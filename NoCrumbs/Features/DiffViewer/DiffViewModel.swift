import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "DiffViewer")

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

        currentEventID = event.id
        isLoading = true
        error = nil

        let paths = fileChanges.map(\.filePath)
        let projectPath = event.projectPath
        let eventID = event.id

        Task { [weak self] in
            do {
                let provider = GitProvider()
                let raw = try await provider.diffForFiles(paths, at: projectPath)
                guard let self, self.currentEventID == eventID else { return }
                let diffs = DiffParser.parse(raw)
                self.fileDiffs = diffs
                if self.selectedFileID == nil || !diffs.contains(where: { $0.id == self.selectedFileID }) {
                    self.selectedFileID = diffs.first?.id
                }
                self.buildLinePairs()
                self.isLoading = false
            } catch {
                guard let self, self.currentEventID == eventID else { return }
                logger.error("Failed to load diff: \(error.localizedDescription)")
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func selectFile(_ id: UUID) {
        selectedFileID = id
        buildLinePairs()
    }

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
                    // Collect consecutive deletions and additions to pair them
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
