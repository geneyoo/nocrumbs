import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "MockData")

@MainActor
enum MockDataGenerator {

    // MARK: - Public

    static func populate(_ database: Database) throws {
        logger.info("🎭 Generating mock data…")

        // --- Day offsets -------------------------------------------------------
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = today.addingTimeInterval(-86400)
        let threeDaysAgo = today.addingTimeInterval(-86400 * 3)

        // --- Repos -------------------------------------------------------------
        let vaporAPI = "~/code/vapor-api"
        let noCrumbs = "~/code/nocrumbs"
        let swiftCollections = "~/code/swift-collections"

        // ======================================================================
        // TODAY — vapor-api: Auth middleware (4-prompt sequence → code, then 1 solo typo fix)
        // ======================================================================
        let s1ID = "session-\(shortID())"
        let s1Start = date(base: today, hour: 10, minute: 0)
        try database.upsertSession(Session(
            id: s1ID, projectPath: vaporAPI,
            startedAt: s1Start, lastActivityAt: date(base: today, hour: 10, minute: 42)
        ))

        let seq1 = UUID().uuidString
        let e1a = makeEvent(session: s1ID, project: vaporAPI, seq: seq1,
                            prompt: "Add JWT auth middleware that validates tokens from the Authorization header",
                            at: date(base: today, hour: 10, minute: 0), vcs: .git)
        let e1b = makeEvent(session: s1ID, project: vaporAPI, seq: seq1,
                            prompt: "Extract the token validation into a separate TokenValidator protocol",
                            at: date(base: today, hour: 10, minute: 8), vcs: .git)
        let e1c = makeEvent(session: s1ID, project: vaporAPI, seq: seq1,
                            prompt: "Add unit tests for the middleware — test expired tokens, missing header, and valid tokens",
                            at: date(base: today, hour: 10, minute: 18), vcs: .git)
        let e1d = makeEvent(session: s1ID, project: vaporAPI, seq: seq1,
                            prompt: "Wire up the middleware in configure.swift for all /api/* routes",
                            at: date(base: today, hour: 10, minute: 28), vcs: .git)
        for e in [e1a, e1b, e1c, e1d] { try database.insertPromptEvent(e) }

        try addFiles(database, eventID: e1c.id, project: vaporAPI, files: [
            ("Sources/App/Middleware/AuthMiddleware.swift", "Write"),
            ("Sources/App/Middleware/TokenValidator.swift", "Write"),
            ("Tests/AppTests/AuthMiddlewareTests.swift", "Write"),
        ])
        try addFiles(database, eventID: e1d.id, project: vaporAPI, files: [
            ("Sources/App/configure.swift", "Edit"),
        ])

        // Solo typo fix (new sequence)
        let seq1b = UUID().uuidString
        let e1e = makeEvent(session: s1ID, project: vaporAPI, seq: seq1b,
                            prompt: "Fix typo in AuthMiddleware error message — 'autentication' → 'authentication'",
                            at: date(base: today, hour: 10, minute: 42), vcs: .git)
        try database.insertPromptEvent(e1e)
        try addFiles(database, eventID: e1e.id, project: vaporAPI, files: [
            ("Sources/App/Middleware/AuthMiddleware.swift", "Edit"),
        ])

        // Hook events for session state: .live (recent activity)
        try addHooks(database, sessionID: s1ID, project: vaporAPI, events: [
            ("TaskStart", date(base: today, hour: 10, minute: 0)),
            ("PostToolUse", date(base: today, hour: 10, minute: 42)),
        ])

        // ======================================================================
        // TODAY — nocrumbs: Theme picker (2-prompt sequence → code, then 1 discussion-only)
        // ======================================================================
        let s2ID = "session-\(shortID())"
        let s2Start = date(base: today, hour: 14, minute: 30)
        try database.upsertSession(Session(
            id: s2ID, projectPath: noCrumbs,
            startedAt: s2Start, lastActivityAt: date(base: today, hour: 15, minute: 5)
        ))

        let seq2 = UUID().uuidString
        let e2a = makeEvent(session: s2ID, project: noCrumbs, seq: seq2,
                            prompt: "Create a ThemePicker view that shows color swatches in a grid with the active theme highlighted",
                            at: date(base: today, hour: 14, minute: 30), vcs: .git)
        let e2b = makeEvent(session: s2ID, project: noCrumbs, seq: seq2,
                            prompt: "Add a live preview pane next to the grid that updates as you hover over themes",
                            at: date(base: today, hour: 14, minute: 45), vcs: .git)
        for e in [e2a, e2b] { try database.insertPromptEvent(e) }

        try addFiles(database, eventID: e2a.id, project: noCrumbs, files: [
            ("NoCrumbs/Features/Settings/ThemePickerView.swift", "Write"),
            ("NoCrumbs/UI/Components/ColorSwatchGrid.swift", "Write"),
        ])
        try addFiles(database, eventID: e2b.id, project: noCrumbs, files: [
            ("NoCrumbs/Features/Settings/ThemePickerView.swift", "Edit"),
            ("NoCrumbs/Features/Settings/ThemePreviewPane.swift", "Write"),
        ])

        // Discussion-only prompt (no file changes → new sequence)
        let seq2b = UUID().uuidString
        let e2c = makeEvent(session: s2ID, project: noCrumbs, seq: seq2b,
                            prompt: "What's the best approach for persisting custom user themes — JSON files or SQLite?",
                            at: date(base: today, hour: 15, minute: 5), vcs: .git)
        try database.insertPromptEvent(e2c)

        try addHooks(database, sessionID: s2ID, project: noCrumbs, events: [
            ("TaskStart", date(base: today, hour: 14, minute: 30)),
            ("PostToolUse", date(base: today, hour: 14, minute: 50)),
            ("SessionEnd", date(base: today, hour: 15, minute: 10)),
        ])

        // ======================================================================
        // YESTERDAY — vapor-api: DB migration (single prompt → 3-file change)
        // ======================================================================
        let s3ID = "session-\(shortID())"
        let s3Start = date(base: yesterday, hour: 9, minute: 15)
        try database.upsertSession(Session(
            id: s3ID, projectPath: vaporAPI,
            startedAt: s3Start, lastActivityAt: date(base: yesterday, hour: 9, minute: 22)
        ))

        let seq3 = UUID().uuidString
        let e3a = makeEvent(session: s3ID, project: vaporAPI, seq: seq3,
                            prompt: "Create a migration that adds a 'roles' JSONB column to the users table with a default of ['member']",
                            at: date(base: yesterday, hour: 9, minute: 15), vcs: .git)
        try database.insertPromptEvent(e3a)

        try addFiles(database, eventID: e3a.id, project: vaporAPI, files: [
            ("Sources/App/Migrations/AddUserRoles.swift", "Write"),
            ("Sources/App/Models/User.swift", "Edit"),
            ("Sources/App/configure.swift", "Edit"),
        ])

        try addHooks(database, sessionID: s3ID, project: vaporAPI, events: [
            ("TaskStart", date(base: yesterday, hour: 9, minute: 15)),
            ("PostToolUse", date(base: yesterday, hour: 9, minute: 22)),
            ("SessionEnd", date(base: yesterday, hour: 9, minute: 25)),
        ])

        // ======================================================================
        // YESTERDAY — swift-collections: BTree refactor (3-prompt sequence → code)
        // ======================================================================
        let s4ID = "session-\(shortID())"
        let s4Start = date(base: yesterday, hour: 16, minute: 0)
        try database.upsertSession(Session(
            id: s4ID, projectPath: swiftCollections,
            startedAt: s4Start, lastActivityAt: date(base: yesterday, hour: 16, minute: 40)
        ))

        let seq4 = UUID().uuidString
        let e4a = makeEvent(session: s4ID, project: swiftCollections, seq: seq4,
                            prompt: "Refactor BTreeNode to use a contiguous buffer instead of Array for keys",
                            at: date(base: yesterday, hour: 16, minute: 0), vcs: .git)
        let e4b = makeEvent(session: s4ID, project: swiftCollections, seq: seq4,
                            prompt: "Update the split/merge operations to work with the new buffer layout",
                            at: date(base: yesterday, hour: 16, minute: 15), vcs: .git)
        let e4c = makeEvent(session: s4ID, project: swiftCollections, seq: seq4,
                            prompt: "Run the benchmarks and compare performance — make sure insertion is still O(log n)",
                            at: date(base: yesterday, hour: 16, minute: 30), vcs: .git)
        for e in [e4a, e4b, e4c] { try database.insertPromptEvent(e) }

        try addFiles(database, eventID: e4b.id, project: swiftCollections, files: [
            ("Sources/Collections/BTree/BTreeNode.swift", "Edit"),
            ("Sources/Collections/BTree/BTreeNode+Split.swift", "Edit"),
            ("Sources/Collections/BTree/BTreeNode+Merge.swift", "Edit"),
        ])
        try addFiles(database, eventID: e4c.id, project: swiftCollections, files: [
            ("Benchmarks/BTreeBenchmarks.swift", "Edit"),
        ])

        try addHooks(database, sessionID: s4ID, project: swiftCollections, events: [
            ("TaskStart", date(base: yesterday, hour: 16, minute: 0)),
            ("PostToolUse", date(base: yesterday, hour: 16, minute: 35)),
            ("Stop", date(base: yesterday, hour: 16, minute: 40)),
        ])

        // ======================================================================
        // 3 DAYS AGO — vapor-api: Project setup (2 prompts, ended)
        // ======================================================================
        let s5ID = "session-\(shortID())"
        let s5Start = date(base: threeDaysAgo, hour: 11, minute: 0)
        try database.upsertSession(Session(
            id: s5ID, projectPath: vaporAPI,
            startedAt: s5Start, lastActivityAt: date(base: threeDaysAgo, hour: 11, minute: 20)
        ))

        let seq5 = UUID().uuidString
        let e5a = makeEvent(session: s5ID, project: vaporAPI, seq: seq5,
                            prompt: "Set up the Vapor project structure with Fluent PostgreSQL and leaf templating",
                            at: date(base: threeDaysAgo, hour: 11, minute: 0), vcs: .git)
        let e5b = makeEvent(session: s5ID, project: vaporAPI, seq: seq5,
                            prompt: "Add Docker compose for local PostgreSQL and create the initial User model",
                            at: date(base: threeDaysAgo, hour: 11, minute: 12), vcs: .git)
        for e in [e5a, e5b] { try database.insertPromptEvent(e) }

        try addFiles(database, eventID: e5a.id, project: vaporAPI, files: [
            ("Package.swift", "Write"),
            ("Sources/App/configure.swift", "Write"),
            ("Sources/App/routes.swift", "Write"),
        ])
        try addFiles(database, eventID: e5b.id, project: vaporAPI, files: [
            ("docker-compose.yml", "Write"),
            ("Sources/App/Models/User.swift", "Write"),
            ("Sources/App/Migrations/CreateUser.swift", "Write"),
        ])

        try addHooks(database, sessionID: s5ID, project: vaporAPI, events: [
            ("TaskStart", date(base: threeDaysAgo, hour: 11, minute: 0)),
            ("PostToolUse", date(base: threeDaysAgo, hour: 11, minute: 18)),
            ("SessionEnd", date(base: threeDaysAgo, hour: 11, minute: 20)),
        ])

        // ======================================================================
        // 3 DAYS AGO — vapor-api: CI pipeline (1 prompt, interrupted)
        // ======================================================================
        let s6ID = "session-\(shortID())"
        let s6Start = date(base: threeDaysAgo, hour: 15, minute: 0)
        try database.upsertSession(Session(
            id: s6ID, projectPath: vaporAPI,
            startedAt: s6Start, lastActivityAt: date(base: threeDaysAgo, hour: 15, minute: 5)
        ))

        let seq6 = UUID().uuidString
        let e6a = makeEvent(session: s6ID, project: vaporAPI, seq: seq6,
                            prompt: "Create a GitHub Actions workflow for CI — build, test, and deploy to staging on push to main",
                            at: date(base: threeDaysAgo, hour: 15, minute: 0), vcs: .git)
        try database.insertPromptEvent(e6a)

        try addFiles(database, eventID: e6a.id, project: vaporAPI, files: [
            (".github/workflows/ci.yml", "Write"),
        ])

        try addHooks(database, sessionID: s6ID, project: vaporAPI, events: [
            ("TaskStart", date(base: threeDaysAgo, hour: 15, minute: 0)),
            ("Stop", date(base: threeDaysAgo, hour: 15, minute: 5)),
        ])

        // ======================================================================
        // 3 DAYS AGO — nocrumbs: Socket refactor (2-prompt sequence → code)
        // ======================================================================
        let s7ID = "session-\(shortID())"
        let s7Start = date(base: threeDaysAgo, hour: 20, minute: 0)
        try database.upsertSession(Session(
            id: s7ID, projectPath: noCrumbs,
            startedAt: s7Start, lastActivityAt: date(base: threeDaysAgo, hour: 20, minute: 25)
        ))

        let seq7 = UUID().uuidString
        let e7a = makeEvent(session: s7ID, project: noCrumbs, seq: seq7,
                            prompt: "Refactor SocketServer to use NWListener instead of raw POSIX sockets",
                            at: date(base: threeDaysAgo, hour: 20, minute: 0), vcs: .git)
        let e7b = makeEvent(session: s7ID, project: noCrumbs, seq: seq7,
                            prompt: "Add connection pooling and graceful shutdown to the NWListener implementation",
                            at: date(base: threeDaysAgo, hour: 20, minute: 15), vcs: .git)
        for e in [e7a, e7b] { try database.insertPromptEvent(e) }

        try addFiles(database, eventID: e7a.id, project: noCrumbs, files: [
            ("NoCrumbs/Core/IPC/SocketServer.swift", "Edit"),
            ("NoCrumbs/Core/IPC/ConnectionPool.swift", "Write"),
        ])
        try addFiles(database, eventID: e7b.id, project: noCrumbs, files: [
            ("NoCrumbs/Core/IPC/SocketServer.swift", "Edit"),
            ("NoCrumbs/Core/IPC/ConnectionPool.swift", "Edit"),
        ])

        try addHooks(database, sessionID: s7ID, project: noCrumbs, events: [
            ("TaskStart", date(base: threeDaysAgo, hour: 20, minute: 0)),
            ("PostToolUse", date(base: threeDaysAgo, hour: 20, minute: 22)),
            ("SessionEnd", date(base: threeDaysAgo, hour: 20, minute: 25)),
        ])

        logger.info("🎭 Mock data populated: 7 sessions, \(database.recentEvents.count) events, \(database.fileChangesCache.values.flatMap { $0 }.count) file changes")
    }

