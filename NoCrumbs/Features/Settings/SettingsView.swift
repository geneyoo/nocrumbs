import SwiftUI

struct SettingsView: View {
    @AppStorage("hideEmptyEvents") private var hideEmptyEvents = true
    @AppStorage("annotationEnabled") private var annotationEnabled = true
    @AppStorage("deepLinkInAnnotation") private var deepLinkInAnnotation = true
    @AppStorage("showPromptList") private var showPromptList = true
    @AppStorage("showFileCountPerPrompt") private var showFileCountPerPrompt = true
    @AppStorage("showSessionID") private var showSessionID = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("retentionDays") private var retentionDays = 7
    @AppStorage("remoteTCPPort") private var remoteTCPPort = 0
    @Environment(ThemeManager.self) private var themeManager
    @State private var healthChecker = HookHealthChecker.shared
    @State private var showClearAllConfirmation = false
    private var database: Database { Database.shared }

    private var selectedThemeName: Binding<String> {
        Binding(
            get: { themeManager.currentTheme?.name ?? "" },
            set: { themeManager.selectTheme(named: $0) }
        )
    }

    private var includeAllDetails: Binding<Bool> {
        Binding(
            get: { showPromptList && showFileCountPerPrompt && showSessionID && deepLinkInAnnotation },
            set: { newValue in
                showPromptList = newValue
                showFileCountPerPrompt = newValue
                showSessionID = newValue
                deepLinkInAnnotation = newValue
            }
        )
    }

