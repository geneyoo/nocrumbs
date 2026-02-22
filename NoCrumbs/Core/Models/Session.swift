import Foundation

struct Session: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let projectPath: String
    let startedAt: Date
    var lastActivityAt: Date
    var customName: String?
}

enum SessionState: Equatable, Sendable {
    case live  // Recent prompt/tool activity within 5 min
    case interrupted  // Most recent event is Stop
    case ended  // SessionEnd received
    case idle  // Stale (>5 min, no Stop/End)
}
