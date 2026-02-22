import SwiftUI

// MARK: - Sidebar Item

/// Flat sidebar item — no Section, no DisclosureGroup.
/// Session IDs are valid UUIDs so we use UUID for everything.
private struct SidebarItem: Identifiable {
    let id: UUID
    let kind: Kind
    let session: Session?
    let event: PromptEvent?

    enum Kind { case session, event }

    static func session(_ s: Session) -> SidebarItem {
        // swiftlint:disable:next force_unwrapping
        SidebarItem(id: UUID(uuidString: s.id)!, kind: .session, session: s, event: nil)
    }

    static func event(_ e: PromptEvent) -> SidebarItem {
        SidebarItem(id: e.id, kind: .event, session: nil, event: e)
    }
}

@MainActor @Observable
private final class SidebarState {
    var selection: UUID?
    var expandedSessions: Set<String> = []
    var hideEmptyEvents = false
    var keyMonitor: Any?
}

struct ContentView: View {
    @Environment(Database.self) private var database
    @State private var state = SidebarState()

    private func filteredEvents(for sessionID: String) -> [PromptEvent] {
        let allEvents = database.eventsForSession(id: sessionID)
        guard state.hideEmptyEvents else { return allEvents }
        let latestID = allEvents.first?.id  // most recent = "live", never filtered
        return allEvents.filter { event in
            event.id == latestID || !(database.fileChangesCache[event.id] ?? []).isEmpty
        }
    }

    /// Only the most recent event in a session shows state indicators.
    private func isLatestEvent(_ event: PromptEvent) -> Bool {
        let allEvents = database.eventsForSession(id: event.sessionID)
        return allEvents.first?.id == event.id
    }

    private var flatItems: [SidebarItem] {
        var items: [SidebarItem] = []
        for session in database.sessions {
            let events = filteredEvents(for: session.id)
            guard !events.isEmpty else { continue }
            items.append(.session(session))
            if state.expandedSessions.contains(session.id) {
                items.append(contentsOf: events.map { .event($0) })
            }
        }
        return items
    }

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            detail
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        let s = state
        let db = database
        state.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.option) else { return event }
            switch event.keyCode {
            case 123:  // Left arrow
                ContentView.toggleFoldExpand(expand: false, state: s, database: db)
                return nil
            case 124:  // Right arrow
                ContentView.toggleFoldExpand(expand: true, state: s, database: db)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = state.keyMonitor {
            NSEvent.removeMonitor(monitor)
            state.keyMonitor = nil
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if database.sessions.isEmpty {
            ContentUnavailableView(
                "No Sessions",
                systemImage: "tray",
                description: Text("Start a Claude Code session to see prompts here.")
            )
        } else {
            @Bindable var state = state
            List(selection: $state.selection) {
                ForEach(flatItems) { item in
                    row(for: item)
                }
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        state.hideEmptyEvents.toggle()
                    } label: {
                        Image(systemName: state.hideEmptyEvents ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help(state.hideEmptyEvents ? "Showing only prompts with file changes" : "Showing all prompts")
                }
            }
        }
    }

    private func row(for item: SidebarItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if item.kind == .session, let session = item.session {
                sessionRow(session)
            } else if let event = item.event {
                eventRow(event)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, item.kind == .event ? 20 : 0)
        .tag(item.id)
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let events = filteredEvents(for: session.id)
        let eventCount = events.count
        let firstPrompt = events.first?.promptText
        let expanded = state.expandedSessions.contains(session.id)
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .animation(.smooth(duration: 0.2), value: expanded)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.25)) {
                        if expanded {
                            state.expandedSessions.remove(session.id)
                        } else {
                            state.expandedSessions.insert(session.id)
                        }
                    }
                }
            Image(systemName: "folder\(expanded ? ".fill" : "")")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    let sState = database.sessionState(for: session.id)
                    if sState == .live {
                        Circle().fill(.green).frame(width: 6, height: 6)
                    } else if sState == .interrupted {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                    }
                    Text((session.projectPath as NSString).lastPathComponent)
                        .font(.callout.weight(.medium))
                    if let firstPrompt {
                        Text("·").foregroundStyle(.quaternary)
                        Text(firstPrompt).lineLimit(1).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                Text("\(eventCount) prompt\(eventCount == 1 ? "" : "s") · \(session.startedAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: PromptEvent) -> some View {
        let fileCount = database.fileChangesCache[event.id]?.count ?? 0
        let showState = isLatestEvent(event)
        let sState = showState ? database.sessionState(for: event.sessionID) : .idle
        Text(event.promptText ?? "(no prompt)")
            .lineLimit(2)
            .font(.callout)
        HStack(spacing: 6) {
            SessionStateIndicator(state: sState)
            Text(event.timestamp, style: .time)
            if fileCount > 0 {
                Label("\(fileCount)", systemImage: "doc")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let sel = state.selection,
            let event = database.recentEvents.first(where: { $0.id == sel })
        {
            DiffDetailView(event: event)
        } else if let sel = state.selection,
            let session = database.sessions.first(where: { UUID(uuidString: $0.id) == sel })
        {
            SessionSummaryView(session: session)
        } else {
            Text("Select a prompt")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Keyboard

    private static func toggleFoldExpand(expand: Bool, state: SidebarState, database: Database) {
        guard let selection = state.selection else { return }

        let sessionID: String
        if let event = database.recentEvents.first(where: { $0.id == selection }) {
            sessionID = event.sessionID
        } else if let session = database.sessions.first(where: { UUID(uuidString: $0.id) == selection }) {
            sessionID = session.id
        } else {
            return
        }

        withAnimation(.smooth(duration: 0.25)) {
            if expand {
                state.expandedSessions.insert(sessionID)
            } else {
                state.expandedSessions.remove(sessionID)
            }
        }
    }
}

