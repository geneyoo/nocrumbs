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
            INSERT OR REPLACE INTO promptEvents (id, sessionID, projectPath, promptText, timestamp, vcs)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        try execute(sql, bindings: [
            .text(event.id.uuidString),
            .text(event.sessionID),
            .text(event.projectPath),
            event.promptText.map { .text($0) } ?? .null,
            .double(event.timestamp.timeIntervalSince1970),
            event.vcs.map { .text($0.rawValue) } ?? .null,
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
            "SELECT id, sessionID, projectPath, promptText, timestamp, vcs FROM promptEvents ORDER BY timestamp DESC LIMIT 500"
        ) { stmt in
            let vcsRaw = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            return PromptEvent(
                id: UUID(uuidString: columnText(stmt, 0))!,
                sessionID: columnText(stmt, 1),
                projectPath: columnText(stmt, 2),
                promptText: sqlite3_column_text(stmt, 3).map { String(cString: $0) },
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                vcs: vcsRaw.flatMap { VCSType(rawValue: $0) }
            )
        }
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
