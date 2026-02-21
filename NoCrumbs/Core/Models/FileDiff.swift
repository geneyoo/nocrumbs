import Foundation

struct FileDiff: Identifiable, Equatable {
    let id: UUID
    let oldPath: String?
    let newPath: String?
    let hunks: [DiffHunk]
    var status: FileStatus

    enum FileStatus: Equatable {
        case added, deleted, modified
    }

    var displayPath: String {
        newPath ?? oldPath ?? "(unknown)"
    }

    var fileExtension: String {
        (displayPath as NSString).pathExtension
    }
}

struct DiffHunk: Identifiable, Equatable {
    let id: UUID
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

struct DiffLine: Identifiable, Equatable {
    let id: UUID
    let type: LineType
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    enum LineType: Equatable {
        case context, addition, deletion
    }
}