    // MARK: - Helpers

    private static func makeEvent(
        session: String, project: String, seq: String,
        prompt: String, at timestamp: Date, vcs: VCSType?
    ) -> PromptEvent {
        PromptEvent(
            id: UUID(), sessionID: session, projectPath: project,
            promptText: prompt, timestamp: timestamp,
            vcs: vcs, baseCommitHash: randomHash(),
            sequenceID: seq
        )
    }

    private static func addFiles(
        _ db: Database, eventID: UUID, project: String,
        files: [(String, String)]
    ) throws {
        for (relativePath, tool) in files {
            let change = FileChange(
                id: UUID(), eventID: eventID,
                filePath: project + "/" + relativePath,
                toolName: tool,
                timestamp: Date()
            )
            try db.insertFileChange(change)
        }
    }

    private static func addHooks(
        _ db: Database, sessionID: String, project: String,
        events: [(String, Date)]
    ) throws {
        for (name, timestamp) in events {
            let hook = HookEvent(
                id: UUID(), sessionID: sessionID,
                hookEventName: name, projectPath: project,
                timestamp: timestamp, payload: nil
            )
            try db.insertHookEvent(hook)
        }
    }

    private static func date(base: Date, hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private static func shortID() -> String {
        UUID().uuidString.prefix(8).lowercased()
    }

    private static func randomHash() -> String {
        (0..<7).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
    }
}
