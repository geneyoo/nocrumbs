import Foundation
import OSLog
import SQLite3

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "DB")

@Observable
@MainActor
final class Database {  // swiftlint:disable:this type_body_length
    static let shared = Database()

    private(set) var sessions: [Session] = []
    private(set) var recentEvents: [PromptEvent] = []
    private(set) var fileChangesCache: [UUID: [FileChange]] = [:]
    private(set) var recentHookEvents: [HookEvent] = []
    private(set) var sessionStateCache: [String: SessionState] = [:]
    private(set) var commitTemplates: [CommitTemplate] = []
    /// In-memory cache for computed diff stats — survives view navigation, cleared on app restart.
    var diffStatCache: [UUID: PromptDiffStat] = [:]

    var activeTemplate: CommitTemplate? {
        commitTemplates.first(where: \.isActive)
    }

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoCrumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("nocrumbs.sqlite").path
    }

    /// Testable initializer — uses a custom DB path (e.g. temp file or ":memory:")
    init(path: String) {
        dbPath = path
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

    // swiftlint:disable:next function_body_length
    private func migrate() throws {
        let version = userVersion()

        if version < 1 {
            exec(
                """
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    projectPath TEXT NOT NULL,
                    startedAt REAL NOT NULL,
                    lastActivityAt REAL NOT NULL
                )
                """)

            exec(
                """
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

            exec(
                """
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

        if version < 3 {
            exec(
                """
                CREATE TABLE IF NOT EXISTS hookEvents (
                    id TEXT PRIMARY KEY,
                    sessionID TEXT NOT NULL,
                    hookEventName TEXT NOT NULL,
                    projectPath TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    payload TEXT,
                    FOREIGN KEY(sessionID) REFERENCES sessions(id) ON DELETE CASCADE
                )
                """)
            exec("CREATE INDEX IF NOT EXISTS idx_hookEvents_sessionID ON hookEvents(sessionID)")
            exec("CREATE INDEX IF NOT EXISTS idx_hookEvents_timestamp ON hookEvents(timestamp)")
            exec("CREATE INDEX IF NOT EXISTS idx_hookEvents_hookEventName ON hookEvents(hookEventName)")
            setUserVersion(3)
            logger.info("🔄 [DB] Migrated to v3 (hookEvents)")
        }

        if version < 4 {
            // Deduplicate fileChanges: keep one record per (eventID, filePath)
            exec(
                """
                DELETE FROM fileChanges WHERE id NOT IN (
                    SELECT id FROM (
                        SELECT id, ROW_NUMBER() OVER (PARTITION BY eventID, filePath ORDER BY timestamp DESC) AS rn
                        FROM fileChanges
                    ) WHERE rn = 1
                )
                """)
            // Recreate table with UNIQUE constraint on (eventID, filePath)
            exec(
                """
                CREATE TABLE fileChanges_new (
                    id TEXT PRIMARY KEY,
                    eventID TEXT NOT NULL,
                    filePath TEXT NOT NULL,
                    toolName TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    FOREIGN KEY(eventID) REFERENCES promptEvents(id) ON DELETE CASCADE,
                    UNIQUE(eventID, filePath)
                )
                """)
            exec("INSERT OR IGNORE INTO fileChanges_new SELECT * FROM fileChanges")
            exec("DROP TABLE fileChanges")
            exec("ALTER TABLE fileChanges_new RENAME TO fileChanges")
            exec("CREATE INDEX IF NOT EXISTS idx_fileChanges_eventID ON fileChanges(eventID)")
            exec("CREATE INDEX IF NOT EXISTS idx_fileChanges_filePath ON fileChanges(filePath)")
            setUserVersion(4)
            logger.info("🔄 [DB] Migrated to v4 (deduplicate fileChanges)")
        }

        if version < 5 {
            // Merge orphan prompt events (promptText IS NULL) into the next real prompt
            // in the same session. Reassign file changes, then delete the orphan.
            exec(
                """
                UPDATE fileChanges SET eventID = (
                    SELECT pe2.id FROM promptEvents pe2
                    WHERE pe2.sessionID = (SELECT sessionID FROM promptEvents WHERE id = fileChanges.eventID)
                      AND pe2.promptText IS NOT NULL
                      AND pe2.timestamp > (SELECT timestamp FROM promptEvents WHERE id = fileChanges.eventID)
                    ORDER BY pe2.timestamp ASC LIMIT 1
                )
                WHERE eventID IN (SELECT id FROM promptEvents WHERE promptText IS NULL)
                  AND (
                    SELECT pe2.id FROM promptEvents pe2
                    WHERE pe2.sessionID = (SELECT sessionID FROM promptEvents WHERE id = fileChanges.eventID)
                      AND pe2.promptText IS NOT NULL
                      AND pe2.timestamp > (SELECT timestamp FROM promptEvents WHERE id = fileChanges.eventID)
                    ORDER BY pe2.timestamp ASC LIMIT 1
                  ) IS NOT NULL
                """)
            // Delete orphan events (any remaining with no next prompt lose their file changes via CASCADE)
            exec("DELETE FROM promptEvents WHERE promptText IS NULL")
            setUserVersion(5)
            logger.info("🔄 [DB] Migrated to v5 (merge orphan prompt events)")
        }

        if version < 6 {
            exec(
                """
                CREATE TABLE IF NOT EXISTS commitTemplates (
                    name TEXT PRIMARY KEY,
                    body TEXT NOT NULL,
                    isActive INTEGER NOT NULL DEFAULT 0,
                    createdAt REAL NOT NULL
                )
                """)
            setUserVersion(6)
            logger.info("🔄 [DB] Migrated to v6 (commitTemplates)")
        }

        if version < 7 {
            exec("ALTER TABLE fileChanges ADD COLUMN description TEXT")
            setUserVersion(7)
            logger.info("🔄 [DB] Migrated to v7 (fileChange descriptions)")
        }

        if version < 8 {
            exec("ALTER TABLE sessions ADD COLUMN customName TEXT")
            setUserVersion(8)
            logger.info("🔄 [DB] Migrated to v8 (session customName)")
        }
    }

    // MARK: - CRUD: Sessions

    func upsertSession(_ session: Session) throws {
        let sql = """
            INSERT INTO sessions (id, projectPath, startedAt, lastActivityAt)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET lastActivityAt = excluded.lastActivityAt
            """
        try execute(
            sql,
            bindings: [
                .text(session.id),
                .text(session.projectPath),
                .double(session.startedAt.timeIntervalSince1970),
                .double(session.lastActivityAt.timeIntervalSince1970),
            ])
        // Inline cache update instead of full reload — preserve existing customName
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            var updated = sessions[idx]
            updated.lastActivityAt = session.lastActivityAt
            sessions[idx] = updated
        } else {
            sessions.insert(session, at: 0)
        }
        logger.info("✅ [DB] Upserted session \(session.id)")
    }

    // MARK: - CRUD: PromptEvents

    func insertPromptEvent(_ event: PromptEvent) throws {
        let sql = """
            INSERT OR REPLACE INTO promptEvents (id, sessionID, projectPath, promptText, timestamp, vcs, baseCommitHash)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        try execute(
            sql,
            bindings: [
                .text(event.id.uuidString),
                .text(event.sessionID),
                .text(event.projectPath),
                event.promptText.map { .text($0) } ?? .null,
                .double(event.timestamp.timeIntervalSince1970),
                event.vcs.map { .text($0.rawValue) } ?? .null,
                event.baseCommitHash.map { .text($0) } ?? .null,
            ])
        // Inline cache update: prepend (most recent first) and cap at 500
        if let idx = recentEvents.firstIndex(where: { $0.id == event.id }) {
            recentEvents[idx] = event
        } else {
            recentEvents.insert(event, at: 0)
            if recentEvents.count > 500 { recentEvents.removeLast() }
        }
        logger.info("✅ [DB] Inserted event \(event.id.uuidString)")
    }

    // MARK: - CRUD: FileChanges

    func insertFileChange(_ change: FileChange) throws {
        let sql = """
            INSERT INTO fileChanges (id, eventID, filePath, toolName, timestamp, description)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(eventID, filePath) DO UPDATE SET
                toolName = excluded.toolName,
                timestamp = excluded.timestamp
            """
        try execute(
            sql,
            bindings: [
                .text(change.id.uuidString),
                .text(change.eventID.uuidString),
                .text(change.filePath),
                .text(change.toolName),
                .double(change.timestamp.timeIntervalSince1970),
                change.description.map { .text($0) } ?? .null,
            ])
        // Update cache: replace existing entry for same filePath, or append
        var entries = fileChangesCache[change.eventID, default: []]
        if let idx = entries.firstIndex(where: { $0.filePath == change.filePath }) {
            entries[idx] = change
        } else {
            entries.append(change)
        }
        fileChangesCache[change.eventID] = entries
        logger.info("✅ [DB] Upserted file change \(change.filePath)")
    }

    func insertFileChanges(_ changes: [FileChange]) throws {
        exec("BEGIN TRANSACTION")
        for change in changes {
            try insertFileChange(change)
        }
        exec("COMMIT")
    }

    func fileChanges(forEventID eventID: UUID) throws -> [FileChange] {
        let sql = "SELECT id, eventID, filePath, toolName, timestamp, description FROM fileChanges WHERE eventID = ? ORDER BY timestamp"
        // swiftlint:disable force_unwrapping
        return try query(sql, bindings: [.text(eventID.uuidString)]) { stmt in
            FileChange(
                id: UUID(uuidString: columnText(stmt, 0))!,
                eventID: UUID(uuidString: columnText(stmt, 1))!,
                filePath: columnText(stmt, 2),
                toolName: columnText(stmt, 3),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                description: sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            )
        }
        // swiftlint:enable force_unwrapping
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
        return try query(
            sql,
            bindings: [
                .text(projectPath),
                .double(since.timeIntervalSince1970),
            ]
        ) { stmt in
            let vcsRaw = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            return PromptEvent(
                id: UUID(uuidString: columnText(stmt, 0))!,  // swiftlint:disable:this force_unwrapping
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
        let sql = "SELECT COUNT(DISTINCT filePath) FROM fileChanges WHERE eventID = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, eventID.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    func totalFileCount(forProject projectPath: String, since: Date) throws -> Int {
        let sql = """
            SELECT COUNT(DISTINCT fc.filePath) FROM fileChanges fc
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

    /// Backfill promptText on an orphan event (created before prompt arrived).
    func updatePromptText(_ text: String, forEventID eventID: UUID) throws {
        try execute(
            "UPDATE promptEvents SET promptText = ? WHERE id = ?",
            bindings: [.text(text), .text(eventID.uuidString)]
        )
        // Inline cache update instead of full reload
        if let idx = recentEvents.firstIndex(where: { $0.id == eventID }) {
            let old = recentEvents[idx]
            recentEvents[idx] = PromptEvent(
                id: old.id, sessionID: old.sessionID, projectPath: old.projectPath,
                promptText: text, timestamp: old.timestamp,
                vcs: old.vcs, baseCommitHash: old.baseCommitHash
            )
        }
        logger.info("✅ [DB] Backfilled prompt text for \(eventID.uuidString)")
    }

    /// Update description on a fileChange matched by sessionID + filePath.
    func updateFileDescription(_ description: String, sessionID: String, filePath: String) throws {
        let sql = """
            UPDATE fileChanges SET description = ? WHERE eventID IN (
                SELECT pe.id FROM promptEvents pe WHERE pe.sessionID = ?
            ) AND filePath = ?
            """
        try execute(sql, bindings: [.text(description), .text(sessionID), .text(filePath)])

        // Update cache — find matching entries
        for (eventID, changes) in fileChangesCache {
            if let idx = changes.firstIndex(where: { $0.filePath == filePath }) {
                var updated = changes[idx]
                updated.description = description
                fileChangesCache[eventID]?[idx] = updated
            }
        }
        logger.info("✅ [DB] Updated description for \(filePath)")
    }

    func updateSessionName(_ name: String?, sessionID: String) throws {
        try execute(
            "UPDATE sessions SET customName = ? WHERE id = ?",
            bindings: [name.map { .text($0) } ?? .null, .text(sessionID)]
        )
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].customName = name
        }
        logger.info("✅ [DB] Updated session name for \(sessionID.prefix(8))")
    }

    func deleteSession(id: String) throws {
        try execute("DELETE FROM sessions WHERE id = ?", bindings: [.text(id)])
        // Full reload needed — cascade deletes events + file changes + hook events
        try loadSessions()
        try loadRecentEvents()
        try loadFileChanges()
        try loadRecentHookEvents()
        sessionStateCache.removeValue(forKey: id)
        diffStatCache = diffStatCache.filter { key, _ in
            recentEvents.contains { $0.id == key }
        }
        logger.info("✅ [DB] Deleted session \(id) (cascade)")
    }

    func deletePromptEvent(id: UUID) throws {
        try execute("DELETE FROM promptEvents WHERE id = ?", bindings: [.text(id.uuidString)])
        recentEvents.removeAll { $0.id == id }
        fileChangesCache.removeValue(forKey: id)
        diffStatCache.removeValue(forKey: id)
        logger.info("✅ [DB] Deleted prompt event \(id.uuidString) (cascade)")
    }

    func deleteAllData() throws {
        try execute("DELETE FROM sessions")
        sessions.removeAll()
        recentEvents.removeAll()
        fileChangesCache.removeAll()
        recentHookEvents.removeAll()
        sessionStateCache.removeAll()
        diffStatCache.removeAll()
        logger.info("✅ [DB] Cleared all data")
    }

    func evictOlderThan(days: Int) throws {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        try execute(
            "DELETE FROM sessions WHERE lastActivityAt < ?",
            bindings: [.double(cutoff.timeIntervalSince1970)]
        )
        try loadCache()
        logger.info("✅ [DB] Evicted sessions older than \(days) days")
    }

    // MARK: - CRUD: HookEvents

    func insertHookEvent(_ event: HookEvent) throws {
        let sql = """
            INSERT OR REPLACE INTO hookEvents (id, sessionID, hookEventName, projectPath, timestamp, payload)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        try execute(
            sql,
            bindings: [
                .text(event.id.uuidString),
                .text(event.sessionID),
                .text(event.hookEventName),
                .text(event.projectPath),
                .double(event.timestamp.timeIntervalSince1970),
                event.payload.map { .text($0) } ?? .null,
            ])
        // Inline cache update: prepend and cap at 200
        if let idx = recentHookEvents.firstIndex(where: { $0.id == event.id }) {
            recentHookEvents[idx] = event
        } else {
            recentHookEvents.insert(event, at: 0)
            if recentHookEvents.count > 200 { recentHookEvents.removeLast() }
        }
        // Update session state cache
        rebuildSessionStateCache(for: event.sessionID)
        logger.info("✅ [DB] Inserted hook event \(event.hookEventName) \(event.id.uuidString)")
    }

    func sessionState(for sessionID: String) -> SessionState {
        sessionStateCache[sessionID] ?? .idle
    }

    private func rebuildSessionStateCache(for sessionID: String) {
        guard let latest = recentHookEvents.first(where: { $0.sessionID == sessionID }) else {
            if let session = sessions.first(where: { $0.id == sessionID }) {
                sessionStateCache[sessionID] = session.lastActivityAt.timeIntervalSinceNow > -300 ? .live : .idle
            } else {
                sessionStateCache[sessionID] = .idle
            }
            return
        }
        switch latest.hookEventName {
        case "SessionEnd": sessionStateCache[sessionID] = .ended
        case "Stop": sessionStateCache[sessionID] = .interrupted
        default: sessionStateCache[sessionID] = latest.timestamp.timeIntervalSinceNow > -300 ? .live : .idle
        }
    }

    private func rebuildAllSessionStates() {
        sessionStateCache.removeAll()
        let sessionIDs = Set(sessions.map(\.id))
        for id in sessionIDs {
            rebuildSessionStateCache(for: id)
        }
    }

    // MARK: - CRUD: CommitTemplates

    func saveCommitTemplate(name: String, body: String) throws {
        let sql = """
            INSERT INTO commitTemplates (name, body, isActive, createdAt)
            VALUES (?, ?, 0, ?)
            ON CONFLICT(name) DO UPDATE SET body = excluded.body
            """
        try execute(sql, bindings: [.text(name), .text(body), .double(Date().timeIntervalSince1970)])
        try loadCommitTemplates()
        logger.info("✅ [DB] Saved commit template '\(name)'")
    }

    func deleteCommitTemplate(name: String) throws {
        let wasActive = commitTemplates.first(where: { $0.name == name })?.isActive ?? false
        try execute("DELETE FROM commitTemplates WHERE name = ?", bindings: [.text(name)])
        if wasActive {
            // No active template — falls back to built-in default
        }
        try loadCommitTemplates()
        logger.info("✅ [DB] Deleted commit template '\(name)'")
    }

    func setActiveTemplate(name: String) throws {
        exec("UPDATE commitTemplates SET isActive = 0")
        try execute("UPDATE commitTemplates SET isActive = 1 WHERE name = ?", bindings: [.text(name)])
        try loadCommitTemplates()
        logger.info("✅ [DB] Set active template '\(name)'")
    }

    /// Backfill baseCommitHash for legacy events that have NULL.
    func backfillBaseCommitHashes() async {
        let events: [PromptEvent] = await MainActor.run {
            recentEvents.filter { $0.baseCommitHash == nil && $0.vcs == .git }
        }
        guard !events.isEmpty else { return }
        logger.info("🔄 [DB] Backfilling baseCommitHash for \(events.count) events")

        let provider = GitProvider()
        var cache: [String: String] = [:]

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

        await MainActor.run {
            // Inline update: patch baseCommitHash on cached events instead of full reload
            for event in events {
                if let idx = recentEvents.firstIndex(where: { $0.id == event.id }),
                    recentEvents[idx].baseCommitHash == nil
                {
                    let old = recentEvents[idx]
                    if let hash = cache["\(old.projectPath)|\(Int(old.timestamp.timeIntervalSince1970))"] {
                        recentEvents[idx] = PromptEvent(
                            id: old.id, sessionID: old.sessionID, projectPath: old.projectPath,
                            promptText: old.promptText, timestamp: old.timestamp,
                            vcs: old.vcs, baseCommitHash: hash
                        )
                    }
                }
            }
            logger.info("🔄 [DB] Backfill complete")
        }
    }

    // MARK: - Cache Loading

    private func loadCache() throws {
        try loadSessions()
        try loadRecentEvents()
        try loadFileChanges()
        try loadRecentHookEvents()
        try loadCommitTemplates()
        rebuildAllSessionStates()
    }

    private func loadSessions() throws {
        sessions = try query(
            "SELECT id, projectPath, startedAt, lastActivityAt, customName FROM sessions ORDER BY lastActivityAt DESC"
        ) { stmt in
            Session(
                id: columnText(stmt, 0),
                projectPath: columnText(stmt, 1),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                lastActivityAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                customName: sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            )
        }
    }

    private func loadRecentEvents() throws {
        recentEvents = try query(
            "SELECT id, sessionID, projectPath, promptText, timestamp, vcs, baseCommitHash FROM promptEvents ORDER BY timestamp DESC LIMIT 500"
        ) { stmt in
            let vcsRaw = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            return PromptEvent(
                id: UUID(uuidString: columnText(stmt, 0))!,  // swiftlint:disable:this force_unwrapping
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
        // Single batch query — join with promptEvents to filter out-of-repo paths
        let sql = """
            SELECT fc.id, fc.eventID, fc.filePath, fc.toolName, fc.timestamp, fc.description, pe.projectPath
            FROM fileChanges fc
            JOIN promptEvents pe ON fc.eventID = pe.id
            ORDER BY pe.timestamp DESC, fc.timestamp ASC
            LIMIT 5000
            """
        // swiftlint:disable force_unwrapping
        var cache: [UUID: [FileChange]] = [:]
        let rows: [(FileChange, String)] = try query(sql) { stmt in
            let change = FileChange(
                id: UUID(uuidString: columnText(stmt, 0))!,
                eventID: UUID(uuidString: columnText(stmt, 1))!,
                filePath: columnText(stmt, 2),
                toolName: columnText(stmt, 3),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                description: sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            )
            let projectPath = columnText(stmt, 6)
            return (change, projectPath)
        }
        // swiftlint:enable force_unwrapping
        for (change, projectPath) in rows {
            guard change.filePath.hasPrefix(projectPath + "/") else { continue }
            cache[change.eventID, default: []].append(change)
        }
        fileChangesCache = cache
    }

    private func loadRecentHookEvents() throws {
        recentHookEvents = try query(
            "SELECT id, sessionID, hookEventName, projectPath, timestamp, payload FROM hookEvents ORDER BY timestamp DESC LIMIT 200"
        ) { stmt in
            HookEvent(
                id: UUID(uuidString: columnText(stmt, 0))!,  // swiftlint:disable:this force_unwrapping
                sessionID: columnText(stmt, 1),
                hookEventName: columnText(stmt, 2),
                projectPath: columnText(stmt, 3),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                payload: sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            )
        }
    }

    private func loadCommitTemplates() throws {
        commitTemplates = try query(
            "SELECT name, body, isActive, createdAt FROM commitTemplates ORDER BY createdAt"
        ) { stmt in
            CommitTemplate(
                name: columnText(stmt, 0),
                body: columnText(stmt, 1),
                isActive: sqlite3_column_int(stmt, 2) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
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
            results.append(map(stmt!))  // swiftlint:disable:this force_unwrapping
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
