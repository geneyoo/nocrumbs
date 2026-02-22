import XCTest

@testable import NoCrumbs

@MainActor
final class DatabaseTests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var db: Database!
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var tempPath: String!

    override func setUp() {
        super.setUp()
        tempPath = NSTemporaryDirectory() + "nocrumbs_test_\(UUID().uuidString).sqlite"
        db = Database(path: tempPath)
        try? db.open()  // Safe in tests — failure will surface as nil db
    }

    override func tearDown() {
        db.close()
        try? FileManager.default.removeItem(atPath: tempPath)
        super.tearDown()
    }

    // MARK: - Helpers

    private let testSessionID = "test-session-001"
    private let testProject = "/tmp/test-project"

    private func insertSession() throws {
        let session = Session(
            id: testSessionID,
            projectPath: testProject,
            startedAt: Date(),
            lastActivityAt: Date()
        )
        try db.upsertSession(session)
    }

    private func insertOrphan() throws -> PromptEvent {
        let event = PromptEvent(
            id: UUID(),
            sessionID: testSessionID,
            projectPath: testProject,
            promptText: nil,
            timestamp: Date(),
            vcs: .git,
            baseCommitHash: "abc123"
        )
        try db.insertPromptEvent(event)
        return event
    }

    // MARK: - Tests

    func testOrphanBackfill() throws {
        try insertSession()
        let orphan = try insertOrphan()

        // Attach file changes to the orphan
        let change = FileChange(
            id: UUID(), eventID: orphan.id,
            filePath: "/tmp/test.swift", toolName: "Write", timestamp: Date()
        )
        try db.insertFileChange(change)

        // Backfill prompt text
        try db.updatePromptText("Fix the login bug", forEventID: orphan.id)

        // Verify backfill worked
        let updated = db.recentEvents.first(where: { $0.id == orphan.id })
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.promptText, "Fix the login bug")

        // Verify no duplicate event was created
        let sessionEvents = db.recentEvents.filter { $0.sessionID == testSessionID }
        XCTAssertEqual(sessionEvents.count, 1)

        // Verify file changes still attached
        let changes = try db.fileChanges(forEventID: orphan.id)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.filePath, "/tmp/test.swift")
    }

    func testNoOrphanCreatesNewEvent() throws {
        try insertSession()

        // Insert a normal event with prompt text
        let first = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "First prompt", timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123"
        )
        try db.insertPromptEvent(first)

        // Insert a second event
        let second = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Second prompt", timestamp: Date().addingTimeInterval(1),
            vcs: .git, baseCommitHash: "def456"
        )
        try db.insertPromptEvent(second)

        // Verify both exist
        let sessionEvents = db.recentEvents.filter { $0.sessionID == testSessionID }
        XCTAssertEqual(sessionEvents.count, 2)
    }

    func testOrphanDetection() throws {
        try insertSession()
        let orphan = try insertOrphan()

        // Find orphan via the same pattern SocketServer uses
        let found = db.recentEvents.first(where: {
            $0.sessionID == testSessionID && $0.promptText == nil
        })
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, orphan.id)
    }

    func testOrphanWithFileChanges() throws {
        try insertSession()
        let orphan = try insertOrphan()

        // Attach 3 file changes
        let paths = ["/tmp/a.swift", "/tmp/b.swift", "/tmp/c.swift"]
        for path in paths {
            try db.insertFileChange(
                FileChange(
                    id: UUID(), eventID: orphan.id,
                    filePath: path, toolName: "Write", timestamp: Date()
                ))
        }

        // Backfill
        try db.updatePromptText("Refactor networking layer", forEventID: orphan.id)

        // All 3 changes still reference the same event
        let changes = try db.fileChanges(forEventID: orphan.id)
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(Set(changes.map(\.filePath)), Set(paths))
    }

    func testMultipleSessionsIsolation() throws {
        let session2ID = "test-session-002"

        // Set up two sessions
        try db.upsertSession(
            Session(
                id: testSessionID, projectPath: testProject,
                startedAt: Date(), lastActivityAt: Date()
            ))
        try db.upsertSession(
            Session(
                id: session2ID, projectPath: testProject,
                startedAt: Date(), lastActivityAt: Date()
            ))

        // Session 1: orphan
        let orphan = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: nil, timestamp: Date(),
            vcs: .git, baseCommitHash: "aaa"
        )
        try db.insertPromptEvent(orphan)

        // Session 2: normal event
        let normal = PromptEvent(
            id: UUID(), sessionID: session2ID, projectPath: testProject,
            promptText: "Already has text", timestamp: Date(),
            vcs: .git, baseCommitHash: "bbb"
        )
        try db.insertPromptEvent(normal)

        // Backfill session 1 orphan
        try db.updatePromptText("Backfilled text", forEventID: orphan.id)

        // Session 1 orphan is backfilled
        let s1Event = db.recentEvents.first(where: { $0.id == orphan.id })
        XCTAssertEqual(s1Event?.promptText, "Backfilled text")

        // Session 2 event is unchanged
        let s2Event = db.recentEvents.first(where: { $0.id == normal.id })
        XCTAssertEqual(s2Event?.promptText, "Already has text")

        // No orphans in session 2
        let s2Orphan = db.recentEvents.first(where: {
            $0.sessionID == session2ID && $0.promptText == nil
        })
        XCTAssertNil(s2Orphan)
    }
}
