import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "SessionSummaryVM")

@Observable @MainActor
final class SessionSummaryViewModel {
    private(set) var isLoading = false
    private(set) var loadingProgress: (completed: Int, total: Int) = (0, 0)
    private(set) var errors: [UUID: String] = [:]
    private(set) var remoteURL: String?

    private var currentSessionID: String?
    private var loadTask: Task<Void, Never>?
    private let provider: any VCSProvider

    init(provider: any VCSProvider = GitProvider()) {
        self.provider = provider
    }

    // MARK: - Access (reads from Database cache)

    var promptDiffStats: [UUID: PromptDiffStat] {
        Database.shared.diffStatCache
    }

    var aggregateAdditions: Int {
        currentEventIDs.reduce(0) { sum, id in
            sum + (Database.shared.diffStatCache[id]?.totalAdditions ?? 0)
        }
    }

    var aggregateDeletions: Int {
        currentEventIDs.reduce(0) { sum, id in
            sum + (Database.shared.diffStatCache[id]?.totalDeletions ?? 0)
        }
    }

    var uniqueFiles: [AggregatedFileStat] {
        var byPath: [String: (status: FileDiff.FileStatus, adds: Int, dels: Int, prompts: Set<UUID>)] = [:]
        let cache = Database.shared.diffStatCache

        for id in currentEventIDs {
            guard let promptStat = cache[id] else { continue }
            for file in promptStat.fileStats {
                var entry = byPath[file.filePath] ?? (status: file.status, adds: 0, dels: 0, prompts: [])
                entry.adds += file.additions
                entry.dels += file.deletions
                entry.prompts.insert(promptStat.eventID)
                entry.status = file.status
                byPath[file.filePath] = entry
            }
        }

        return byPath.map { path, entry in
            AggregatedFileStat(
                filePath: path,
                status: entry.status,
                totalAdditions: entry.adds,
                totalDeletions: entry.dels,
                promptCount: entry.prompts.count
            )
        }
        .sorted { $0.totalChanges != $1.totalChanges ? $0.totalChanges > $1.totalChanges : $0.filePath < $1.filePath }
    }

    /// Event IDs belonging to the current session (for scoping aggregates).
    private var currentEventIDs: [UUID] {
        guard let sid = currentSessionID else { return [] }
        return Database.shared.eventsForSession(id: sid).map(\.id)
    }

    func commitURL(for hash: String) -> URL? {
        guard let remote = remoteURL else { return nil }
        return RemoteURLParser.commitURL(remoteURL: remote, hash: hash)
    }

    // MARK: - Load

    func load(session: Session, events: [PromptEvent], fileChangesCache: [UUID: [FileChange]]) {
        guard currentSessionID != session.id else { return }
        currentSessionID = session.id
        errors = [:]
        remoteURL = nil

        // Cancel any in-flight load from a previous session
        loadTask?.cancel()

        // Fetch remote URL once per session
        if events.first?.vcs == .git, let projectPath = events.first?.projectPath {
            Task {
                self.remoteURL = try? await GitProvider().remoteURL(at: projectPath)
            }
        }

        loadMissing(events: events, fileChangesCache: fileChangesCache, sessionID: session.id)
    }

    func reloadIfNeeded(session: Session, events: [PromptEvent], fileChangesCache: [UUID: [FileChange]]) {
        guard currentSessionID == session.id else {
            load(session: session, events: events, fileChangesCache: fileChangesCache)
            return
        }
        loadMissing(events: events, fileChangesCache: fileChangesCache, sessionID: session.id)
    }

    private func loadMissing(events: [PromptEvent], fileChangesCache: [UUID: [FileChange]], sessionID: String) {
        let cache = Database.shared.diffStatCache

        let uncached = events.filter { event in
            event.vcs != nil
                && event.baseCommitHash != nil
                && !(fileChangesCache[event.id] ?? []).isEmpty
                && cache[event.id] == nil
                && errors[event.id] == nil
        }

        guard !uncached.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true
        loadingProgress = (0, uncached.count)

        logger.info("Loading diffstats for \(uncached.count) uncached events in session \(sessionID)")

        loadTask = Task { [weak self] in
            await withTaskGroup(of: (UUID, Result<PromptDiffStat, Error>).self) { group in
                for event in uncached {
                    let changes = fileChangesCache[event.id] ?? []
                    let eventProvider = event.vcs.map { makeProvider(for: $0) } ?? GitProvider()
                    group.addTask {
                        do {
                            let stat = try await Self.loadDiffStat(
                                event: event, fileChanges: changes, provider: eventProvider
                            )
                            return (event.id, .success(stat))
                        } catch {
                            return (event.id, .failure(error))
                        }
                    }
                }

                for await (eventID, result) in group {
                    guard let self, !Task.isCancelled, self.currentSessionID == sessionID else { return }
                    switch result {
                    case .success(let stat):
                        Database.shared.diffStatCache[eventID] = stat
                    case .failure(let error):
                        self.errors[eventID] = error.localizedDescription
                        logger.warning("Failed to load diffstat for event \(eventID): \(error.localizedDescription)")
                    }
                    self.loadingProgress.completed += 1
                }
            }

            guard let self, !Task.isCancelled, self.currentSessionID == sessionID else { return }
            self.isLoading = false
            logger.info("Loaded diffstats, cache now has \(Database.shared.diffStatCache.count) entries")
        }
    }

    func markdownSummary(session: Session, events: [PromptEvent], fileChangesCache: [UUID: [FileChange]] = [:]) -> String {
        var descriptions: [String: String] = [:]
        for event in events {
            for change in fileChangesCache[event.id] ?? [] {
                if let desc = change.description {
                    descriptions[change.filePath] = desc
                }
            }
        }
        return SessionMarkdownFormatter.format(
            .init(
                session: session,
                events: events,
                promptDiffStats: Database.shared.diffStatCache,
                uniqueFiles: uniqueFiles,
                aggregateAdditions: aggregateAdditions,
                aggregateDeletions: aggregateDeletions,
                fileDescriptions: descriptions
            ))
    }

    func invalidate() {
        currentSessionID = nil
        loadTask?.cancel()
        loadTask = nil
        errors = [:]
        remoteURL = nil
        isLoading = false
    }

    // MARK: - Private

    private static func loadDiffStat(
        event: PromptEvent, fileChanges: [FileChange], provider: any VCSProvider
    ) async throws -> PromptDiffStat {
        guard let baseHash = event.baseCommitHash else {
            return PromptDiffStat(eventID: event.id, fileStats: [])
        }

        let projectPath = event.projectPath
        let relativePaths = fileChanges.compactMap { change -> String? in
            guard change.filePath.hasPrefix(projectPath + "/") else { return nil }
            return String(change.filePath.dropFirst(projectPath.count + 1))
        }

        let isValid = try await provider.isValidCommit(baseHash, at: projectPath)
        guard isValid else {
            throw VCSError.commandFailed("git", 1, "Commit \(String(baseHash.prefix(7))) no longer exists")
        }

        let raw = try await provider.diffFromBase(baseHash, filePaths: relativePaths, at: projectPath)
        let fileDiffs = DiffParser.parse(raw)
        let stats = fileDiffs.map { DiffStat.from($0) }

        return PromptDiffStat(eventID: event.id, fileStats: stats)
    }
}
