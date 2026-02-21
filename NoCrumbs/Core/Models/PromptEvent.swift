import Foundation

struct PromptEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: String
    let projectPath: String
    let promptText: String?
    let timestamp: Date
    let vcs: VCSType?
}
