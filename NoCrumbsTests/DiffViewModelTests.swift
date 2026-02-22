import XCTest

@testable import NoCrumbs

@MainActor
final class DiffViewModelTests: XCTestCase {

    private func makeEvent(
        vcs: VCSType? = .git,
        baseCommitHash: String? = "abc1234567890abcdef1234567890abcdef123456",
        projectPath: String = "/tmp/test"
    ) -> PromptEvent {
        PromptEvent(
            id: UUID(),
            sessionID: "test-session",
            projectPath: projectPath,
            promptText: "test prompt",
            timestamp: Date(),
            vcs: vcs,
            baseCommitHash: baseCommitHash
        )
    }

    private func makeFileChange(eventID: UUID, path: String) -> FileChange {
        FileChange(
            id: UUID(),
            eventID: eventID,
            filePath: path,
            toolName: "Write",
            timestamp: Date()
        )
    }

    // MARK: - Tests

    func testLoad_noVCS() async throws {
        let mock = MockVCSProvider()
        let vm = DiffViewModel(provider: mock)
        let event = makeEvent(vcs: nil)
        let change = makeFileChange(eventID: event.id, path: "/tmp/test/file.swift")

        vm.load(event: event, fileChanges: [change])

        // Give the synchronous guard a chance to execute
        try await Task.yield()

        XCTAssertNotNil(vm.error)
        XCTAssertTrue(vm.error?.contains("No VCS") == true)
    }

    func testLoad_noFileChanges() async throws {
        let mock = MockVCSProvider()
        let vm = DiffViewModel(provider: mock)
        let event = makeEvent()

        vm.load(event: event, fileChanges: [])

        try await Task.yield()

        XCTAssertTrue(vm.fileDiffs.isEmpty)
        XCTAssertNil(vm.error)
    }

    func testLoad_nilBaseHash() async throws {
        let mock = MockVCSProvider()
        let vm = DiffViewModel(provider: mock)
        let event = makeEvent(baseCommitHash: nil)
        let change = makeFileChange(eventID: event.id, path: "/tmp/test/file.swift")

        vm.load(event: event, fileChanges: [change])

        // Wait for the Task inside load() to run
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(vm.error)
        XCTAssertTrue(vm.error?.contains("baseline") == true || vm.error?.contains("Waiting") == true)
    }

    func testLoad_invalidCommit() async throws {
        var mock = MockVCSProvider()
        mock.isValid = false
        let vm = DiffViewModel(provider: mock)
        let event = makeEvent()
        let change = makeFileChange(eventID: event.id, path: "/tmp/test/file.swift")

        vm.load(event: event, fileChanges: [change])

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(vm.error)
        XCTAssertTrue(vm.error?.contains("no longer exists") == true)
    }

    func testLoad_validDiff() async throws {
        var mock = MockVCSProvider()
        mock.diffOutput = """
            diff --git a/file.swift b/file.swift
            --- a/file.swift
            +++ b/file.swift
            @@ -1,1 +1,1 @@
            -old
            +new
            """
        let vm = DiffViewModel(provider: mock)
        let event = makeEvent()
        let change = makeFileChange(eventID: event.id, path: "/tmp/test/file.swift")

        vm.load(event: event, fileChanges: [change])

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.fileDiffs.count, 1)
        XCTAssertEqual(vm.fileDiffs[0].status, .modified)
    }

    func testLoad_gitFailure() async throws {
        var mock = MockVCSProvider()
        mock.shouldThrow = VCSError.commandFailed("git", 1, "fatal: bad object")
        let vm = DiffViewModel(provider: mock)
        let event = makeEvent()
        let change = makeFileChange(eventID: event.id, path: "/tmp/test/file.swift")

        vm.load(event: event, fileChanges: [change])

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(vm.error)
    }

    func testLoad_untrackedFiles() async throws {
        var mock = MockVCSProvider()
        mock.diffOutput = ""  // No diff output for the file
        mock.untrackedResult = Set(["newfile.swift"])
        let vm = DiffViewModel(provider: mock)
        let event = makeEvent()
        let change = makeFileChange(eventID: event.id, path: "/tmp/test/newfile.swift")

        // Create the actual file so syntheticDiff can read it
        let dir = "/tmp/test"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "hello world".write(toFile: "\(dir)/newfile.swift", atomically: true, encoding: .utf8)

        vm.load(event: event, fileChanges: [change])

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.fileDiffs.count, 1)
        XCTAssertEqual(vm.fileDiffs[0].status, .added)

        // Cleanup
        try? FileManager.default.removeItem(atPath: "\(dir)/newfile.swift")
    }
}

// MARK: - MockVCSProvider

struct MockVCSProvider: VCSProvider, @unchecked Sendable {
    var type: VCSType = .git
    var headHash: String = "abc1234567890abcdef1234567890abcdef123456"
    var branchName: String = "main"
    var isValid: Bool = true
    var diffOutput: String = ""
    var untrackedResult: Set<String> = []
    var shouldThrow: Error?

    func currentHead(at path: String) async throws -> String {
        if let err = shouldThrow { throw err }
        return headHash
    }

    func currentBranch(at path: String) async throws -> String {
        if let err = shouldThrow { throw err }
        return branchName
    }

    func isValidCommit(_ hash: String, at path: String) async throws -> Bool {
        if let err = shouldThrow { throw err }
        return isValid
    }

    func diff(for hash: String, at path: String) async throws -> String {
        if let err = shouldThrow { throw err }
        return diffOutput
    }

    func uncommittedDiff(at path: String) async throws -> String {
        if let err = shouldThrow { throw err }
        return diffOutput
    }

    func diffForFiles(_ filePaths: [String], at path: String) async throws -> String {
        if let err = shouldThrow { throw err }
        return diffOutput
    }

    func diffFromBase(_ baseHash: String, filePaths: [String], at path: String) async throws -> String {
        if let err = shouldThrow { throw err }
        return diffOutput
    }

    func headBefore(_ date: Date, at path: String) async throws -> String? {
        if let err = shouldThrow { throw err }
        return headHash
    }

    func untrackedFiles(_ filePaths: [String], at path: String) async throws -> Set<String> {
        if let err = shouldThrow { throw err }
        return untrackedResult
    }
}