    var body: some View {
        NavigationStack {
        Form {
            Section("Hook Status") {
                LabeledContent("CLI installed") {
                    Image(systemName: healthChecker.cliInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(healthChecker.cliInstalled ? .green : .red)
                }
                LabeledContent("Hooks configured") {
                    Image(systemName: healthChecker.hooksConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(healthChecker.hooksConfigured ? .green : .red)
                }
                LabeledContent("Socket active") {
                    Image(systemName: healthChecker.socketActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(healthChecker.socketActive ? .green : .red)
                }
            }
            .onAppear { healthChecker.refresh() }

            Section("Sidebar") {
                Toggle("Hide prompts with no file changes", isOn: $hideEmptyEvents)
                    .help("Only show prompts that produced file changes (the most recent prompt in each session is always shown)")
            }

            Section("Data") {
                Toggle("Confirm before deleting", isOn: $confirmBeforeDelete)
                    .help("Show a confirmation dialog before deleting sessions or prompts")

                Picker("Auto-delete after", selection: $retentionDays) {
                    Text("1 day").tag(1)
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("Never").tag(0)
                }
                .help("Automatically delete sessions older than this on app launch")

                Button("Clear All Data", role: .destructive) {
                    if confirmBeforeDelete {
                        showClearAllConfirmation = true
                    } else {
                        try? database.deleteAllData()
                    }
                }
                .alert("Clear All Data", isPresented: $showClearAllConfirmation) {
                    Button("Clear All", role: .destructive) {
                        try? database.deleteAllData()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all sessions, prompts, and file changes.")
                }
            }

            Section("General") {
                Toggle("Annotate commit messages with prompt history", isOn: $annotationEnabled)
                    .help(
                        "Appends a summary of recent prompts to git commit messages via prepare-commit-msg hook"
                    )

                if annotationEnabled {
                    Toggle("Include all details", isOn: includeAllDetails)
                        .help("Toggle all annotation content at once")

                    Toggle("Prompt list", isOn: $showPromptList)
                        .help("Show numbered prompt lines in multi-prompt annotations")
                        .padding(.leading, 16)

                    Toggle("File count per prompt", isOn: $showFileCountPerPrompt)
                        .help("Show file count suffix on prompt lines")
                        .padding(.leading, 16)

                    Toggle("Session ID", isOn: $showSessionID)
                        .help("Show 8-char session prefix in summary line")
                        .padding(.leading, 16)

                    Toggle("Deep link", isOn: $deepLinkInAnnotation)
                        .help("Appends a nocrumbs:// URL to annotations so you can click back to the session")
                        .padding(.leading, 16)

                    if database.commitTemplates.isEmpty {
                        Text("No custom templates. Use `nocrumbs template add` to create one.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(database.commitTemplates) { template in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(template.name).font(.body)
                                    Text(String(template.body.prefix(80)))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if template.isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { try? database.setActiveTemplate(name: template.name) }
                            .contextMenu {
                                Button("Delete") { try? database.deleteCommitTemplate(name: template.name) }
                            }
                        }
                    }
                }
            }

            Section("Remote") {
                Toggle(
                    "Accept remote connections",
                    isOn: Binding(
                        get: { remoteTCPPort > 0 },
                        set: { enabled in
                            remoteTCPPort = enabled ? Int(TransportEndpoint.defaultTCPPort) : 0
                            Task {
                                let server = await AppDelegate.shared?.socketServer
                                if enabled {
                                    try? await server?.startTCPListener(port: TransportEndpoint.defaultTCPPort)
                                } else {
                                    await server?.stopTCPListener()
                                }
                            }
                        }
                    )
                )
                .help("Listen on localhost TCP port for connections from remote dev servers via SSH/ET tunnel")

                if remoteTCPPort > 0 {
                    LabeledContent("Port") {
                        Text("\(remoteTCPPort)")
                            .monospacedDigit()
                    }
                    Text("Remote CLI connects via SSH tunnel or `export NOCRUMBS_HOST=localhost`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink("Database") {
                    DatabaseDebugView(database: database)
                }
            }

            Section("Diff Theme") {
                Picker("Theme", selection: selectedThemeName) {
                    ForEach(themeManager.availableThemes, id: \.name) { theme in
                        HStack(spacing: 6) {
                            ThemeSwatch(theme: theme)
                            Text(theme.name)
                        }
                        .tag(theme.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        }
        .frame(width: 450)
        .fixedSize()
    }
}

/// Inline color swatch showing background, added, and removed colors.
private struct ThemeSwatch: View {
    let theme: DiffTheme

    var body: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: theme.editorBgColor))
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color(nsColor: NSColor(hex: theme.addedLine)))
                .frame(width: 8, height: 8)
            Circle()
                .fill(Color(nsColor: NSColor(hex: theme.removedLine)))
                .frame(width: 8, height: 8)
        }
    }
}

private struct DatabaseDebugView: View {
    var database: Database

    var body: some View {
        Form {
            Section("Records") {
                LabeledContent("Sessions") { Text("\(database.sessions.count)") }
                LabeledContent("Prompt events") { Text("\(database.recentEvents.count)") }
                LabeledContent("File changes") {
                    Text("\(database.fileChangesCache.values.reduce(0) { $0 + $1.count })")
                }
                LabeledContent("Hook events") { Text("\(database.recentHookEvents.count)") }
                LabeledContent("Templates") { Text("\(database.commitTemplates.count)") }
            }

            Section("Activity") {
                if let oldest = database.sessions.last?.startedAt {
                    LabeledContent("Oldest session") { Text(oldest, style: .date) }
                }
                if let newest = database.sessions.first?.lastActivityAt {
                    LabeledContent("Newest activity") { Text(newest, style: .relative) }
                }
            }

            Section("Storage") {
                LabeledContent("Schema version") { Text("v\(database.schemaVersion)") }
                LabeledContent("DB size") { Text(formattedFileSize(database.fileSize)) }
                LabeledContent("DB path") {
                    HStack(spacing: 4) {
                        Text(database.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: 200, alignment: .trailing)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(database.path, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy path")
                        Button {
                            NSWorkspace.shared.selectFile(database.path, inFileViewerRootedAtPath: "")
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Database")
    }
}

private func formattedFileSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private extension NSColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
