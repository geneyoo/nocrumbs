import SwiftUI

struct SessionSummaryView: View {
    let session: Session
    @Environment(Database.self) private var database
    @State private var viewModel = SessionSummaryViewModel()

    private var events: [PromptEvent] {
        database.eventsForSession(id: session.id)
    }

    private var totalFileChanges: Int {
        events.reduce(0) { $0 + (database.fileChangesCache[$1.id]?.count ?? 0) }
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

                Text(formattedDuration)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.green)
                    Text("-\(dels)")
                        .foregroundStyle(.red)
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
                ForEach(events.reversed()) { event in
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
                    ForEach(stat.fileStats.sorted(by: { $0.totalChanges > $1.totalChanges }), id: \.filePath) { file in
                        fileStatRow(file)
                    }
                }
                .padding(.leading, 24)
                .padding(.vertical, 4)
            } else if !fileChanges.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(fileChanges) { change in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(relativePath(change.filePath))
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.vertical, 4)
            }
        } label: {
            HStack(spacing: 8) {
                // Timestamp
                Text(event.timestamp, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                // Prompt text
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.promptText ?? "(no prompt)")
                        .lineLimit(2)
                        .font(.callout)

                    HStack(spacing: 8) {
                        let count = stat?.totalFiles ?? fileChanges.count
                        if count > 0 {
                            Text("\(count) file\(count == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }

                        if let stat, (stat.totalAdditions > 0 || stat.totalDeletions > 0) {
                            Text("+\(stat.totalAdditions)")
                                .foregroundStyle(.green)
                            Text("-\(stat.totalDeletions)")
                                .foregroundStyle(.red)
                        }

                        if hasError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
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
        HStack(spacing: 6) {
            FileStatusBadge(status: stat.status)
                .frame(width: 18)

            Text(stat.filePath)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if stat.additions > 0 {
                Text("+\(stat.additions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.green)
            }

            if stat.deletions > 0 {
                Text("-\(stat.deletions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.red)
            }

            DiffStatSquares(additions: stat.additions, deletions: stat.deletions)
        }
        .padding(.vertical, 1)
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
                    .fill(.green.opacity(0.7))
                    .frame(width: addWidth)

                RoundedRectangle(cornerRadius: 2)
                    .fill(.red.opacity(0.7))
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
                    .fill(i < greenCount ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - File Status Badge (A/M/D)

struct FileStatusBadge: View {
    let status: FileDiff.FileStatus

    var body: some View {
        Text(letter)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
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
        case .added: .green
        case .modified: .orange
        case .deleted: .red
        }
    }
}
