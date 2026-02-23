import XCTest

@testable import NoCrumbs

/// Tests the sequence boundary logic used in SocketServer to assign sequenceIDs.
/// The logic is extracted here for testability without needing a live socket.
@MainActor
final class SequenceBoundaryTests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var db: Database!
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var tempPath: String!

    private let testSessionID = "seq-test-session"
    private let testProject = "/tmp/seq-test"

    override func setUp() {
        super.setUp()
        tempPath = NSTemporaryDirectory() + "nocrumbs_seq_test_\(UUID().uuidString).sqlite"
        db = Database(path: tempPath)
        try? db.open()
        try? db.upsertSession(
            Session(id: testSessionID, projectPath: testProject, startedAt: Date(), lastActivityAt: Date())
        )
    }

    override func tearDown() {
        db.close()
        try? FileManager.default.removeItem(atPath: tempPath)
        super.tearDown()
    }

    // MARK: - Sequence Boundary Logic (mirrors SocketServer)

    /// Computes the sequenceID for a new prompt, using the same logic as SocketServer.
    private func computeSequenceID(sessionID: String) -> String {
        let sessionEvents = db.recentEvents.filter { $0.sessionID == sessionID }
        guard let lastEvent = sessionEvents.first else {
            return UUID().uuidString  // First prompt → new sequence
        }
        let lastHadChanges = !(db.fileChangesCache[lastEvent.id] ?? []).isEmpty
        if lastHadChanges {
            return UUID().uuidString  // Last prompt had changes → new sequence
        }
        return lastEvent.sequenceID ?? UUID().uuidString  // Continue current sequence
    }

    private func insertPrompt(text: String, sequenceID: String) throws -> PromptEvent {
        let event = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: text, timestamp: Date().addingTimeInterval(Double(db.recentEvents.count)),
            vcs: .git, baseCommitHash: nil, sequenceID: sequenceID
        )
        try db.insertPromptEvent(event)
        return event
    }

    private func insertFileChange(forEventID eventID: UUID) throws {
        try db.insertFileChange(FileChange(
            id: UUID(), eventID: eventID,
            filePath: testProject + "/file\(UUID().uuidString.prefix(4)).swift",
            toolName: "Write", timestamp: Date()
        ))
    }

    // MARK: - Tests

    func testFirstPromptGetsNewSequence() throws {
        let seqID = computeSequenceID(sessionID: testSessionID)
        XCTAssertFalse(seqID.isEmpty)

        // It should be a valid UUID string
        XCTAssertNotNil(UUID(uuidString: seqID))
    }

    func testPromptAfterNoChanges_ContinuesSequence() throws {
        let seqA = computeSequenceID(sessionID: testSessionID)
        _ = try insertPrompt(text: "Discuss something", sequenceID: seqA)

        // No file changes attached to first prompt
        let seqB = computeSequenceID(sessionID: testSessionID)
        XCTAssertEqual(seqA, seqB, "Should continue the same sequence when last prompt had no changes")
    }

    func testPromptAfterChanges_StartsNewSequence() throws {
        let seqA = computeSequenceID(sessionID: testSessionID)
        let event = try insertPrompt(text: "Do something", sequenceID: seqA)

        // Attach file changes
        try insertFileChange(forEventID: event.id)

        let seqB = computeSequenceID(sessionID: testSessionID)
        XCTAssertNotEqual(seqA, seqB, "Should start a new sequence when last prompt had changes")
    }

    func testMultipleSequencesInOneSession() throws {
        // Sequence A: discuss → discuss → do (with changes)
        let seqA = computeSequenceID(sessionID: testSessionID)
        _ = try insertPrompt(text: "Discuss approach", sequenceID: seqA)

        let seqA2 = computeSequenceID(sessionID: testSessionID)
        XCTAssertEqual(seqA, seqA2)
        _ = try insertPrompt(text: "Clarify requirements", sequenceID: seqA2)

        let seqA3 = computeSequenceID(sessionID: testSessionID)
        XCTAssertEqual(seqA, seqA3)
        let doEvent = try insertPrompt(text: "Do it", sequenceID: seqA3)
        try insertFileChange(forEventID: doEvent.id)

        // Sequence B: new prompt after changes
        let seqB = computeSequenceID(sessionID: testSessionID)
        XCTAssertNotEqual(seqA, seqB)
        _ = try insertPrompt(text: "Fix the bug", sequenceID: seqB)

        // Verify counts
        XCTAssertEqual(db.eventsForSequence(id: seqA).count, 3)
        XCTAssertEqual(db.eventsForSequence(id: seqB).count, 1)
    }

    func testLegacyNullSequenceID_TreatedAsSolo() throws {
        // Simulate legacy event with nil sequenceID
        let legacy = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Legacy prompt", timestamp: Date(),
            vcs: .git, baseCommitHash: nil, sequenceID: nil
        )
        try db.insertPromptEvent(legacy)

        // Next prompt should get a new sequence (nil → can't continue)
        let seqID = computeSequenceID(sessionID: testSessionID)
        XCTAssertNotNil(UUID(uuidString: seqID))
    }
}
