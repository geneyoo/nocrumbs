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
            SessionDetailView(session: session, database: database)
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

// MARK: - Session Detail

private struct SessionDetailView: View {
    let session: Session
    let database: Database

    private var events: [PromptEvent] {
        database.eventsForSession(id: session.id)
    }

    private var totalFiles: Int {
        events.reduce(0) { $0 + (database.fileChangesCache[$1.id]?.count ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Session") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("ID").foregroundStyle(.secondary)
                            Text(session.id).monospaced()
                        }
                        GridRow {
                            Text("Project").foregroundStyle(.secondary)
                            Text(session.projectPath).monospaced()
                        }
                        GridRow {
                            Text("Started").foregroundStyle(.secondary)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .standard))
                        }
                        GridRow {
                            Text("Last Activity").foregroundStyle(.secondary)
                            Text(session.lastActivityAt.formatted(date: .abbreviated, time: .standard))
                        }
                        GridRow {
                            Text("Prompts").foregroundStyle(.secondary)
                            Text("\(events.count)")
                        }
                        GridRow {
                            Text("Files").foregroundStyle(.secondary)
                            Text("\(totalFiles)")
                        }
                    }
                    .padding(4)
                }
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 400)
    }
}

// MARK: - Event Detail

private struct EventDetailView: View {
    let event: PromptEvent
    let database: Database

    private var fileChanges: [FileChange] {
        database.fileChangesCache[event.id] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Prompt") {
                    Text(event.promptText ?? "(no prompt text)")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }

                GroupBox("Metadata") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Session").foregroundStyle(.secondary)
                            Text(event.sessionID).monospaced()
                        }
                        GridRow {
                            Text("Time").foregroundStyle(.secondary)
                            Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                        }
                        GridRow {
                            Text("Project").foregroundStyle(.secondary)
                            Text(event.projectPath).monospaced()
                        }
                        if let vcs = event.vcs {
                            GridRow {
                                Text("VCS").foregroundStyle(.secondary)
                                Text(vcs.rawValue)
                            }
                        }
                    }
                    .padding(4)
                }

                if !fileChanges.isEmpty {
                    GroupBox("Files Changed (\(fileChanges.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(fileChanges) { change in
                                HStack {
                                    Image(systemName: change.toolName == "Write" ? "doc.badge.plus" : "pencil")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(relativePath(change.filePath))
                                        .monospaced()
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(change.toolName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 400)
    }

    private func relativePath(_ path: String) -> String {
        if path.hasPrefix(event.projectPath) {
            return String(path.dropFirst(event.projectPath.count + 1))
        }
        return (path as NSString).lastPathComponent
    }
}

// MARK: - Session State Indicator

private struct SessionStateIndicator: View {
    let state: SessionState

    var body: some View {
        switch state {
        case .live:
            LiveDot()
            Text("Live")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
        case .interrupted:
            Image(systemName: "pause.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Paused")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
        case .ended:
            Image(systemName: "stop.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Ended")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Live Indicator

private struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 6, height: 6)
            .scaleEffect(pulse ? 1.4 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
