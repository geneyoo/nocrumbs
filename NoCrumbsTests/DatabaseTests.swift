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
            baseCommitHash: "abc123",
            sequenceID: nil
        )
        try db.insertPromptEvent(event)
        return event
    }

    // MARK: - Tests

    func testOrphanBackfill() throws {
        try insertSession()
        let orphan = try insertOrphan()

        // Attach file changes to the orphan (path must be inside testProject)
        let change = FileChange(
            id: UUID(), eventID: orphan.id,
            filePath: testProject + "/test.swift", toolName: "Write", timestamp: Date()
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
        XCTAssertEqual(changes.first?.filePath, testProject + "/test.swift")
    }

    func testNoOrphanCreatesNewEvent() throws {
        try insertSession()

        // Insert a normal event with prompt text
        let first = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "First prompt", timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123", sequenceID: nil
        )
        try db.insertPromptEvent(first)

        // Insert a second event
        let second = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Second prompt", timestamp: Date().addingTimeInterval(1),
            vcs: .git, baseCommitHash: "def456", sequenceID: nil
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

        // Attach 3 file changes (paths must be inside testProject)
        let paths = [testProject + "/a.swift", testProject + "/b.swift", testProject + "/c.swift"]
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
            vcs: .git, baseCommitHash: "aaa", sequenceID: nil
        )
        try db.insertPromptEvent(orphan)

        // Session 2: normal event
        let normal = PromptEvent(
            id: UUID(), sessionID: session2ID, projectPath: testProject,
            promptText: "Already has text", timestamp: Date(),
            vcs: .git, baseCommitHash: "bbb", sequenceID: nil
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

    // MARK: - Out-of-Repo Filtering

    func testOutOfRepoFileChangesExcludedFromCache() throws {
        try insertSession()
        let event = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Test prompt", timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123", sequenceID: nil
        )
        try db.insertPromptEvent(event)

        // Insert an in-repo file change
        let inRepo = FileChange(
            id: UUID(), eventID: event.id,
            filePath: testProject + "/Sources/app.swift", toolName: "Write", timestamp: Date()
        )
        try db.insertFileChange(inRepo)

        // Insert an out-of-repo file change (e.g. ~/.claude/plans/...)
        let outOfRepo = FileChange(
            id: UUID(), eventID: event.id,
            filePath: "/Users/someone/.claude/plans/plan.md", toolName: "Write", timestamp: Date()
        )
        try db.insertFileChange(outOfRepo)

        // Both exist in the raw DB
        let rawChanges = try db.fileChanges(forEventID: event.id)
        XCTAssertEqual(rawChanges.count, 2)

        // But the cache only has the in-repo file (cache filters on load)
        // Re-open to trigger fresh cache load
        db.close()
        db = Database(path: tempPath)
        try db.open()

        let cached = db.fileChangesCache[event.id] ?? []
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached.first?.filePath, testProject + "/Sources/app.swift")
    }

    // MARK: - Delete Methods

    func testDeletePromptEvent() throws {
        try insertSession()
        let event = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Delete me", timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123", sequenceID: nil
        )
        try db.insertPromptEvent(event)
        try db.insertFileChange(
            FileChange(
                id: UUID(), eventID: event.id,
                filePath: testProject + "/file.swift", toolName: "Write", timestamp: Date()
            ))

        XCTAssertEqual(db.recentEvents.filter { $0.id == event.id }.count, 1)
        XCTAssertEqual(db.fileChangesCache[event.id]?.count, 1)

        try db.deletePromptEvent(id: event.id)

        XCTAssertEqual(db.recentEvents.filter { $0.id == event.id }.count, 0)
        XCTAssertNil(db.fileChangesCache[event.id])
        // Cascade: file changes also deleted in DB
        let rawChanges = try db.fileChanges(forEventID: event.id)
        XCTAssertEqual(rawChanges.count, 0)
    }

    func testDeleteAllData() throws {
        try insertSession()
        let event = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Wipe me", timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123", sequenceID: nil
        )
        try db.insertPromptEvent(event)

        XCTAssertFalse(db.sessions.isEmpty)
        XCTAssertFalse(db.recentEvents.isEmpty)

        try db.deleteAllData()

        XCTAssertTrue(db.sessions.isEmpty)
        XCTAssertTrue(db.recentEvents.isEmpty)
        XCTAssertTrue(db.fileChangesCache.isEmpty)
    }

    func testEvictOlderThan() throws {
        // Old session (10 days ago)
        let oldDate = Date().addingTimeInterval(-10 * 86400)
        try db.upsertSession(
            Session(id: "old-session", projectPath: testProject, startedAt: oldDate, lastActivityAt: oldDate)
        )
        let oldEvent = PromptEvent(
            id: UUID(), sessionID: "old-session", projectPath: testProject,
            promptText: "Old prompt", timestamp: oldDate,
            vcs: .git, baseCommitHash: "old", sequenceID: nil
        )
        try db.insertPromptEvent(oldEvent)

        // Recent session (now)
        try insertSession()
        let newEvent = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "New prompt", timestamp: Date(),
            vcs: .git, baseCommitHash: "new", sequenceID: nil
        )
        try db.insertPromptEvent(newEvent)

        XCTAssertEqual(db.sessions.count, 2)

        try db.evictOlderThan(days: 7)

        XCTAssertEqual(db.sessions.count, 1)
        XCTAssertEqual(db.sessions.first?.id, testSessionID)
        XCTAssertEqual(db.recentEvents.count, 1)
    }

    // MARK: - SequenceID

    func testSequenceIDRoundTrip() throws {
        try insertSession()
        let seqID = UUID().uuidString
        let event = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Test prompt", timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123", sequenceID: seqID
        )
        try db.insertPromptEvent(event)

        // Verify in memory cache
        let cached = db.recentEvents.first(where: { $0.id == event.id })
        XCTAssertEqual(cached?.sequenceID, seqID)

        // Verify survives reload (close + reopen)
        db.close()
        db = Database(path: tempPath)
        try db.open()

        let reloaded = db.recentEvents.first(where: { $0.id == event.id })
        XCTAssertEqual(reloaded?.sequenceID, seqID)
    }

    func testSequenceIDNilBackwardCompat() throws {
        try insertSession()
        let event = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: "Legacy prompt", timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123", sequenceID: nil
        )
        try db.insertPromptEvent(event)

        let cached = db.recentEvents.first(where: { $0.id == event.id })
        XCTAssertNil(cached?.sequenceID)
    }

    func testEventsForSequence() throws {
        try insertSession()
        let seqA = UUID().uuidString
        let seqB = UUID().uuidString

        for i in 0..<3 {
            try db.insertPromptEvent(PromptEvent(
                id: UUID(), sessionID: testSessionID, projectPath: testProject,
                promptText: "Prompt \(i)", timestamp: Date().addingTimeInterval(Double(i)),
                vcs: .git, baseCommitHash: nil, sequenceID: i < 2 ? seqA : seqB
            ))
        }

        XCTAssertEqual(db.eventsForSequence(id: seqA).count, 2)
        XCTAssertEqual(db.eventsForSequence(id: seqB).count, 1)
    }

    func testBackfillPreservesSequenceID() throws {
        try insertSession()
        let seqID = UUID().uuidString
        let event = PromptEvent(
            id: UUID(), sessionID: testSessionID, projectPath: testProject,
            promptText: nil, timestamp: Date(),
            vcs: .git, baseCommitHash: "abc123", sequenceID: seqID
        )
        try db.insertPromptEvent(event)
        try db.updatePromptText("Backfilled", forEventID: event.id)

        let updated = db.recentEvents.first(where: { $0.id == event.id })
        XCTAssertEqual(updated?.promptText, "Backfilled")
        XCTAssertEqual(updated?.sequenceID, seqID)
    }
}
