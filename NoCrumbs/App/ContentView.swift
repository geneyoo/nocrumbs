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
    let sequencePosition: SequencePosition

    let olderCount: Int
    let sessionID: String?

    enum Kind { case timePeriodHeader, projectHeader, session, event, showOlder, daySeparator, collapsed }

    let collapsedCount: Int
    let groupKey: String?

    enum SequencePosition {
        case solo
        case first
        case middle
        case last

        var isFirst: Bool { if case .first = self { return true } else { return false } }
        var isLast: Bool { if case .last = self { return true } else { return false } }
    }

    static func timePeriodHeader(_ period: TimePeriod) -> SidebarItem {
        SidebarItem(id: UUID(), kind: .timePeriodHeader, session: nil, event: nil, projectName: period.label, sequencePosition: .solo, olderCount: 0, sessionID: nil, collapsedCount: 0, groupKey: nil)
    }

    static func projectHeader(_ name: String) -> SidebarItem {
        SidebarItem(id: UUID(), kind: .projectHeader, session: nil, event: nil, projectName: name, sequencePosition: .solo, olderCount: 0, sessionID: nil, collapsedCount: 0, groupKey: nil)
    }

    static func session(_ s: Session) -> SidebarItem {
        let uuid = UUID(uuidString: s.id) ?? UUID()
        return SidebarItem(id: uuid, kind: .session, session: s, event: nil, projectName: nil, sequencePosition: .solo, olderCount: 0, sessionID: nil, collapsedCount: 0, groupKey: nil)
    }

    static func event(_ e: PromptEvent, position: SequencePosition = .solo) -> SidebarItem {
        SidebarItem(id: e.id, kind: .event, session: nil, event: e, projectName: nil, sequencePosition: position, olderCount: 0, sessionID: nil, collapsedCount: 0, groupKey: nil)
    }

    static func showOlder(count: Int, sessionID: String) -> SidebarItem {
        SidebarItem(id: UUID(), kind: .showOlder, session: nil, event: nil, projectName: nil, sequencePosition: .solo, olderCount: count, sessionID: sessionID, collapsedCount: 0, groupKey: nil)
    }

    static func daySeparator(_ label: String) -> SidebarItem {
        SidebarItem(id: UUID(), kind: .daySeparator, session: nil, event: nil, projectName: label, sequencePosition: .solo, olderCount: 0, sessionID: nil, collapsedCount: 0, groupKey: nil)
    }

    static func collapsed(count: Int, groupKey: String) -> SidebarItem {
        SidebarItem(id: UUID(), kind: .collapsed, session: nil, event: nil, projectName: nil, sequencePosition: .solo, olderCount: 0, sessionID: nil, collapsedCount: count, groupKey: groupKey)
    }
}

@MainActor @Observable
private final class SidebarState {
    var selection: UUID?
    var expandedSessions: Set<String> = []
    @ObservationIgnored
    @AppStorage("hideEmptyEvents") var hideEmptyEvents = true
    @ObservationIgnored
    @AppStorage("confirmBeforeDelete") var confirmBeforeDelete = true
    var collapsedProjects: Set<String> = []
    var showAllPrompts: Set<String> = []
    var expandedCollapseGroups: Set<String> = []
    var keyMonitor: Any?
    var renamingSessionID: String?
    var renameText = ""
    var deletingSessionID: String?
    var deletingEventID: UUID?
    var showClearAllConfirmation = false
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

        // Latest non-system event is "live", never filtered
        let latestID = allEvents.first(where: {
            !($0.promptText?.isTaskNotification ?? false)
        })?.id

        // Build set of sequenceIDs that have at least one file change
        var changedSequences = Set<String>()
        for event in allEvents {
            guard let seqID = event.sequenceID else { continue }
            if !(database.fileChangesCache[event.id] ?? []).isEmpty {
                changedSequences.insert(seqID)
            }
        }

        // The latest event's sequence is "live" — show all prompts in it
        let liveSequenceID = allEvents.first(where: {
            !($0.promptText?.isTaskNotification ?? false)
        })?.sequenceID

