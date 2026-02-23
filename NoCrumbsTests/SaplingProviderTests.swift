import XCTest

@testable import NoCrumbs

/// Integration tests using a real temporary sl repo. Skipped if sl is not installed.
final class SaplingProviderTests: XCTestCase {

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var repo: SlTestRepo!
    private let provider = SaplingProvider()

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(SlTestRepo.isSlAvailable(), "sl not installed — skipping Sapling tests")
        repo = try SlTestRepo()
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
        XCTAssertFalse(branch.isEmpty)
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

// MARK: - SlTestRepo Helper

/// Creates a temporary Sapling repository for testing.
final class SlTestRepo {
    let path: String

    static func isSlAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sl", "--version"]
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
        let tmp = NSTemporaryDirectory() + "nocrumbs-sl-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        self.path = tmp
        try run("sl", "init")
    }

    func commit(file: String, content: String, message: String? = nil) throws {
        try content.write(toFile: "\(path)/\(file)", atomically: true, encoding: .utf8)
        try run("sl", "add", file)
        try run("sl", "commit", "-m", message ?? "Add \(file)", "--user", "test <test@test.com>")
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
                domain: "SlTestRepo", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output])
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
