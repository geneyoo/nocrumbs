import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "SessionSummaryVM")

@Observable @MainActor
final class SessionSummaryViewModel {
    private(set) var promptDiffStats: [UUID: PromptDiffStat] = [:]
    private(set) var isLoading = false
    private(set) var loadingProgress: (completed: Int, total: Int) = (0, 0)
    private(set) var errors: [UUID: String] = [:]
    private(set) var remoteURL: String?

    private var currentSessionID: String?
    private let provider: any VCSProvider

    init(provider: any VCSProvider = GitProvider()) {
        self.provider = provider
    }

    // MARK: - Computed Aggregates

    var aggregateAdditions: Int {
        promptDiffStats.values.reduce(0) { $0 + $1.totalAdditions }
    }

    var aggregateDeletions: Int {
        promptDiffStats.values.reduce(0) { $0 + $1.totalDeletions }
    }

    var uniqueFileCount: Int {
        var paths = Set<String>()
        for stat in promptDiffStats.values {
            for file in stat.fileStats {
                paths.insert(file.filePath)
            }
        }
        return paths.count
    }

    var uniqueFiles: [AggregatedFileStat] {
        var byPath: [String: (status: FileDiff.FileStatus, adds: Int, dels: Int, prompts: Set<UUID>)] = [:]

        // Sort by eventID for deterministic iteration — dictionary order is random
        for (_, promptStat) in promptDiffStats.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            for file in promptStat.fileStats {
                var entry = byPath[file.filePath] ?? (status: file.status, adds: 0, dels: 0, prompts: [])
                entry.adds += file.additions
                entry.dels += file.deletions
                entry.prompts.insert(promptStat.eventID)
                // Last status wins (a file could be added then modified)
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

    func commitURL(for hash: String) -> URL? {
        guard let remote = remoteURL else { return nil }
        return RemoteURLParser.commitURL(remoteURL: remote, hash: hash)
    }

    // MARK: - Load

    func load(session: Session, events: [PromptEvent], fileChangesCache: [UUID: [FileChange]]) {
        guard currentSessionID != session.id else { return }
        currentSessionID = session.id
        promptDiffStats = [:]
        errors = [:]
        remoteURL = nil
        isLoading = true

        // Fetch remote URL once per session (Git only)
        if events.first?.vcs == .git, let projectPath = events.first?.projectPath {
            Task {
                self.remoteURL = try? await GitProvider().remoteURL(at: projectPath)
            }
        }

        let eventsWithChanges = events.filter { event in
            event.vcs != nil
                && event.baseCommitHash != nil
                && !(fileChangesCache[event.id] ?? []).isEmpty
        }

        loadingProgress = (0, eventsWithChanges.count)

        guard !eventsWithChanges.isEmpty else {
            isLoading = false
            return
        }

        logger.info("Loading diffstats for \(eventsWithChanges.count) events in session \(session.id)")

        let sessionID = session.id
        let provider = self.provider

        Task { [weak self] in
            await withTaskGroup(of: (UUID, Result<PromptDiffStat, Error>).self) { group in
                for event in eventsWithChanges {
                    let changes = fileChangesCache[event.id] ?? []
                    group.addTask {
                        do {
                            let stat = try await Self.loadDiffStat(
                                event: event, fileChanges: changes, provider: provider
                            )
                            return (event.id, .success(stat))
                        } catch {
                            return (event.id, .failure(error))
                        }
                    }
                }

                for await (eventID, result) in group {
                    guard let self, self.currentSessionID == sessionID else { return }
                    switch result {
                    case .success(let stat):
                        self.promptDiffStats[eventID] = stat
                    case .failure(let error):
                        self.errors[eventID] = error.localizedDescription
                        logger.warning("Failed to load diffstat for event \(eventID): \(error.localizedDescription)")
                    }
                    self.loadingProgress.completed += 1
                }
            }

            guard let self, self.currentSessionID == sessionID else { return }
            self.isLoading = false
            logger.info("Loaded \(self.promptDiffStats.count) diffstats, \(self.errors.count) errors")
        }
    }

    /// Incremental reload — loads only events not already cached.
    func reloadIfNeeded(session: Session, events: [PromptEvent], fileChangesCache: [UUID: [FileChange]]) {
        guard currentSessionID == session.id else {
            load(session: session, events: events, fileChangesCache: fileChangesCache)
            return
        }

        let newEvents = events.filter { event in
            event.vcs != nil
                && event.baseCommitHash != nil
                && !(fileChangesCache[event.id] ?? []).isEmpty
                && promptDiffStats[event.id] == nil
                && errors[event.id] == nil
        }

        guard !newEvents.isEmpty else { return }

        let sessionID = session.id
        let provider = self.provider

        Task { [weak self] in
            await withTaskGroup(of: (UUID, Result<PromptDiffStat, Error>).self) { group in
                for event in newEvents {
                    let changes = fileChangesCache[event.id] ?? []
                    group.addTask {
                        do {
                            let stat = try await Self.loadDiffStat(
                                event: event, fileChanges: changes, provider: provider
                            )
                            return (event.id, .success(stat))
                        } catch {
                            return (event.id, .failure(error))
                        }
                    }
                }

                for await (eventID, result) in group {
                    guard let self, self.currentSessionID == sessionID else { return }
                    switch result {
                    case .success(let stat):
                        self.promptDiffStats[eventID] = stat
                    case .failure(let error):
                        self.errors[eventID] = error.localizedDescription
                    }
                }
            }
        }
    }

    func markdownSummary(session: Session, events: [PromptEvent]) -> String {
        SessionMarkdownFormatter.format(
            .init(
                session: session,
                events: events,
                promptDiffStats: promptDiffStats,
                uniqueFiles: uniqueFiles,
                aggregateAdditions: aggregateAdditions,
                aggregateDeletions: aggregateDeletions
            ))
    }

    func invalidate() {
        currentSessionID = nil
        promptDiffStats = [:]
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