        return allEvents.filter { event in
            // Always skip task-notifications when filtering
            if event.promptText?.isTaskNotification ?? false { return false }
            return event.id == latestID
                || !(database.fileChangesCache[event.id] ?? []).isEmpty
                || (event.sequenceID != nil && changedSequences.contains(event.sequenceID!))
                || (event.sequenceID != nil && event.sequenceID == liveSequenceID)
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
                guard !state.collapsedProjects.contains(projectName) else { continue }
                for session in sessions {
                    let events = filteredEvents(for: session.id)
                    guard !events.isEmpty else { continue }
                    items.append(.session(session))
                    if state.expandedSessions.contains(session.id) {
                        let cal = Calendar.current
                        let todayStart = cal.startOfDay(for: Date())

                        // Split into recent (today) and older events
                        let recentEvents = events.filter { $0.timestamp >= todayStart }
                        let olderEvents = events.filter { $0.timestamp < todayStart }

                        let showAll = state.showAllPrompts.contains(session.id)
                        let visibleEvents: [PromptEvent]
                        if recentEvents.isEmpty {
                            // All old — show the latest event at minimum
                            visibleEvents = showAll ? events : Array(events.prefix(1))
                        } else {
                            visibleEvents = showAll ? events : recentEvents
                        }

                        // Collapse no-change prompts between change prompts
                        let displayItems = SidebarFilter.collapseNoChangePrompts(
                            visibleEvents,
                            fileChangesCache: database.fileChangesCache,
                            sessionID: session.id
                        )

                        for displayItem in displayItems {
                            switch displayItem {
                            case .event(let event):
                                items.append(.event(event))
                            case .collapsed(let hiddenEvents, let key):
                                if state.expandedCollapseGroups.contains(key) {
                                    // Show a "collapse" pill before the expanded events
                                    items.append(.collapsed(count: hiddenEvents.count, groupKey: key))
                                    for event in hiddenEvents {
                                        items.append(.event(event))
                                    }
                                } else {
                                    items.append(.collapsed(count: hiddenEvents.count, groupKey: key))
                                }
                            }
                        }

                        // "Show older" button
                        if !showAll && !olderEvents.isEmpty && !recentEvents.isEmpty {
                            let olderCount = olderEvents.count
                            items.append(.showOlder(count: olderCount, sessionID: session.id))
                        }
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
            .alert(
                "Rename Session",
                isPresented: Binding(
                    get: { state.renamingSessionID != nil },
                    set: { if !$0 { state.renamingSessionID = nil } }
                )
            ) {
                TextField("Session name", text: $state.renameText)
                Button("Rename") {
                    guard let sessionID = state.renamingSessionID else { return }
                    let name = state.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? database.updateSessionName(name.isEmpty ? nil : name, sessionID: sessionID)
                    state.renamingSessionID = nil
                }
                Button("Cancel", role: .cancel) {
                    state.renamingSessionID = nil
                }
            } message: {
                Text("Enter a custom name for this session, or leave empty to use the first prompt.")
            }
            .alert(
                "Delete Session",
                isPresented: Binding(
                    get: { state.deletingSessionID != nil },
                    set: { if !$0 { state.deletingSessionID = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    guard let sessionID = state.deletingSessionID else { return }
                    try? database.deleteSession(id: sessionID)
                    state.deletingSessionID = nil
                }
                Button("Cancel", role: .cancel) {
                    state.deletingSessionID = nil
                }
            } message: {
                Text("This will permanently delete the session and all its prompts.")
            }
            .alert(
                "Delete Prompt",
                isPresented: Binding(
                    get: { state.deletingEventID != nil },
                    set: { if !$0 { state.deletingEventID = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    guard let eventID = state.deletingEventID else { return }
                    try? database.deletePromptEvent(id: eventID)
                    state.deletingEventID = nil
                }
                Button("Cancel", role: .cancel) {
                    state.deletingEventID = nil
                }
            } message: {
                Text("This will permanently delete this prompt and its file changes.")
            }
            .alert("Clear All Data", isPresented: $state.showClearAllConfirmation) {
                Button("Clear All", role: .destructive) {
                    try? database.deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all sessions, prompts, and file changes.")
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        state.hideEmptyEvents.toggle()
                    } label: {
                        Image(systemName: state.hideEmptyEvents ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help(state.hideEmptyEvents ? "Showing only prompts with file changes" : "Showing all prompts")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        if state.confirmBeforeDelete {
                            state.showClearAllConfirmation = true
                        } else {
                            try? database.deleteAllData()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear all data")
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
                eventRow(event, position: item.sequencePosition)
                    .padding(.vertical, 2)
                    .padding(.leading, 20)
                    .tag(item.id)
            }
        case .daySeparator:
            Text(item.projectName ?? "")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.quaternary)
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, maxHeight: 2, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .tag(item.id)
        case .showOlder:
            if let sessionID = item.sessionID {
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        _ = state.showAllPrompts.insert(sessionID)
                    }
                } label: {
                    Text("Show \(item.olderCount) older prompt\(item.olderCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.vertical, 4)
                .tag(item.id)
            }
        case .collapsed:
            if let key = item.groupKey {
                let isExpanded = state.expandedCollapseGroups.contains(key)
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        if isExpanded {
                            state.expandedCollapseGroups.remove(key)
                        } else {
                            state.expandedCollapseGroups.insert(key)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("\(item.collapsedCount) prompt\(item.collapsedCount == 1 ? "" : "s") without changes")
                    }
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.vertical, 1)
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
        let collapsed = state.collapsedProjects.contains(name)
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.quaternary)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
                .animation(.smooth(duration: 0.2), value: collapsed)
                .frame(width: 12)
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.25)) {
                if collapsed {
                    state.collapsedProjects.remove(name)
                } else {
                    state.collapsedProjects.insert(name)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let events = filteredEvents(for: session.id)
        let eventCount = events.count
        let firstPrompt = events.last?.promptText  // oldest — stable session identity
        let displayTitle = session.customName ?? firstPrompt?.displayPromptText ?? "(no prompt)"
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
                    Text(displayTitle)
                        .font(.callout)
                        .lineLimit(1)
                }
                Text("\(eventCount) prompt\(eventCount == 1 ? "" : "s") · \(session.startedAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button("Rename…") {
                state.renameText = session.customName ?? ""
                state.renamingSessionID = session.id
            }
            if session.customName != nil {
                Button("Clear Name") {
                    try? database.updateSessionName(nil, sessionID: session.id)
                }
            }
            Divider()
            Button("Delete Session", role: .destructive) {
                if state.confirmBeforeDelete {
                    state.deletingSessionID = session.id
                } else {
                    try? database.deleteSession(id: session.id)
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: PromptEvent, position: SidebarItem.SequencePosition) -> some View {
        let fileCount = database.fileChangesCache[event.id]?.count ?? 0
        let hasChanges = fileCount > 0
        let isEmpty = event.isEmptyPrompt
        let showState = isLatestEvent(event)
        let sState = showState ? database.sessionState(for: event.sessionID) : .idle
        VStack(alignment: .leading, spacing: 2) {
            Text(event.promptText?.displayPromptText ?? "(no prompt)")
                .lineLimit(hasChanges ? 2 : 1)
                .font(hasChanges ? .callout.weight(.medium) : .caption)
                .foregroundStyle(isEmpty ? .quaternary : (hasChanges ? .primary : .tertiary))
                .italic(isEmpty)
            HStack(spacing: 6) {
                SessionStateIndicator(state: sState)
                Text(event.timestamp, style: .time)
                if fileCount > 0 {
                    Label("\(fileCount)", systemImage: "doc")
                }
            }
            .font(.caption2)
            .foregroundStyle(hasChanges ? .secondary : .quaternary)
        }
        .contextMenu {
            Button("Delete Prompt", role: .destructive) {
                if state.confirmBeforeDelete {
                    state.deletingEventID = event.id
                } else {
                    try? database.deletePromptEvent(id: event.id)
                }
            }
        }
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
