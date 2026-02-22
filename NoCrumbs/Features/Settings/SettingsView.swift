import SwiftUI

struct SettingsView: View {
    @AppStorage("annotationEnabled") private var annotationEnabled = true
    @AppStorage("deepLinkInAnnotation") private var deepLinkInAnnotation = true
    @AppStorage("showPromptList") private var showPromptList = true
    @AppStorage("showFileCountPerPrompt") private var showFileCountPerPrompt = true
    @AppStorage("showSessionID") private var showSessionID = true
    @Environment(ThemeManager.self) private var themeManager
    @State private var healthChecker = HookHealthChecker.shared
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
