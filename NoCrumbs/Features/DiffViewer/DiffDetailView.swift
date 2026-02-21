import SwiftUI

struct DiffDetailView: View {
    let event: PromptEvent
    @Environment(Database.self) private var database
    @State private var viewModel = DiffViewModel()
    @State private var scrollSync = DiffScrollSync()

    private var fileChanges: [FileChange] {
        database.fileChangesCache[event.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.fileDiffs.isEmpty {
                emptyView
            } else {
                diffContent
            }
        }
        .frame(minWidth: 600)
        .onChange(of: event.id) { _, _ in reload() }
        .onChange(of: fileChanges) { _, _ in reload() }
        .onAppear { reload() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.promptText ?? "(no prompt text)")
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(event.timestamp, style: .time)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("\(fileChanges.count) file\(fileChanges.count == 1 ? "" : "s")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        HSplitView {
            fileList
                .frame(minWidth: 140, idealWidth: 180, maxWidth: 240)
            diffPanes
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: Binding(
            get: { viewModel.selectedFileID ?? viewModel.fileDiffs.first?.id },
            set: { if let id = $0 { viewModel.selectFile(id) } }
        )) {
            ForEach(viewModel.fileDiffs) { file in
                HStack(spacing: 6) {
                    statusIcon(for: file.status)
                    Text(displayName(for: file))
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tag(file.id)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Diff Panes

    private var diffPanes: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Before")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                Divider().frame(height: 20)
                Text("After")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            Divider()

            if let file = viewModel.selectedFile {
                diffPanesContent(for: file)
            }
        }
    }

    @ViewBuilder
    private func diffPanesContent(for file: FileDiff) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                leftPane(for: file)
                    .frame(width: (geo.size.width - 1) / 2)
                Divider()
                rightPane(for: file)
                    .frame(width: (geo.size.width - 1) / 2)
            }
        }
    }

    @ViewBuilder
    private func leftPane(for file: FileDiff) -> some View {
        switch file.status {
        case .added:
            placeholderPane("File did not exist")
        case .deleted, .modified:
            DiffTextView(
                lines: viewModel.linePairs.map(\.left),
                side: .left,
                scrollSync: file.status == .modified ? scrollSync : nil
            )
        }
    }

    @ViewBuilder
    private func rightPane(for file: FileDiff) -> some View {
        switch file.status {
        case .deleted:
            placeholderPane("File was deleted")
        case .added, .modified:
            DiffTextView(
                lines: viewModel.linePairs.map(\.right),
                side: .right,
                scrollSync: file.status == .modified ? scrollSync : nil
            )
        }
    }

    private func placeholderPane(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading diff…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        Text("No diffs available")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func reload() {
        scrollSync.detach()
        scrollSync = DiffScrollSync()
        viewModel.load(event: event, fileChanges: fileChanges)
    }

    private func statusIcon(for status: FileDiff.FileStatus) -> some View {
        switch status {
        case .added:
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .modified:
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    private func displayName(for file: FileDiff) -> String {
        let path = file.displayPath
        if path.hasPrefix(event.projectPath) {
            return String(path.dropFirst(event.projectPath.count + 1))
        }
        return (path as NSString).lastPathComponent
    }
}
