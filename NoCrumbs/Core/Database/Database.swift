import Foundation
import OSLog
import SQLite3

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "DB")

@Observable
@MainActor
final class Database {
    static let shared = Database()

    private(set) var sessions: [Session] = []
    private(set) var recentEvents: [PromptEvent] = []
    private(set) var fileChangesCache: [UUID: [FileChange]] = [:]

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoCrumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("nocrumbs.sqlite").path
    }

    func open() throws {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            logger.error("📦 [DB] Failed to open: \(msg)")
            throw DatabaseError.openFailed(msg)
        }
        logger.info("📦 [DB] Opened at \(self.dbPath)")

        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA foreign_keys=ON")
        try migrate()
        try loadCache()
    }

    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
            logger.info("📦 [DB] Closed")
        }
    }

    // MARK: - Migrations

    private func migrate() throws {
        let version = userVersion()

        if version < 1 {
            exec("""
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    projectPath TEXT NOT NULL,
                    startedAt REAL NOT NULL,
                    lastActivityAt REAL NOT NULL
                )
                """)

            exec("""
                CREATE TABLE IF NOT EXISTS promptEvents (
                    id TEXT PRIMARY KEY,
                    sessionID TEXT NOT NULL,
                    projectPath TEXT NOT NULL,
                    promptText TEXT,
                    timestamp REAL NOT NULL,
                    vcs TEXT,
                    FOREIGN KEY(sessionID) REFERENCES sessions(id) ON DELETE CASCADE
                )
                """)

            exec("""
                CREATE TABLE IF NOT EXISTS fileChanges (
                    id TEXT PRIMARY KEY,
                    eventID TEXT NOT NULL,
                    filePath TEXT NOT NULL,
                    toolName TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    FOREIGN KEY(eventID) REFERENCES promptEvents(id) ON DELETE CASCADE
                )
                """)

            exec("CREATE INDEX IF NOT EXISTS idx_promptEvents_sessionID ON promptEvents(sessionID)")
            exec("CREATE INDEX IF NOT EXISTS idx_promptEvents_timestamp ON promptEvents(timestamp)")
            exec("CREATE INDEX IF NOT EXISTS idx_fileChanges_eventID ON fileChanges(eventID)")
            exec("CREATE INDEX IF NOT EXISTS idx_fileChanges_filePath ON fileChanges(filePath)")

            setUserVersion(1)
            logger.info("🔄 [DB] Migrated to v1")
        }

        if version < 2 {
            exec("ALTER TABLE promptEvents ADD COLUMN baseCommitHash TEXT")
            setUserVersion(2)
            logger.info("🔄 [DB] Migrated to v2 (baseCommitHash)")
        }
    }

    // MARK: - CRUD: Sessions

    func upsertSession(_ session: Session) throws {
        let sql = """
            INSERT INTO sessions (id, projectPath, startedAt, lastActivityAt)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET lastActivityAt = excluded.lastActivityAt
            """
        try execute(sql, bindings: [
            .text(session.id),
            .text(session.projectPath),
            .double(session.startedAt.timeIntervalSince1970),
            .double(session.lastActivityAt.timeIntervalSince1970),
        ])
        try loadSessions()
        logger.info("✅ [DB] Upserted session \(session.id)")
    }

    // MARK: - CRUD: PromptEvents

    func insertPromptEvent(_ event: PromptEvent) throws {
        let sql = """
            INSERT OR REPLACE INTO promptEvents (id, sessionID, projectPath, promptText, timestamp, vcs, baseCommitHash)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        try execute(sql, bindings: [
            .text(event.id.uuidString),
            .text(event.sessionID),
            .text(event.projectPath),
            event.promptText.map { .text($0) } ?? .null,
            .double(event.timestamp.timeIntervalSince1970),
            event.vcs.map { .text($0.rawValue) } ?? .null,
            event.baseCommitHash.map { .text($0) } ?? .null,
        ])
        try loadRecentEvents()
        logger.info("✅ [DB] Inserted event \(event.id.uuidString)")
    }

    // MARK: - CRUD: FileChanges

    func insertFileChange(_ change: FileChange) throws {
        let sql = """
            INSERT OR REPLACE INTO fileChanges (id, eventID, filePath, toolName, timestamp)
            VALUES (?, ?, ?, ?, ?)
            """
        try execute(sql, bindings: [
            .text(change.id.uuidString),
            .text(change.eventID.uuidString),
            .text(change.filePath),
            .text(change.toolName),
            .double(change.timestamp.timeIntervalSince1970),
        ])
        fileChangesCache[change.eventID, default: []].append(change)
        logger.info("✅ [DB] Inserted file change \(change.filePath)")
    }

    func insertFileChanges(_ changes: [FileChange]) throws {
        exec("BEGIN TRANSACTION")
        for change in changes {
            try insertFileChange(change)
        }
        exec("COMMIT")
    }

    func fileChanges(forEventID eventID: UUID) throws -> [FileChange] {
        let sql = "SELECT id, eventID, filePath, toolName, timestamp FROM fileChanges WHERE eventID = ? ORDER BY timestamp"
        return try query(sql, bindings: [.text(eventID.uuidString)]) { stmt in
            FileChange(
                id: UUID(uuidString: columnText(stmt, 0))!,
                eventID: UUID(uuidString: columnText(stmt, 1))!,
                filePath: columnText(stmt, 2),
                toolName: columnText(stmt, 3),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            )
        }
    }

    func eventsForSession(id: String) -> [PromptEvent] {
        recentEvents.filter { $0.sessionID == id }
    }

    func recentEvents(forProject projectPath: String, since: Date) throws -> [PromptEvent] {
        let sql = """
            SELECT id, sessionID, projectPath, promptText, timestamp, vcs, baseCommitHash
            FROM promptEvents
            WHERE projectPath = ? AND timestamp >= ? AND promptText IS NOT NULL
            ORDER BY timestamp DESC
            """
        return try query(sql, bindings: [
            .text(projectPath),
            .double(since.timeIntervalSince1970),
        ]) { stmt in
            let vcsRaw = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            return PromptEvent(
                id: UUID(uuidString: columnText(stmt, 0))!,
                sessionID: columnText(stmt, 1),
                projectPath: columnText(stmt, 2),
                promptText: sqlite3_column_text(stmt, 3).map { String(cString: $0) },
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                vcs: vcsRaw.flatMap { VCSType(rawValue: $0) },
                baseCommitHash: sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            )
        }
    }

    func fileChangeCount(forEventID eventID: UUID) throws -> Int {
        let sql = "SELECT COUNT(*) FROM fileChanges WHERE eventID = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, eventID.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    func totalFileCount(forProject projectPath: String, since: Date) throws -> Int {
        let sql = """
            SELECT COUNT(*) FROM fileChanges fc
            JOIN promptEvents pe ON fc.eventID = pe.id
            WHERE pe.projectPath = ? AND pe.timestamp >= ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, projectPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(stmt, 2, since.timeIntervalSince1970)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    func updateBaseCommitHash(_ hash: String, forEventID eventID: UUID) throws {
        try execute(
            "UPDATE promptEvents SET baseCommitHash = ? WHERE id = ?",
            bindings: [.text(hash), .text(eventID.uuidString)]
        )
    }

    /// Backfill baseCommitHash for legacy events that have NULL.
    /// Uses `git log --before=<timestamp>` to find what HEAD was at prompt time.
    func backfillBaseCommitHashes() async {
        let events: [PromptEvent] = await MainActor.run {
            recentEvents.filter { $0.baseCommitHash == nil && $0.vcs == .git }
        }
        guard !events.isEmpty else { return }
        logger.info("🔄 [DB] Backfilling baseCommitHash for \(events.count) events")

        let provider = GitProvider()
        // Cache per project to avoid redundant git calls for same timestamp range
        var cache: [String: String] = [:]  // "projectPath|timestamp" → hash

        for event in events {
            let cacheKey = "\(event.projectPath)|\(Int(event.timestamp.timeIntervalSince1970))"
            let hash: String?
            if let cached = cache[cacheKey] {
                hash = cached
            } else {
                hash = try? await provider.headBefore(event.timestamp, at: event.projectPath)
                if let hash { cache[cacheKey] = hash }
            }

            guard let hash else { continue }
            await MainActor.run {
                do {
                    try updateBaseCommitHash(hash, forEventID: event.id)
                } catch {
                    logger.warning("🔄 [DB] Backfill failed for \(event.id): \(error.localizedDescription)")
                }
            }
        }

        // Reload cache to pick up backfilled values
        await MainActor.run {
            try? loadRecentEvents()
            logger.info("🔄 [DB] Backfill complete")
        }
    }

    func deleteSession(id: String) throws {
        try execute("DELETE FROM sessions WHERE id = ?", bindings: [.text(id)])
        try loadSessions()
        try loadRecentEvents()
        logger.info("✅ [DB] Deleted session \(id) (cascade)")
    }

    // MARK: - Cache Loading

    private func loadCache() throws {
        try loadSessions()
        try loadRecentEvents()
        try loadFileChanges()
    }

    private func loadSessions() throws {
        sessions = try query(
            "SELECT id, projectPath, startedAt, lastActivityAt FROM sessions ORDER BY lastActivityAt DESC"
        ) { stmt in
            Session(
                id: columnText(stmt, 0),
                projectPath: columnText(stmt, 1),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                lastActivityAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            )
        }
    }

    private func loadRecentEvents() throws {
        recentEvents = try query(
            "SELECT id, sessionID, projectPath, promptText, timestamp, vcs, baseCommitHash FROM promptEvents ORDER BY timestamp DESC LIMIT 500"
        ) { stmt in
            let vcsRaw = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            return PromptEvent(
                id: UUID(uuidString: columnText(stmt, 0))!,
                sessionID: columnText(stmt, 1),
                projectPath: columnText(stmt, 2),
                promptText: sqlite3_column_text(stmt, 3).map { String(cString: $0) },
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                vcs: vcsRaw.flatMap { VCSType(rawValue: $0) },
                baseCommitHash: sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            )
        }
    }

    private func loadFileChanges() throws {
        let eventIDs = recentEvents.map { $0.id }
        var cache: [UUID: [FileChange]] = [:]
        for eventID in eventIDs {
            let changes = try fileChanges(forEventID: eventID)
            if !changes.isEmpty {
                cache[eventID] = changes
            }
        }
        fileChangesCache = cache
    }

    // MARK: - SQLite Helpers

    private enum Binding {
        case text(String)
        case double(Double)
        case null
    }

    private func execute(_ sql: String, bindings: [Binding] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            logger.error("❌ [DB] Prepare failed: \(msg)")
            throw DatabaseError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .double(let d): sqlite3_bind_double(stmt, idx, d)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            logger.error("❌ [DB] Step failed: \(msg)")
            throw DatabaseError.queryFailed(msg)
        }
    }

    private func query<T>(_ sql: String, bindings: [Binding] = [], map: (OpaquePointer) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.queryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .double(let d): sqlite3_bind_double(stmt, idx, d)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(map(stmt!))
        }
        return results
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        String(cString: sqlite3_column_text(stmt, idx))
    }

    private func userVersion() -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil)
        sqlite3_step(stmt)
        return sqlite3_column_int(stmt, 0)
    }

    private func setUserVersion(_ v: Int32) {
        exec("PRAGMA user_version = \(v)")
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): "Database open failed: \(msg)"
        case .queryFailed(let msg): "Database query failed: \(msg)"
        }
    }
}
