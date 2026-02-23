import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "DiffVM")

@Observable @MainActor
final class DiffViewModel {
    private(set) var fileDiffs: [FileDiff] = []
    var selectedFileID: UUID?
    private(set) var isLoading = false
    private(set) var error: String?

    private(set) var linePairs: [(left: DiffLine?, right: DiffLine?)] = []

    private var currentEventID: UUID?
    private var loadTask: Task<Void, Never>?
    private var diffCache: [UUID: [FileDiff]] = [:]
    private var provider: any VCSProvider
    private let injectedProvider: Bool

    init(provider: (any VCSProvider)? = nil) {
        self.provider = provider ?? GitProvider()
        self.injectedProvider = provider != nil
    }

    var selectedFile: FileDiff? {
        guard let id = selectedFileID else { return fileDiffs.first }
        return fileDiffs.first { $0.id == id }
    }

    func load(event: PromptEvent, fileChanges: [FileChange]) {
        loadTask?.cancel()

        // Debug mock data: no real repos exist — synthesize FileDiffs from metadata
        if DebugConfiguration.isMockDataEnabled {
            loadMockDiffs(event: event, fileChanges: fileChanges)
            return
        }

        guard let vcs = event.vcs else {
            fileDiffs = []
            linePairs = []
            error = "No VCS detected for this event"
            logger.warning("load: no VCS for event \(event.id)")
            return
        }

        // Use the correct provider for this event's VCS type (unless test-injected)
        if !injectedProvider {
            provider = makeProvider(for: vcs)
        }

        guard !fileChanges.isEmpty else {
            fileDiffs = []
            linePairs = []
            isLoading = false
            logger.info("load: no fileChanges for event \(event.id)")
            return
        }

        currentEventID = event.id

        // Return cached results instantly if available
        if let cached = diffCache[event.id] {
            error = nil
            applyDiffs(cached)
            return
        }

        isLoading = true
        error = nil

        let projectPath = event.projectPath

        // Convert to relative paths for git commands, filtering out paths outside the repo
        let relativePaths = fileChanges.compactMap { change -> String? in
            let path = change.filePath
            guard path.hasPrefix(projectPath + "/") else {
                logger.info("skipping out-of-repo path: \(path)")
                return nil
            }
            return String(path.dropFirst(projectPath.count + 1))
        }

        guard !relativePaths.isEmpty else {
            fileDiffs = []
            linePairs = []
            isLoading = false
            logger.info("load: all file paths outside repo for event \(event.id)")
            return
        }

        let eventID = event.id
        let baseHash = event.baseCommitHash

        logger.info("load: event=\(eventID) baseHash=\(baseHash ?? "nil") files=\(relativePaths.count) projectPath=\(projectPath)")
        for (i, rp) in relativePaths.enumerated() {
            logger.info("  file[\(i)]: \(rp)")
        }

        let eventTimestamp = event.timestamp

        loadTask = Task { [weak self] in
            await self?.performLoad(
                eventID: eventID, baseHash: baseHash,
                relativePaths: relativePaths, projectPath: projectPath,
                eventTimestamp: eventTimestamp
            )
        }
    }

    private func loadMockDiffs(event: PromptEvent, fileChanges: [FileChange]) {
        guard !fileChanges.isEmpty else {
            fileDiffs = []
            linePairs = []
            isLoading = false
            return
        }
        let projectPath = event.projectPath
        let diffs = fileChanges.compactMap { change -> FileDiff? in
            let relativePath: String
            if change.filePath.hasPrefix(projectPath + "/") {
                relativePath = String(change.filePath.dropFirst(projectPath.count + 1))
            } else {
                relativePath = (change.filePath as NSString).lastPathComponent
            }
            let status: FileDiff.FileStatus = change.toolName == "Write" ? .added : .modified
            let placeholder = status == .added
                ? "// New file created by \(change.toolName)"
                : "// Modified by \(change.toolName)"
            let line = DiffLine(id: UUID(), type: .addition, text: placeholder, oldLineNumber: nil, newLineNumber: 1)
            let hunk = DiffHunk(id: UUID(), oldStart: 0, oldCount: 0, newStart: 1, newCount: 1, lines: [line])
            return FileDiff(id: UUID(), oldPath: status == .modified ? relativePath : nil, newPath: relativePath, hunks: [hunk], status: status)
        }
        error = nil
        applyDiffs(diffs)
    }

