import Foundation

@Observable @MainActor
final class DiffViewModel {
    private(set) var fileDiffs: [FileDiff] = []
    var selectedFileID: UUID?
    private(set) var isLoading = false
    private(set) var error: String?

    private(set) var linePairs: [(left: DiffLine?, right: DiffLine?)] = []

    private var currentEventID: UUID?

    var selectedFile: FileDiff? {
        guard let id = selectedFileID else { return fileDiffs.first }
        return fileDiffs.first { $0.id == id }
    }

    func load(event: PromptEvent, fileChanges: [FileChange]) {
        guard event.vcs == .git else {
            fileDiffs = []
            linePairs = []
            error = "No VCS detected for this event"
            return
        }

        guard !fileChanges.isEmpty else {
            fileDiffs = []
            linePairs = []
            isLoading = false
            return
        }

        currentEventID = event.id
        isLoading = true
        error = nil

        let absolutePaths = fileChanges.map(\.filePath)
        let projectPath = event.projectPath

        // Convert to relative paths for git commands
        let relativePaths = absolutePaths.map { path -> String in
            if path.hasPrefix(projectPath + "/") {
                return String(path.dropFirst(projectPath.count + 1))
            }
            return path
        }

        let eventID = event.id

        Task { [weak self] in
            do {
                let provider = GitProvider()
                var allDiffs: [FileDiff] = []

                // 1. Get git diff HEAD for tracked modified files
                let raw = try await provider.diffForFiles(relativePaths, at: projectPath)
                let parsedDiffs = DiffParser.parse(raw)
                allDiffs.append(contentsOf: parsedDiffs)

                // 2. Find files not in the git diff output (untracked or committed)
                let diffedPaths = Set(parsedDiffs.compactMap { $0.newPath ?? $0.oldPath })
                let missingRelPaths = relativePaths.filter { !diffedPaths.contains($0) }

                if !missingRelPaths.isEmpty {
                    // Check which missing files are untracked (new)
                    let untracked = try await provider.untrackedFiles(missingRelPaths, at: projectPath)

                    for relPath in missingRelPaths {
                        let absPath = projectPath + "/" + relPath
                        if untracked.contains(relPath) {
                            // New file — read content and create synthetic diff
                            if let synthetic = Self.syntheticDiff(for: relPath, absolutePath: absPath, status: .added) {
                                allDiffs.append(synthetic)
                            }
                        }
                        // else: committed file — omit (no diff to show)
                    }
                }

                guard let self, self.currentEventID == eventID else { return }
                self.fileDiffs = allDiffs
                if self.selectedFileID == nil || !allDiffs.contains(where: { $0.id == self.selectedFileID }) {
                    self.selectedFileID = allDiffs.first?.id
                }
                self.buildLinePairs()
                self.isLoading = false
            } catch {
                guard let self, self.currentEventID == eventID else { return }
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func selectFile(_ id: UUID) {
        selectedFileID = id
        buildLinePairs()
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
                        pairs.append((
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
