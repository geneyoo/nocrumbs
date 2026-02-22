import SwiftUI

struct SessionSummaryView: View {
    let session: Session
    @Environment(Database.self) private var database
    @Environment(AppScale.self) private var scale
    @State private var viewModel = SessionSummaryViewModel()
    @State private var showCopiedFeedback = false

    private var events: [PromptEvent] {
        database.eventsForSession(id: session.id)
    }

    private var totalFileChanges: Int {
        var paths = Set<String>()
        for event in events {
            for change in database.fileChangesCache[event.id] ?? [] {
                paths.insert(change.filePath)
            }
        }
        return paths.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if !events.isEmpty {
                    promptTimelineSection
                }
                if !viewModel.uniqueFiles.isEmpty {
                    allFilesSection
                }
            }
            .padding()
        }
        .frame(minWidth: 500)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    Text((session.projectPath as NSString).lastPathComponent)
                        .font(.headline)
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(events.first?.promptText ?? "(no prompt)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: session.id) { _, _ in
            viewModel.invalidate()
            reload()
        }
        .onChange(of: events.count) { _, _ in
            viewModel.reloadIfNeeded(
                session: session,
                events: events,
                fileChangesCache: database.fileChangesCache
            )
        }
    }

    private func reload() {
        viewModel.load(
            session: session,
            events: events,
            fileChangesCache: database.fileChangesCache
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status + project name + duration
            HStack(alignment: .firstTextBaseline) {
                let sState = database.sessionState(for: session.id)
                SessionStateIndicator(state: sState)

                Text((session.projectPath as NSString).lastPathComponent)
                    .font(.title2.bold())

                Spacer()

                Button {
                    let md = viewModel.markdownSummary(session: session, events: events, fileChangesCache: database.fileChangesCache)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                    showCopiedFeedback = true
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy session summary as Markdown")

                Button {
                    exportMarkdown()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Export session summary as .md file")

                Text(formattedDuration)
                    .font(AppFonts.numeric(scale.level))
                    .foregroundStyle(.secondary)
            }
            .overlay(alignment: .trailing) {
                if showCopiedFeedback {
                    Text("Copied!")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showCopiedFeedback = false }
                            }
                        }
                }
            }

            // Full project path
            Text(session.projectPath)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

            // Time range
            HStack(spacing: 4) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                Text("\u{2192}")
                    .foregroundStyle(.tertiary)
                Text(session.lastActivityAt.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            // Stats row + diffstat bar
            statsRow
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        let adds = viewModel.aggregateAdditions
        let dels = viewModel.aggregateDeletions
        let fileCount = viewModel.uniqueFiles.isEmpty ? totalFileChanges : viewModel.uniqueFiles.count

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label("\(events.count) prompt\(events.count == 1 ? "" : "s")", systemImage: "text.bubble")
                Label("\(fileCount) file\(fileCount == 1 ? "" : "s")", systemImage: "doc")

                if adds > 0 || dels > 0 {
                    Text("+\(adds)")
                        .foregroundStyle(AppColors.addition)
                    Text("-\(dels)")
                        .foregroundStyle(AppColors.deletion)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(viewModel.loadingProgress.completed)/\(viewModel.loadingProgress.total)")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)

            if adds > 0 || dels > 0 {
                DiffStatBar(additions: adds, deletions: dels)
                    .frame(height: 8)
            }
        }
    }

    private func exportMarkdown() {
        let md = viewModel.markdownSummary(session: session, events: events, fileChangesCache: database.fileChangesCache)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "session-\(session.id.prefix(8)).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    private var formattedDuration: String {
        let interval = session.lastActivityAt.timeIntervalSince(session.startedAt)
        if interval < 60 {
            return "<1 min"
        } else if interval < 3600 {
            return "\(Int(interval / 60)) min"
        } else {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        }
    }

    // MARK: - Prompt Timeline

    @ViewBuilder
    private var promptTimelineSection: some View {
        GroupBox {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(events) { event in
                    promptRow(event)
                    if event.id != events.last?.id {
                        Divider().padding(.leading, 8)
                    }
                }
            }
        } label: {
            Text("Prompt Timeline")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func promptRow(_ event: PromptEvent) -> some View {
        let stat = viewModel.promptDiffStats[event.id]
        let fileChanges = database.fileChangesCache[event.id] ?? []
        let hasError = viewModel.errors[event.id] != nil

        DisclosureGroup {
            if let stat, !stat.fileStats.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(
                        stat.fileStats.sorted(by: { $0.totalChanges != $1.totalChanges ? $0.totalChanges > $1.totalChanges : $0.filePath < $1.filePath }),
                        id: \.filePath
                    ) { file in
                        fileStatRow(file)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                .padding(.vertical, 4)
            } else if !fileChanges.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(fileChanges) { change in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(relativePath(change.filePath))
                                .font(AppFonts.filePath(scale.level))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                .padding(.vertical, 4)
            }
        } label: {
            HStack(spacing: 8) {
                // Timestamp
                Text(event.timestamp, style: .time)
                    .font(AppFonts.numericSmall(scale.level))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                // Prompt text
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.promptText ?? "(no prompt)")
                        .lineLimit(2)
                        .font(.callout)

                    HStack(spacing: 8) {
                        if let hash = event.baseCommitHash {
                            let short = String(hash.prefix(7))
                            if let url = viewModel.commitURL(for: hash) {
                                Text(short)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.blue)
                                    .onTapGesture { NSWorkspace.shared.open(url) }
                                    .help("Open commit on remote")
                            } else {
                                Text(short)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        let fileCount = stat?.totalFiles ?? fileChanges.count
                        if fileCount > 0 {
                            Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }

                        if let stat, (stat.totalAdditions > 0 || stat.totalDeletions > 0) {
                            Text("+\(stat.totalAdditions)")
                                .foregroundStyle(AppColors.addition)
                            Text("-\(stat.totalDeletions)")
                                .foregroundStyle(AppColors.deletion)
                        }

                        if hasError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppColors.warning)
                                .help(viewModel.errors[event.id] ?? "Unknown error")
                        }

                        if stat == nil && !hasError && viewModel.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .font(.caption)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - All Files

    @ViewBuilder
    private var allFilesSection: some View {
        let files = viewModel.uniqueFiles

        GroupBox {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(files) { file in
                    fileStatRow(
                        DiffStat(
                            filePath: file.filePath,
                            status: file.status,
                            additions: file.totalAdditions,
                            deletions: file.totalDeletions
                        )
                    )
                }
            }
        } label: {
            Text("All Files (\(files.count))")
                .font(.headline)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func fileStatRow(_ stat: DiffStat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                FileStatusBadge(status: stat.status)
                    .frame(width: 18)

                Text(stat.filePath)
                    .font(AppFonts.filePath(scale.level))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if stat.additions > 0 {
                    Text("+\(stat.additions)")
                        .font(AppFonts.numeric(scale.level))
                        .foregroundStyle(AppColors.addition)
                }

                if stat.deletions > 0 {
                    Text("-\(stat.deletions)")
                        .font(AppFonts.numeric(scale.level))
                        .foregroundStyle(AppColors.deletion)
                }

                DiffStatSquares(additions: stat.additions, deletions: stat.deletions)
            }

            if let desc = descriptionForFile(stat.filePath) {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 1)
    }

    private func descriptionForFile(_ filePath: String) -> String? {
        for event in events {
            if let changes = database.fileChangesCache[event.id] {
                if let match = changes.first(where: { $0.filePath.hasSuffix(filePath) || filePath.hasSuffix($0.filePath) }) {
                    if let desc = match.description { return desc }
                }
            }
        }
        return nil
    }

    private func relativePath(_ path: String) -> String {
        if path.hasPrefix(session.projectPath + "/") {
            return String(path.dropFirst(session.projectPath.count + 1))
        }
        return (path as NSString).lastPathComponent
    }
}

// MARK: - DiffStat Bar (GitHub-style proportional bar)

struct DiffStatBar: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        GeometryReader { geo in
            let total = max(additions + deletions, 1)
            let addWidth = geo.size.width * CGFloat(additions) / CGFloat(total)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.additionMuted)
                    .frame(width: addWidth)

                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.deletionMuted)
                    .frame(width: geo.size.width - addWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

// MARK: - DiffStat Squares (5-square GitHub-style)

struct DiffStatSquares: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 1) {
            let total = max(additions + deletions, 1)
            let greenCount = min(5, Int(round(Double(additions) / Double(total) * 5.0)))

            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < greenCount ? AppColors.additionSquare : AppColors.deletionSquare)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - File Status Badge (A/M/D)

struct FileStatusBadge: View {
    let status: FileDiff.FileStatus
    @Environment(AppScale.self) private var scale

    var body: some View {
        Text(letter)
            .font(AppFonts.statusBadge(scale.level))
            .foregroundStyle(color)
    }

    private var letter: String {
        switch status {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        }
    }

    private var color: Color {
        switch status {
        case .added: AppColors.addition
        case .modified: AppColors.modified
        case .deleted: AppColors.deletion
        }
    }
}