    private func performLoad(
        eventID: UUID, baseHash: String?,
        relativePaths: [String], projectPath: String,
        eventTimestamp: Date
    ) async {
        do {
            // If baseHash is nil, attempt live capture as fallback
            var resolvedHash = baseHash
            if resolvedHash == nil {
                logger.info("baseHash nil for event \(eventID) — attempting live HEAD capture")
                resolvedHash = try? await provider.currentHead(at: projectPath)
                if let hash = resolvedHash {
                    logger.info("Live capture succeeded: \(hash)")
                    await MainActor.run {
                        try? Database.shared.updateBaseCommitHash(hash, forEventID: eventID)
                    }
                }
            }

            guard let baseHash = resolvedHash else {
                guard currentEventID == eventID else { return }
                error = "Could not determine baseline commit"
                isLoading = false
                logger.warning("no baseHash — live capture also failed")
                return
            }

            let isValid = try await provider.isValidCommit(baseHash, at: projectPath)
            guard !Task.isCancelled else { return }

            // If the original commit was rebased/stripped, try finding the nearest ancestor
            if !isValid {
                logger.warning("baseHash \(baseHash) is dangling — trying headBefore fallback")
                if let fallbackHash = try? await provider.headBefore(eventTimestamp, at: projectPath),
                    try await provider.isValidCommit(fallbackHash, at: projectPath)
                {
                    logger.info("headBefore fallback succeeded: \(fallbackHash)")
                    await MainActor.run {
                        try? Database.shared.updateBaseCommitHash(fallbackHash, forEventID: eventID)
                    }
                    // Continue with fallback hash
                    return await performDiff(
                        eventID: eventID, baseHash: fallbackHash,
                        relativePaths: relativePaths, projectPath: projectPath
                    )
                }

                guard currentEventID == eventID else { return }
                error = "Commit \(String(baseHash.prefix(7))) no longer exists — likely rebased or reset"
                isLoading = false
                logger.warning("baseHash \(baseHash) is dangling, headBefore fallback also failed")
                return
            }

            await performDiff(
                eventID: eventID, baseHash: baseHash,
                relativePaths: relativePaths, projectPath: projectPath
            )
        } catch {
            guard !Task.isCancelled, currentEventID == eventID else { return }
            logger.error("load failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func performDiff(
        eventID: UUID, baseHash: String,
        relativePaths: [String], projectPath: String
    ) async {
        do {
            let raw = try await provider.diffFromBase(baseHash, filePaths: relativePaths, at: projectPath)
            guard !Task.isCancelled else { return }
            logger.info("diff \(baseHash.prefix(7)) returned \(raw.count) chars")
            var allDiffs = DiffParser.parse(raw)
            logger.info("parsed \(allDiffs.count) file diffs")

            try await Self.appendUntrackedDiffs(
                to: &allDiffs, relativePaths: relativePaths,
                projectPath: projectPath, provider: provider
            )

            guard !Task.isCancelled, currentEventID == eventID else { return }
            logger.info("total diffs: \(allDiffs.count)")
            diffCache[eventID] = allDiffs
            applyDiffs(allDiffs)
        } catch {
            guard !Task.isCancelled, currentEventID == eventID else { return }
            logger.error("diff failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func applyDiffs(_ diffs: [FileDiff]) {
        fileDiffs = diffs
        if selectedFileID == nil || !diffs.contains(where: { $0.id == selectedFileID }) {
            selectedFileID = diffs.first?.id
        }
        buildLinePairs()
        isLoading = false
    }

    func selectFile(_ id: UUID) {
        selectedFileID = id
        buildLinePairs()
    }

    // MARK: - Untracked Files

    private static func appendUntrackedDiffs(
        to allDiffs: inout [FileDiff], relativePaths: [String],
        projectPath: String, provider: any VCSProvider
    ) async throws {
        let diffedPaths = Set(allDiffs.compactMap { $0.newPath ?? $0.oldPath })
        let missingRelPaths = relativePaths.filter { !diffedPaths.contains($0) }
        guard !missingRelPaths.isEmpty else { return }

        logger.info("\(missingRelPaths.count) files not in diff: \(missingRelPaths)")
        let untracked = try await provider.untrackedFiles(missingRelPaths, at: projectPath)
        logger.info("untracked: \(untracked)")
        for relPath in missingRelPaths where untracked.contains(relPath) {
            let absPath = projectPath + "/" + relPath
            if let synthetic = syntheticDiff(for: relPath, absolutePath: absPath, status: .added) {
                allDiffs.append(synthetic)
            }
        }
    }

    // MARK: - Synthetic Diff

    private static func syntheticDiff(for relativePath: String, absolutePath: String, status: FileDiff.FileStatus) -> FileDiff? {
        guard let content = try? String(contentsOfFile: absolutePath, encoding: .utf8) else { return nil }
        let fileLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let diffLines: [DiffLine] = fileLines.enumerated().map { index, text in
            DiffLine(
                id: UUID(),
                type: .addition,
                text: text,
                oldLineNumber: nil,
                newLineNumber: index + 1
            )
        }

        let hunk = DiffHunk(
            id: UUID(),
            oldStart: 0,
            oldCount: 0,
            newStart: 1,
            newCount: fileLines.count,
            lines: diffLines
        )

        return FileDiff(
            id: UUID(),
            oldPath: nil,
            newPath: relativePath,
            hunks: [hunk],
            status: status
        )
    }

    // MARK: - Line Pairing

    private func buildLinePairs() {
        guard let file = selectedFile else {
            linePairs = []
            return
        }

        var pairs: [(left: DiffLine?, right: DiffLine?)] = []

        for hunk in file.hunks {
            var i = 0
            let lines = hunk.lines
            while i < lines.count {
                let line = lines[i]
                switch line.type {
                case .context:
                    pairs.append((left: line, right: line))
                    i += 1

                case .deletion:
                    var deletions: [DiffLine] = []
                    while i < lines.count, lines[i].type == .deletion {
                        deletions.append(lines[i])
                        i += 1
                    }
                    var additions: [DiffLine] = []
                    while i < lines.count, lines[i].type == .addition {
                        additions.append(lines[i])
                        i += 1
                    }
                    let maxCount = max(deletions.count, additions.count)
                    for j in 0..<maxCount {
                        pairs.append(
                            (
                                left: j < deletions.count ? deletions[j] : nil,
                                right: j < additions.count ? additions[j] : nil
                            ))
                    }

                case .addition:
                    pairs.append((left: nil, right: line))
                    i += 1
                }
            }
        }

        linePairs = pairs
    }
}
