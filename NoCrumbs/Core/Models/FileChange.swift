import Foundation

struct FileChange: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let eventID: UUID
    let filePath: String
    let toolName: String
    let timestamp: Date
}
