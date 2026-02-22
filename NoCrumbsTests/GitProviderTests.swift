import XCTest

@testable import NoCrumbs

/// Integration tests using a real temporary git repo.
final class GitProviderTests: XCTestCase {

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var repo: GitTestRepo!
    private let provider = GitProvider()

    override func setUp() async throws {
        try await super.setUp()
        repo = try GitTestRepo()
    }

    override func tearDown() async throws {
        repo?.cleanup()
        try await super.tearDown()
    }

    func testCurrentHead() async throws {
        try repo.commit(file: "init.txt", content: "hello")
        let head = try await provider.currentHead(at: repo.path)
        XCTAssertEqual(head.count, 40)
        XCTAssertTrue(head.allSatisfy { $0.isHexDigit })
    }

    func testIsValidCommit_valid() async throws {
        try repo.commit(file: "a.txt", content: "a")
        let head = try await provider.currentHead(at: repo.path)
        let valid = try await provider.isValidCommit(head, at: repo.path)
        XCTAssertTrue(valid)
    }

    func testIsValidCommit_invalid() async throws {
        try repo.commit(file: "a.txt", content: "a")
        let fake = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let valid = try await provider.isValidCommit(fake, at: repo.path)
        XCTAssertFalse(valid)
    }

    func testIsValidCommit_afterReset() async throws {
        try repo.commit(file: "a.txt", content: "a")
        try repo.commit(file: "b.txt", content: "b")
        let oldHead = try await provider.currentHead(at: repo.path)

        // Hard reset to lose the commit, then prune
        try repo.run("git", "reset", "--hard", "HEAD~1")
        try repo.run("git", "reflog", "expire", "--expire=now", "--all")
        try repo.run("git", "gc", "--prune=now", "--aggressive")

        let valid = try await provider.isValidCommit(oldHead, at: repo.path)
        XCTAssertFalse(valid)
    }

    func testDiffFromBase() async throws {
        try repo.commit(file: "file.swift", content: "let a = 1\n")
        let baseHash = try await provider.currentHead(at: repo.path)

        // Modify the file (unstaged)
        try "let a = 2\n".write(toFile: "\(repo.path)/file.swift", atomically: true, encoding: .utf8)

        let diff = try await provider.diffFromBase(baseHash, filePaths: ["file.swift"], at: repo.path)
        XCTAssertTrue(diff.contains("-let a = 1"))
        XCTAssertTrue(diff.contains("+let a = 2"))
    }

    func testDiffFromBase_invalidHash() async throws {
        try repo.commit(file: "a.txt", content: "a")
        let fake = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        do {
            _ = try await provider.diffFromBase(fake, filePaths: ["a.txt"], at: repo.path)
            XCTFail("Expected VCSError.commandFailed")
        } catch let error as VCSError {
            if case .commandFailed(_, let code, _) = error {
                XCTAssertEqual(code, 128)
            } else {
                XCTFail("Unexpected error variant")
            }
        }
    }

    func testHeadBefore() async throws {
        try repo.commit(file: "a.txt", content: "a")
        let head = try await provider.currentHead(at: repo.path)
        // headBefore a future date should return current head
        let future = Date().addingTimeInterval(3600)
        let result = try await provider.headBefore(future, at: repo.path)
        XCTAssertEqual(result, head)
    }

    func testUntrackedFiles() async throws {
        try repo.commit(file: "tracked.txt", content: "tracked")
        try "untracked content".write(
            toFile: "\(repo.path)/untracked.txt", atomically: true, encoding: .utf8
        )
        let untracked = try await provider.untrackedFiles(
            ["tracked.txt", "untracked.txt"], at: repo.path
        )
        XCTAssertTrue(untracked.contains("untracked.txt"))
        XCTAssertFalse(untracked.contains("tracked.txt"))
    }
}

// MARK: - GitTestRepo Helper

/// Creates a temporary git repository for testing.
final class GitTestRepo {
    let path: String

    init() throws {
        let tmp = NSTemporaryDirectory() + "nocrumbs-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        self.path = tmp
        try run("git", "init")
        try run("git", "config", "user.email", "test@test.com")
        try run("git", "config", "user.name", "Test")
    }

    func commit(file: String, content: String, message: String? = nil) throws {
        try content.write(toFile: "\(path)/\(file)", atomically: true, encoding: .utf8)
        try run("git", "add", file)
        try run("git", "commit", "-m", message ?? "Add \(file)")
    }

    @discardableResult
    func run(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let output = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GitTestRepo", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output])
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
