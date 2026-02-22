import Foundation

// MARK: - Per-File Diff Stat

struct DiffStat: Equatable, Sendable {
    let filePath: String
    let status: FileDiff.FileStatus
    let additions: Int
    let deletions: Int

    var totalChanges: Int { additions + deletions }

    static func from(_ fileDiff: FileDiff) -> DiffStat {
        var adds = 0
        var dels = 0
        for hunk in fileDiff.hunks {
            for line in hunk.lines {
                switch line.type {
                case .addition: adds += 1
                case .deletion: dels += 1
                case .context: break
                }
            }
        }
        return DiffStat(
            filePath: fileDiff.displayPath,
            status: fileDiff.status,
            additions: adds,
            deletions: dels
        )
    }
}

// MARK: - Per-Prompt Diff Stat

struct PromptDiffStat: Equatable, Sendable {
    let eventID: UUID
    let fileStats: [DiffStat]

    var totalAdditions: Int { fileStats.reduce(0) { $0 + $1.additions } }
    var totalDeletions: Int { fileStats.reduce(0) { $0 + $1.deletions } }
    var totalFiles: Int { fileStats.count }
}

// MARK: - Aggregated File Stat (session-wide, deduped)

struct AggregatedFileStat: Identifiable, Equatable {
    var id: String { filePath }
    let filePath: String
    let status: FileDiff.FileStatus
    let totalAdditions: Int
    let totalDeletions: Int
    let promptCount: Int

    var totalChanges: Int { totalAdditions + totalDeletions }
}
