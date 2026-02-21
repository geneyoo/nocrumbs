import Foundation

protocol VCSProvider: Sendable {
    var type: VCSType { get }
    func currentBranch(at path: String) async throws -> String
    func isValidCommit(_ hash: String, at path: String) async throws -> Bool
    func diff(for hash: String, at path: String) async throws -> String
    func uncommittedDiff(at path: String) async throws -> String
    func diffForFiles(_ filePaths: [String], at path: String) async throws -> String
}
