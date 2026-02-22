import Foundation

struct CommitTemplate: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let body: String
    let isActive: Bool
    let createdAt: Date
}
