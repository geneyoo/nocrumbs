import SwiftUI

struct DiffDetailView: View {
    let event: PromptEvent
    @Environment(Database.self) private var database
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppScale.self) private var scale
    @State private var viewModel = DiffViewModel()
    @State private var scrollSync = DiffScrollSync()
    @State private var isFileListVisible = true
    @State private var fileListWidth: CGFloat = LayoutGuide.fileListWidth
    @GestureState private var dragOffset: CGFloat = 0
    @State private var fileSearchQuery = ""

    private var theme: DiffTheme? {
        themeManager.currentTheme
    }

    private var fileChanges: [FileChange] {
        database.fileChangesCache[event.id] ?? []
    }

    private var sessionFirstPrompt: String {
        let events = database.eventsForSession(id: event.sessionID)
        return events.last?.promptText ?? "(no prompt)"
    }

    private var titleText: String {
        let project = (event.projectPath as NSString).lastPathComponent
        return "\(project) — \(sessionFirstPrompt)"
    }

    var body: some View {
        VStack(spacing: LayoutGuide.spacingNone) {
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
        .navigationTitle(titleText)
        .onChange(of: event) { _, _ in
            fileSearchQuery = ""
            reload()
        }
        .onChange(of: fileChanges) { _, _ in reload() }
        .onAppear { reload() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LayoutGuide.spacingS) {
            Text(event.promptText ?? "(no prompt text)")
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: LayoutGuide.spacingL) {
                Text(event.timestamp, style: .time)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("\(fileChanges.count) file\(fileChanges.count == 1 ? "" : "s")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LayoutGuide.paddingL)
        .padding(.vertical, LayoutGuide.paddingM)
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        HStack(spacing: LayoutGuide.spacingNone) {
            if isFileListVisible {
                fileList
                    .frame(width: min(max(fileListWidth + dragOffset, 120), 400))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                fileListResizeHandle
            }
            diffPanes
        }
        .animation(.smooth(duration: 0.2), value: isFileListVisible)
    }

    private var fileListResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .overlay(Divider(), alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        fileListWidth = min(max(fileListWidth + value.translation.width, 120), 400)
                    }
            )
    }

    // MARK: - File List

    private var filteredFileDiffs: [FileDiff] {
        guard !fileSearchQuery.isEmpty else { return viewModel.fileDiffs }
        let query = fileSearchQuery.lowercased()
        return viewModel.fileDiffs.filter { displayName(for: $0).lowercased().contains(query) }
    }

    private var fileList: some View {
        VStack(spacing: LayoutGuide.spacingNone) {
            HStack(spacing: LayoutGuide.spacingS) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Search", text: $fileSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !fileSearchQuery.isEmpty {
                    Button {
                        fileSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, LayoutGuide.paddingM)
            .padding(.vertical, LayoutGuide.paddingS)

            Divider()

            List(
                selection: Binding(
                    get: { viewModel.selectedFileID ?? viewModel.fileDiffs.first?.id },
                    set: { if let id = $0 { viewModel.selectFile(id) } }
                )
            ) {
                ForEach(filteredFileDiffs) { file in
                    HStack(spacing: LayoutGuide.spacingM) {
                        statusIcon(for: file.status)
                        Text(displayName(for: file))
                            .font(AppFonts.filePath(scale.level))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(file.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Diff Panes

    private var diffPanes: some View {
        VStack(spacing: LayoutGuide.spacingNone) {
            // Column headers with file list toggle
            HStack(spacing: LayoutGuide.spacingNone) {
                Button {
                    isFileListVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.caption)
                        .foregroundStyle(isFileListVisible ? .primary : .secondary)
                }
                .buttonStyle(.borderless)
                .padding(.leading, LayoutGuide.paddingM)
                .help(isFileListVisible ? "Hide file list" : "Show file list")

                Text("Before")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LayoutGuide.paddingS)
                Divider().frame(height: LayoutGuide.spacingXXL)
                Text("After")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LayoutGuide.paddingS)
            }
            Divider()

            if let file = viewModel.selectedFile {
                diffPanesContent(for: file)
            }
        }
    }

    @ViewBuilder
    private func diffPanesContent(for file: FileDiff) -> some View {
        HStack(spacing: LayoutGuide.spacingNone) {
            leftPane(for: file)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            rightPane(for: file)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func leftPane(for file: FileDiff) -> some View {
        switch file.status {
        case .added:
            placeholderPane("File did not exist")
        case .deleted, .modified:
            if let theme {
                DiffTextView(
                    lines: viewModel.linePairs.map(\.left),
                    side: .left,
                    scrollSync: file.status == .modified ? scrollSync : nil,
                    fileExtension: file.fileExtension,
                    scale: scale.level,
                    theme: theme
                )
            }
        }
    }

    @ViewBuilder
    private func rightPane(for file: FileDiff) -> some View {
        switch file.status {
        case .deleted:
            placeholderPane("File was deleted")
        case .added, .modified:
            if let theme {
                DiffTextView(
                    lines: viewModel.linePairs.map(\.right),
                    side: .right,
                    scrollSync: file.status == .modified ? scrollSync : nil,
                    fileExtension: file.fileExtension,
                    scale: scale.level,
                    theme: theme
                )
            }
        }
    }

    @ViewBuilder
    private func placeholderPane(_ text: String) -> some View {
        let fg: Color = theme.map { Color(nsColor: $0.lineNumberFgColor) } ?? Color.secondary
        let bg: Color = theme.map { Color(nsColor: $0.editorBgColor) } ?? Color(nsColor: .controlBackgroundColor).opacity(0.5)
        Text(text)
            .font(.callout)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bg)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: LayoutGuide.spacingL) {
            ProgressView()
            Text("Loading diff…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: LayoutGuide.spacingL) {
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
                .foregroundStyle(AppColors.addition)
                .font(.caption)
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(AppColors.deletion)
                .font(.caption)
        case .modified:
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(AppColors.modified)
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
