import XCTest

@testable import NoCrumbs

/// Integration tests using a real temporary hg repo. Skipped if hg is not installed.
final class MercurialProviderTests: XCTestCase {

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var repo: HgTestRepo!
    private let provider = MercurialProvider()

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(HgTestRepo.isHgAvailable(), "hg not installed — skipping Mercurial tests")
        repo = try HgTestRepo()
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

    func testCurrentBranch() async throws {
        try repo.commit(file: "init.txt", content: "hello")
        let branch = try await provider.currentBranch(at: repo.path)
        XCTAssertEqual(branch, "default")
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

    func testDiffFromBase() async throws {
        try repo.commit(file: "file.swift", content: "let a = 1\n")
        let baseHash = try await provider.currentHead(at: repo.path)

        // Modify the file (uncommitted)
        try "let a = 2\n".write(toFile: "\(repo.path)/file.swift", atomically: true, encoding: .utf8)

        let diff = try await provider.diffFromBase(baseHash, filePaths: ["file.swift"], at: repo.path)
        XCTAssertTrue(diff.contains("-let a = 1"))
        XCTAssertTrue(diff.contains("+let a = 2"))
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

// MARK: - HgTestRepo Helper

/// Creates a temporary Mercurial repository for testing.
final class HgTestRepo {
    let path: String

    static func isHgAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["hg", "--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    init() throws {
        let tmp = NSTemporaryDirectory() + "nocrumbs-hg-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        self.path = tmp
        try run("hg", "init")
    }

    func commit(file: String, content: String, message: String? = nil) throws {
        try content.write(toFile: "\(path)/\(file)", atomically: true, encoding: .utf8)
        try run("hg", "add", file)
        try run("hg", "commit", "-m", message ?? "Add \(file)", "--user", "test <test@test.com>")
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
                domain: "HgTestRepo", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output])
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
