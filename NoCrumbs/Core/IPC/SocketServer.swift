import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "Socket")

actor SocketServer {
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var listening = false

    static var defaultSocketPath: String {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NoCrumbs/nocrumbs.sock").path
    }

    init(path: String = SocketServer.defaultSocketPath) {
        self.socketPath = path
    }

    func start() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Remove stale socket
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw SocketError.createFailed(errno)
        }

        var addr = makeUnixAddr(path: socketPath)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            throw SocketError.bindFailed(errno)
        }

        guard listen(serverFD, 5) == 0 else {
            close(serverFD)
            throw SocketError.listenFailed(errno)
        }

        listening = true
        logger.info("[NC:Socket] Listening on \(self.socketPath)")

        // Accept loop in detached task
        let fd = serverFD
        let path = socketPath
        Task.detached { [weak self] in
            await self?.acceptLoop(fd: fd, path: path)
        }
    }

    func stop() {
        listening = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
        logger.info("[NC:Socket] Stopped")
    }

    private func acceptLoop(fd: Int32, path: String) async {
        while listening {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(fd, sockPtr, &clientLen)
                }
            }

            guard clientFD >= 0 else {
                if listening { logger.warning("[NC:Socket] Accept failed: \(errno)") }
                break
            }

            let data = readAll(fd: clientFD)

            if !data.isEmpty {
                await handleMessage(data, clientFD: clientFD)
            } else {
                close(clientFD)
            }
        }
    }

    private func readAll(fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[..<n])
        }
        return data
    }

    private func handleMessage(_ data: Data, clientFD: Int32) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            logger.warning("[NC:Socket] Invalid message")
            close(clientFD)
            return
        }

        logger.info("[NC:Socket] Received: \(type)")

        let db = await MainActor.run { Database.shared }

        switch type {
        case "event":
            close(clientFD)
            await handleEvent(json, db: db)
        case "prompt":
            close(clientFD)
            await handlePrompt(json, db: db)
        case "change":
            close(clientFD)
            await handleChange(json, db: db)
        case "file-descriptions":
            close(clientFD)
            await handleFileDescriptions(json, db: db)
        case "session-rename":
            close(clientFD)
            await handleSessionRename(json, db: db)
        case "query-prompts":
            await handleQueryPrompts(json, db: db, clientFD: clientFD)
        case "template":
            await handleTemplate(json, db: db, clientFD: clientFD)
        default:
            logger.warning("[NC:Socket] Unknown type: \(type)")
            close(clientFD)
        }
    }

    // MARK: - Generic Event Handler

    private func handleEvent(_ json: [String: Any], db: Database) async {
        guard let sessionID = json["session_id"] as? String,
            let hookEventName = json["hook_event_name"] as? String,
            let cwd = json["cwd"] as? String
        else {
            logger.warning("[NC:Socket] Malformed event message")
            return
        }

        let now = Date()

        // Build payload JSON from remaining interesting fields
        var payloadDict: [String: Any] = [:]
        let payloadKeys = [
            "prompt", "tool_name", "tool_input", "stop_hook_active",
            "agent_id", "agent_type", "transcript_path",
        ]
        for key in payloadKeys {
            if let value = json[key] { payloadDict[key] = value }
        }
        let payloadJSON: String? =
            payloadDict.isEmpty
            ? nil
            : {
                guard let data = try? JSONSerialization.data(withJSONObject: payloadDict) else { return nil }
                return String(data: data, encoding: .utf8)
            }()

        let hookEvent = HookEvent(
            id: UUID(),
            sessionID: sessionID,
            hookEventName: hookEventName,
            projectPath: cwd,
            timestamp: now,
            payload: payloadJSON
        )

        let session = Session(id: sessionID, projectPath: cwd, startedAt: now, lastActivityAt: now)

        await MainActor.run {
            do {
                try db.upsertSession(session)
                try db.insertHookEvent(hookEvent)
            } catch {
                logger.error("[NC:Socket] DB error (event): \(error.localizedDescription)")
            }
        }

        // Bridge to legacy tables for backward compat
        switch hookEventName {
        case "UserPromptSubmit":
            await bridgePromptEvent(json, sessionID: sessionID, cwd: cwd, now: now, db: db)
        case "PostToolUse":
            await bridgeFileChange(json, sessionID: sessionID, cwd: cwd, now: now, db: db)
        default:
            break
        }

        logger.info("[NC:Socket] Stored event \(hookEventName) for session \(sessionID.prefix(8))")
    }

    private func bridgePromptEvent(
        _ json: [String: Any], sessionID: String, cwd: String, now: Date, db: Database
    ) async {
        // Fall back to transcript extraction for subagent sessions with no prompt
        let prompt: String? = (json["prompt"] as? String)
            ?? (json["transcript_path"] as? String).flatMap { extractPromptFromTranscript($0) }

        // Backfill orphan if prompt text is available and an orphan exists for this session
        if let prompt {
            let backfilled: Bool = await MainActor.run {
                if let orphan = db.recentEvents.first(where: { $0.sessionID == sessionID && $0.promptText == nil }) {
                    do {
                        try db.updatePromptText(prompt, forEventID: orphan.id)
                        logger.info("[NC:Socket] Bridged backfill orphan \(orphan.id.uuidString)")
                        return true
                    } catch {
                        logger.error("[NC:Socket] Bridge backfill failed: \(error.localizedDescription)")
                    }
                }
                return false
            }
            if backfilled { return }
        }

        let vcsType = VCSDetector.detect(at: cwd)

        var baseHash: String?
        if let vcsType {
            baseHash = try? await makeProvider(for: vcsType).currentHead(at: cwd)
        }

        let event = PromptEvent(
            id: UUID(),
            sessionID: sessionID,
            projectPath: cwd,
            promptText: prompt,
            timestamp: now,
            vcs: vcsType,
            baseCommitHash: baseHash
        )

        await MainActor.run {
            do {
                try db.insertPromptEvent(event)
                logger.info("[NC:Socket] Bridged prompt event \(event.id.uuidString)")
            } catch {
                logger.error("[NC:Socket] Bridge prompt error: \(error.localizedDescription)")
            }
        }
    }

    private func bridgeFileChange(
        _ json: [String: Any], sessionID: String, cwd: String, now: Date, db: Database
    ) async {
        let toolName = json["tool_name"] as? String ?? "unknown"

        // Only bridge Write/Edit tools with a file_path
        guard toolName == "Write" || toolName == "Edit",
            let toolInput = json["tool_input"] as? [String: Any],
            let filePath = toolInput["file_path"] as? String
        else {
            return
        }

        let eventID: UUID? = await MainActor.run {
            db.recentEvents.first(where: { $0.sessionID == sessionID })?.id
        }

        guard let eventID else {
            // No prompt event yet — create placeholder (same as legacy handleChange)
            // For subagent worktree sessions, try to extract task description from transcript
            let transcriptPrompt: String? = (json["transcript_path"] as? String)
                .flatMap { extractPromptFromTranscript($0) }

            let vcsType = VCSDetector.detect(at: cwd)
            var baseHash: String?
            if let vcsType {
                baseHash = try? await makeProvider(for: vcsType).currentHead(at: cwd)
            }
            let placeholderEvent = PromptEvent(
                id: UUID(),
                sessionID: sessionID,
                projectPath: cwd,
                promptText: transcriptPrompt,
                timestamp: now,
                vcs: vcsType,
                baseCommitHash: baseHash
            )
            let change = FileChange(
                id: UUID(),
                eventID: placeholderEvent.id,
                filePath: filePath,
                toolName: toolName,
                timestamp: now
            )

            await MainActor.run {
                do {
                    try db.insertPromptEvent(placeholderEvent)
                    try db.insertFileChange(change)
                    logger.info("[NC:Socket] Bridged orphaned change \(filePath)")
                } catch {
                    logger.error("[NC:Socket] Bridge orphan error: \(error.localizedDescription)")
                }
            }
            return
        }

        let change = FileChange(
            id: UUID(),
            eventID: eventID,
            filePath: filePath,
            toolName: toolName,
            timestamp: now
        )

        await MainActor.run {
            do {
                try db.insertFileChange(change)
                logger.info("[NC:Socket] Bridged change \(filePath)")
            } catch {
                logger.error("[NC:Socket] Bridge change error: \(error.localizedDescription)")
            }
        }
    }

    private func handleFileDescriptions(_ json: [String: Any], db: Database) async {
        guard let sessionID = json["session_id"] as? String,
            let descriptions = json["descriptions"] as? [[String: Any]]
        else {
            logger.warning("[NC:Socket] Malformed file-descriptions message")
            return
        }

        await MainActor.run {
            for desc in descriptions {
                guard let filePath = desc["file_path"] as? String,
                    let description = desc["description"] as? String
                else { continue }
                do {
                    try db.updateFileDescription(description, sessionID: sessionID, filePath: filePath)
                } catch {
                    logger.error("[NC:Socket] Failed to update description for \(filePath): \(error.localizedDescription)")
                }
            }
        }

        logger.info("[NC:Socket] Updated \(descriptions.count) file descriptions for session \(sessionID.prefix(8))")
    }

    private func handleSessionRename(_ json: [String: Any], db: Database) async {
        guard let sessionID = json["session_id"] as? String else {
            logger.warning("[NC:Socket] Malformed session-rename message")
            return
        }

        // Empty string or missing → clear custom name
        let name: String? = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        await MainActor.run {
            do {
                try db.updateSessionName(name, sessionID: sessionID)
            } catch {
                logger.error("[NC:Socket] Failed to rename session: \(error.localizedDescription)")
            }
        }

        logger.info("[NC:Socket] Renamed session \(sessionID.prefix(8)) to \(name ?? "(cleared)")")
    }

    private func handleQueryPrompts(_ json: [String: Any], db: Database, clientFD: Int32) async {
        guard let cwd = json["cwd"] as? String else {
            close(clientFD)
            return
        }

        let response: [String: Any] = await MainActor.run {
            do {
                let since = Date().addingTimeInterval(-3600)  // last hour
                let events = try db.recentEvents(forProject: cwd, since: since)
                let totalFiles = try db.totalFileCount(forProject: cwd, since: since)
                let sessionID = events.first?.sessionID ?? ""

                // Chronological order (oldest first) — intent-setting prompts surface to top
                let prompts: [[String: Any]] = events.reversed().compactMap { event in
                    guard let text = event.promptText else { return nil }
                    let fileCount = (try? db.fileChangeCount(forEventID: event.id)) ?? 0
                    return ["text": text, "file_count": fileCount]
                }

                var response: [String: Any] = [
                    "prompts": prompts,
                    "session_id": sessionID,
                    "total_files": totalFiles,
                    "annotation_enabled": UserDefaults.standard.bool(forKey: "annotationEnabled"),
                    "deep_link_enabled": UserDefaults.standard.bool(forKey: "deepLinkInAnnotation"),
                    "show_prompt_list": UserDefaults.standard.bool(forKey: "showPromptList"),
                    "show_file_count_per_prompt": UserDefaults.standard.bool(forKey: "showFileCountPerPrompt"),
                    "show_session_id": UserDefaults.standard.bool(forKey: "showSessionID"),
                ]
                if let activeBody = db.activeTemplate?.body {
                    response["template"] = activeBody
                }
                return response
            } catch {
                logger.error("[NC:Socket] Query failed: \(error.localizedDescription)")
                return ["prompts": [] as [Any], "session_id": "", "total_files": 0]
            }
        }

        if let responseData = try? JSONSerialization.data(withJSONObject: response) {
            _ = responseData.withUnsafeBytes { buf in
                // swiftlint:disable:next force_unwrapping
                write(clientFD, buf.baseAddress!, buf.count)
            }
        }
        close(clientFD)
    }

    private func handleTemplate(_ json: [String: Any], db: Database, clientFD: Int32) async {
        guard let action = json["action"] as? String else {
            sendJSON(["error": "missing action"], to: clientFD)
            return
        }

        let response: [String: Any]

        switch action {
        case "add":
            guard let name = json["name"] as? String,
                let body = json["body"] as? String
            else {
                sendJSON(["error": "missing name or body"], to: clientFD)
                return
            }
            response = await MainActor.run {
                do {
                    try db.saveCommitTemplate(name: name, body: body)
                    return ["ok": true] as [String: Any]
                } catch {
                    return ["error": error.localizedDescription] as [String: Any]
                }
            }

        case "list":
            let templates: [[String: Any]] = await MainActor.run {
                db.commitTemplates.map { t in
                    ["name": t.name, "body": t.body, "is_active": t.isActive] as [String: Any]
                }
            }
            response = ["templates": templates]

        case "set":
            guard let name = json["name"] as? String else {
                sendJSON(["error": "missing name"], to: clientFD)
                return
            }
            response = await MainActor.run {
                do {
                    try db.setActiveTemplate(name: name)
                    return ["ok": true] as [String: Any]
                } catch {
                    return ["error": error.localizedDescription] as [String: Any]
                }
            }

        case "remove":
            guard let name = json["name"] as? String else {
                sendJSON(["error": "missing name"], to: clientFD)
                return
            }
            response = await MainActor.run {
                do {
                    try db.deleteCommitTemplate(name: name)
                    return ["ok": true] as [String: Any]
                } catch {
                    return ["error": error.localizedDescription] as [String: Any]
                }
            }

        case "preview":
            let rendered: String = await MainActor.run {
                let templateBody = db.activeTemplate?.body ?? "---\n{{summary_line}}"
                let since = Date().addingTimeInterval(-3600)
                let cwd = json["cwd"] as? String ?? ""

                guard let events = try? db.recentEvents(forProject: cwd, since: since) else {
                    return "(no prompt data)"
                }

                let totalFiles = (try? db.totalFileCount(forProject: cwd, since: since)) ?? 0
                let sessionID = events.first?.sessionID ?? ""
                let prompts: [(text: String, fileCount: Int)] = events.compactMap { event in
                    guard let text = event.promptText else { return nil }
                    let fc = (try? db.fileChangeCount(forEventID: event.id)) ?? 0
                    return (text: text, fileCount: fc)
                }

                let context = TemplateContext(
                    promptCount: prompts.count,
                    totalFiles: totalFiles,
                    sessionID: sessionID,
                    prompts: prompts
                )
                return TemplateRenderer.render(templateBody, context: context)
            }
            response = ["preview": rendered]

        default:
            response = ["error": "unknown action: \(action)"]
        }

        sendJSON(response, to: clientFD)
    }

    private nonisolated func sendJSON(_ object: [String: Any], to clientFD: Int32) {
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            _ = data.withUnsafeBytes { buf in
                // swiftlint:disable:next force_unwrapping
                write(clientFD, buf.baseAddress!, buf.count)
            }
        }
        close(clientFD)
    }

    private func handlePrompt(_ json: [String: Any], db: Database) async {
        guard let sessionID = json["session_id"] as? String,
            let prompt = json["prompt"] as? String,
            let cwd = json["cwd"] as? String
        else {
            logger.warning("[NC:Socket] Malformed prompt message")
            return
        }

        let now = Date()

        // Backfill orphan: if a placeholder event exists for this session with nil promptText,
        // update it instead of creating a duplicate
        let backfilled: Bool = await MainActor.run {
            if let orphan = db.recentEvents.first(where: { $0.sessionID == sessionID && $0.promptText == nil }) {
                do {
                    try db.updatePromptText(prompt, forEventID: orphan.id)
                    logger.info("[NC:Socket] Backfilled orphan \(orphan.id.uuidString) with prompt")
                    return true
                } catch {
                    logger.error("[NC:Socket] Backfill failed: \(error.localizedDescription)")
                }
            }
            return false
        }

        if backfilled {
            await MainActor.run {
                try? db.upsertSession(Session(id: sessionID, projectPath: cwd, startedAt: now, lastActivityAt: now))
            }
            return
        }

        let vcsType = VCSDetector.detect(at: cwd)

        // Capture HEAD hash as diff baseline — if this fails, we still proceed (hash is optional)
        var baseHash: String?
        if let vcsType {
            baseHash = try? await makeProvider(for: vcsType).currentHead(at: cwd)
        }

        let session = Session(id: sessionID, projectPath: cwd, startedAt: now, lastActivityAt: now)
        let event = PromptEvent(
            id: UUID(),
            sessionID: sessionID,
            projectPath: cwd,
            promptText: prompt,
            timestamp: now,
            vcs: vcsType,
            baseCommitHash: baseHash
        )

        await MainActor.run {
            do {
                try db.upsertSession(session)
                try db.insertPromptEvent(event)
                logger.info("[NC:Socket] Stored prompt event \(event.id.uuidString)")
            } catch {
                logger.error("[NC:Socket] DB error: \(error.localizedDescription)")
            }
        }
    }

    private func handleChange(_ json: [String: Any], db: Database) async {
        guard let sessionID = json["session_id"] as? String,
            let filePath = json["file_path"] as? String,
            let cwd = json["cwd"] as? String
        else {
            logger.warning("[NC:Socket] Malformed change message")
            return
        }

        let toolName = json["tool_name"] as? String ?? "unknown"

        // Find the most recent event for this session to attach the file change
        let eventID: UUID? = await MainActor.run {
            db.recentEvents.first(where: { $0.sessionID == sessionID })?.id
        }

        guard let eventID else {
            // No prompt event yet — create a placeholder event for orphaned changes
            let now = Date()
            let vcsType = VCSDetector.detect(at: cwd)
            var baseHash: String?
            if let vcsType {
                baseHash = try? await makeProvider(for: vcsType).currentHead(at: cwd)
            }
            let session = Session(id: sessionID, projectPath: cwd, startedAt: now, lastActivityAt: now)
            let event = PromptEvent(
                id: UUID(),
                sessionID: sessionID,
                projectPath: cwd,
                promptText: nil,
                timestamp: now,
                vcs: vcsType,
                baseCommitHash: baseHash
            )
            let change = FileChange(
                id: UUID(),
                eventID: event.id,
                filePath: filePath,
                toolName: toolName,
                timestamp: now
            )

            await MainActor.run {
                do {
                    try db.upsertSession(session)
                    try db.insertPromptEvent(event)
                    try db.insertFileChange(change)
                    logger.info("[NC:Socket] Stored orphaned change \(filePath)")
                } catch {
                    logger.error("[NC:Socket] DB error: \(error.localizedDescription)")
                }
            }
            return
        }

        let change = FileChange(
            id: UUID(),
            eventID: eventID,
            filePath: filePath,
            toolName: toolName,
            timestamp: Date()
        )

        await MainActor.run {
            do {
                try db.insertFileChange(change)
                try db.upsertSession(
                    Session(
                        id: sessionID,
                        projectPath: cwd,
                        startedAt: Date(),
                        lastActivityAt: Date()
                    ))
                logger.info("[NC:Socket] Stored change \(filePath)")
            } catch {
                logger.error("[NC:Socket] DB error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Transcript Extraction

    /// Extracts the first user-role message from a Claude Code transcript JSONL file.
    /// Used to recover the task description for subagent worktree sessions where
    /// `UserPromptSubmit` never fires (no human prompt).
    private nonisolated func extractPromptFromTranscript(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }
        // Read up to 64KB — enough to find the first user message
        let chunk = handle.readData(ofLength: 65536)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                let data = line.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                obj["role"] as? String == "user" || obj["type"] as? String == "human"
            else { continue }
            // Content may be a string or array of content blocks
            if let content = obj["content"] as? String {
                return String(content.prefix(500))
            }
            if let blocks = obj["content"] as? [[String: Any]],
                let first = blocks.first(where: { $0["type"] as? String == "text" }),
                let text = first["text"] as? String
            {
                return String(text.prefix(500))
            }
        }
        return nil
    }
}

enum SocketError: Error, LocalizedError {
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .createFailed(let e): "Socket create failed: \(e)"
        case .bindFailed(let e): "Socket bind failed: \(e)"
        case .listenFailed(let e): "Socket listen failed: \(e)"
        case .connectFailed(let e): "Socket connect failed: \(e)"
        case .sendFailed: "Socket send failed"
        }
    }
}
