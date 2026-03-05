import Foundation

/// Represents either a visible event or a collapsed noise group in the sidebar.
enum SidebarDisplayItem: Equatable {
    case event(PromptEvent)
    case collapsed(events: [PromptEvent], groupKey: String)
}

/// Pure functions for sidebar noise reduction. Testable without UI.
enum SidebarFilter {

    /// Collapses no-change prompts between change prompts.
    /// Always shows: events with file changes + the latest event (index 0, newest first).
    /// Consecutive no-change events between them become a single collapsed pill.
    static func collapseNoChangePrompts(
        _ events: [PromptEvent],
        fileChangesCache: [UUID: [FileChange]],
        sessionID: String
    ) -> [SidebarDisplayItem] {
        guard !events.isEmpty else { return [] }

        // events are newest-first. Tag each as "must show" or "noise".
        var mustShow = Set<Int>()
        mustShow.insert(0) // latest event always visible

        for (idx, event) in events.enumerated() {
            if !(fileChangesCache[event.id] ?? []).isEmpty {
                mustShow.insert(idx)
            }
        }

        // If everything is visible anyway, skip
        if mustShow.count >= events.count {
            return events.map { .event($0) }
        }

        // Walk events, collapsing consecutive noise into pills
        var result: [SidebarDisplayItem] = []
        var noiseRun: [PromptEvent] = []
        var groupIndex = 0

        func flushNoise() {
            guard !noiseRun.isEmpty else { return }
            result.append(.collapsed(events: noiseRun, groupKey: "\(sessionID)-\(groupIndex)"))
            groupIndex += 1
            noiseRun = []
        }

        for (idx, event) in events.enumerated() {
            if mustShow.contains(idx) {
                flushNoise()
                result.append(.event(event))
            } else {
                noiseRun.append(event)
            }
        }
        flushNoise()

        return result
    }
}
