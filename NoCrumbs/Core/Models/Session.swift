import Foundation

struct Session: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let projectPath: String
    let startedAt: Date
    var lastActivityAt: Date
}
