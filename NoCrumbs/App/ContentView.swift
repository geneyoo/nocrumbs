import SwiftUI

// MARK: - Sidebar Item

/// Flat sidebar item — no Section, no DisclosureGroup.
/// Session IDs are valid UUIDs so we use UUID for everything.
private struct SidebarItem: Identifiable {
    let id: UUID
    let kind: Kind
    let session: Session?
    let event: PromptEvent?
    let projectName: String?

    enum Kind { case timePeriodHeader, projectHeader, session, event }

    static func timePeriodHeader(_ period: TimePeriod) -> SidebarItem {
        SidebarItem(id: UUID(), kind: .timePeriodHeader, session: nil, event: nil, projectName: period.label)
    }

    static func projectHeader(_ name: String) -> SidebarItem {
        SidebarItem(id: UUID(), kind: .projectHeader, session: nil, event: nil, projectName: name)
    }

    static func session(_ s: Session) -> SidebarItem {
        // swiftlint:disable:next force_unwrapping
        SidebarItem(id: UUID(uuidString: s.id)!, kind: .session, session: s, event: nil, projectName: nil)
    }

    static func event(_ e: PromptEvent) -> SidebarItem {
        SidebarItem(id: e.id, kind: .event, session: nil, event: e, projectName: nil)
    }
}

@MainActor @Observable
private final class SidebarState {
    var selection: UUID?
    var expandedSessions: Set<String> = []
    var hideEmptyEvents = false
    var keyMonitor: Any?
}

enum TimePeriod: Int, CaseIterable {
    case today, yesterday, thisWeek, older

    var label: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .older: "Older"
        }
    }

    static func period(for date: Date) -> TimePeriod {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date())) else { return .older }
        if date >= weekAgo { return .thisWeek }
        return .older
    }
}

struct ContentView: View {
    @Environment(Database.self) private var database
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
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
        // Bucket sessions by time period
        let byPeriod = Dictionary(grouping: database.sessions) {
            TimePeriod.period(for: $0.lastActivityAt)
        }

        // Determine if we need time headers (skip if all in one period)
        let activePeriods = TimePeriod.allCases.filter { byPeriod[$0] != nil }
        let showTimeHeaders = activePeriods.count > 1

        var items: [SidebarItem] = []
        for period in TimePeriod.allCases {
            guard let periodSessions = byPeriod[period] else { continue }

            // Group within period by project
            let grouped = Dictionary(grouping: periodSessions) {
                ($0.projectPath as NSString).lastPathComponent
            }
            var seenProjects: [String] = []
            for session in periodSessions {
                let name = (session.projectPath as NSString).lastPathComponent
                if !seenProjects.contains(name) {
                    seenProjects.append(name)
                }
            }

            // Check if this period has any visible sessions
            let hasVisible = periodSessions.contains { !filteredEvents(for: $0.id).isEmpty }
            guard hasVisible else { continue }

            if showTimeHeaders {
                items.append(.timePeriodHeader(period))
            }

            for projectName in seenProjects {
                guard let sessions = grouped[projectName] else { continue }
                let hasVisibleSessions = sessions.contains { !filteredEvents(for: $0.id).isEmpty }
                guard hasVisibleSessions else { continue }
                items.append(.projectHeader(projectName))
                for session in sessions {
                    let events = filteredEvents(for: session.id)
                    guard !events.isEmpty else { continue }
                    items.append(.session(session))
                    if state.expandedSessions.contains(session.id) {
                        items.append(contentsOf: events.map { .event($0) })
                    }
                }
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
        .onAppear {
            installKeyMonitor()
            autoSelectFirstEvent()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: database.recentEvents.count) { _, _ in
            autoSelectFirstEvent()
        }
        .onChange(of: deepLinkRouter.pendingSessionID) { _, newValue in
            guard newValue != nil else { return }
            navigateToDeepLink()
        }
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
            SetupView()
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

    @ViewBuilder
    private func row(for item: SidebarItem) -> some View {
        switch item.kind {
        case .timePeriodHeader:
            timePeriodHeaderRow(item.projectName ?? "")
                .tag(item.id)
        case .projectHeader:
            projectHeaderRow(item.projectName ?? "")
                .tag(item.id)
        case .session:
            if let session = item.session {
                VStack(alignment: .leading, spacing: 2) {
                    sessionRow(session)
                }
                .padding(.vertical, 2)
                .tag(item.id)
            }
        case .event:
            if let event = item.event {
                VStack(alignment: .leading, spacing: 2) {
                    eventRow(event)
                }
                .padding(.vertical, 2)
                .padding(.leading, 20)
                .tag(item.id)
            }
        }
    }

    @ViewBuilder
    private func timePeriodHeaderRow(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(.quaternary)
            .textCase(.uppercase)
            .padding(.top, LayoutGuide.paddingS)
            .padding(.bottom, LayoutGuide.paddingXS)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func projectHeaderRow(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let events = filteredEvents(for: session.id)
        let eventCount = events.count
        let firstPrompt = events.first?.promptText
        let expanded = state.expandedSessions.contains(session.id)
        let sState = database.sessionState(for: session.id)
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if sState == .live {
                        Circle().fill(AppColors.live).frame(width: 6, height: 6)
                    } else if sState == .interrupted {
                        Circle().fill(AppColors.paused).frame(width: 6, height: 6)
                    }
                    Text(firstPrompt ?? "(no prompt)")
                        .font(.callout)
                        .lineLimit(1)
                }
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
            SessionSummaryView(session: session) { event in
                state.expandedSessions.insert(session.id)
                state.selection = event.id
            }
        } else {
            Text("Select a prompt")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Deep Link Navigation

    private func autoSelectFirstEvent() {
        guard state.selection == nil else { return }
        // Select the most recent event from the most recent session
        guard let session = database.sessions.first else { return }
        let events = filteredEvents(for: session.id)
        if let first = events.first {
            state.expandedSessions.insert(session.id)
            state.selection = first.id
        }
    }

    private func navigateToDeepLink() {
        guard let (sessionIDPrefix, eventID) = deepLinkRouter.consume() else { return }

        // Prefix match: annotations use truncated session IDs (8-char)
        guard let session = database.sessions.first(where: { $0.id.hasPrefix(sessionIDPrefix) })
        else { return }

        guard let sessionUUID = UUID(uuidString: session.id) else { return }

        state.expandedSessions.insert(session.id)

        if let eventID {
            state.selection = eventID
        } else {
            state.selection = sessionUUID
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
