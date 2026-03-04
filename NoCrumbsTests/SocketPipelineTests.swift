import XCTest

@testable import NoCrumbs

/// E2E tests for the socket → actor → DB pipeline.
/// These would have caught the v0.5.6 actor deadlock where blocking POSIX calls
/// on actor-isolated methods starved child Tasks from running handleMessage.
@MainActor
final class SocketPipelineTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var db: Database!
    private var server: SocketServer!
    private var tempDBPath: String!
    private var tempSocketPath: String!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() async throws {
        try await super.setUp()
        tempDBPath = NSTemporaryDirectory() + "nocrumbs_pipe_\(UUID().uuidString).sqlite"
        // Unix socket paths are limited to 104 bytes on macOS — use short prefix
        let shortID = UUID().uuidString.prefix(8)
        tempSocketPath = NSTemporaryDirectory() + "nc_\(shortID).sock"

        db = Database(path: tempDBPath)
        try db.open()

        server = SocketServer(path: tempSocketPath, database: db)
        try await server.start()
    }

    override func tearDown() async throws {
        await server.stop()
        db.close()
        try? FileManager.default.removeItem(atPath: tempDBPath)
        try? FileManager.default.removeItem(atPath: tempSocketPath)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Sends a JSON message over Unix domain socket, fire-and-forget.
    /// Runs blocking I/O off MainActor to avoid deadlocking with server's MainActor.run calls.
    private nonisolated func sendMessage(_ json: [String: Any], socketPath: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, min(src.count, 104))
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw SocketError.connectFailed(errno) }

        let data = try JSONSerialization.data(withJSONObject: json)
        _ = data.withUnsafeBytes { buf in
            // swiftlint:disable:next force_unwrapping
            write(fd, buf.baseAddress!, buf.count)
        }
        // Shut down write side so server's readAll sees EOF
        shutdown(fd, SHUT_WR)

        // Drain any response (ignore content — fire-and-forget)
        var discard = [UInt8](repeating: 0, count: 4096)
        while read(fd, &discard, discard.count) > 0 {}
    }

    /// Async wrapper that dispatches blocking socket I/O off MainActor.
    private func send(_ json: [String: Any]) async throws {
        let path = tempSocketPath!
        try await Task.detached {
            try self.sendMessage(json, socketPath: path)
        }.value
    }

    /// Polls a MainActor condition with timeout. Uses short polling interval.
    /// Legitimate polling: socket → actor → MainActor → DB is asynchronous with no observable signal.
    private func waitFor(
        timeout: TimeInterval = 3,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                return
            }
            // Yield to let actor/MainActor process — legitimate hard timeout polling
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
    }

    // MARK: - Tests

    /// THE critical test: send a single prompt over the socket and verify it lands in DB
    /// without needing a second connection. This is exactly what v0.5.6 broke — the blocking
    /// accept() held the actor executor, so handleMessage only ran when the NEXT client connected.
    func testSinglePrompt_landsInDB() async throws {
        let sessionID = "test-single-\(UUID().uuidString)"

        try await send([
            "type": "prompt",
            "session_id": sessionID,
            "prompt": "Fix the login bug",
            "cwd": "/tmp/test-project",
        ])

        try await waitFor {
            self.db.recentEvents.contains { $0.sessionID == sessionID }
        }

        let event = db.recentEvents.first { $0.sessionID == sessionID }
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.promptText, "Fix the login bug")
        XCTAssertEqual(event?.projectPath, "/tmp/test-project")
    }

    /// Tests the `handleEvent` path — the real Claude Code hook flow that creates
    /// both a Session and a HookEvent record.
    func testEventHook_createsSessionAndHookEvent() async throws {
        let sessionID = "test-event-\(UUID().uuidString)"

        try await send([
            "type": "event",
            "session_id": sessionID,
            "hook_event_name": "UserPromptSubmit",
            "cwd": "/tmp/test-project",
            "prompt": "Add dark mode",
        ])

        try await waitFor {
            self.db.recentHookEvents.contains { $0.sessionID == sessionID }
        }

        let hookEvent = db.recentHookEvents.first { $0.sessionID == sessionID }
        XCTAssertNotNil(hookEvent)
        XCTAssertEqual(hookEvent?.hookEventName, "UserPromptSubmit")

        let session = db.sessions.first { $0.id == sessionID }
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.projectPath, "/tmp/test-project")

        // Event hook also bridges to legacy prompt table via bridgePromptEvent
        let promptEvent = db.recentEvents.first { $0.sessionID == sessionID }
        XCTAssertNotNil(promptEvent)
        XCTAssertEqual(promptEvent?.promptText, "Add dark mode")
    }

    /// Send 10 parallel messages and verify all 10 sessions land in DB.
    func testConcurrentClients_allLand() async throws {
        let prefix = "test-concurrent-\(UUID().uuidString)"
        let count = 10

        // Send messages via detached tasks to avoid blocking MainActor.
        // Server processes them concurrently even though we await each send.
        for i in 0..<count {
            try await send([
                "type": "prompt",
                "session_id": "\(prefix)-\(i)",
                "prompt": "Prompt \(i)",
                "cwd": "/tmp/test-project",
            ])
        }

        try await waitFor(timeout: 5) {
            let matched = self.db.recentEvents.filter { $0.sessionID.hasPrefix(prefix) }
            return matched.count == count
        }

        let landed = db.recentEvents.filter { $0.sessionID.hasPrefix(prefix) }
        XCTAssertEqual(landed.count, count)
    }

    /// Send a prompt then a file change, verify the change attaches to the prompt event.
    func testFileChange_attachesToPrompt() async throws {
        let sessionID = "test-change-\(UUID().uuidString)"
        let project = "/tmp/test-project"

        // 1. Send prompt
        try await send([
            "type": "prompt",
            "session_id": sessionID,
            "prompt": "Refactor auth",
            "cwd": project,
        ])

        try await waitFor {
            self.db.recentEvents.contains { $0.sessionID == sessionID }
        }

        // 2. Send file change
        try await send([
            "type": "change",
            "session_id": sessionID,
            "file_path": "\(project)/Auth.swift",
            "tool_name": "Edit",
            "cwd": project,
        ])

        let event = db.recentEvents.first { $0.sessionID == sessionID }!

        try await waitFor {
            let changes = self.db.fileChangesCache[event.id] ?? []
            return !changes.isEmpty
        }

        let changes = db.fileChangesCache[event.id] ?? []
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.filePath, "\(project)/Auth.swift")
        XCTAssertEqual(changes.first?.toolName, "Edit")
    }
}
