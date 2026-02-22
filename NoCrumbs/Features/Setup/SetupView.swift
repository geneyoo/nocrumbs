import SwiftUI

struct SetupView: View {
    @Environment(HookHealthChecker.self) private var health

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            content
                .onChange(of: context.date) { _, _ in health.refresh() }
        }
        .onAppear { health.refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text("Get Started")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 4)

            Text("Set up NoCrumbs to capture your Claude Code prompts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            SetupStep(
                number: 1,
                title: "Install CLI",
                done: health.cliInstalled,
                code: "cd \(projectRoot) && swift build -c release --package-path CLI/ && cp .build/release/nocrumbs /usr/local/bin/"
            )

            SetupStep(
                number: 2,
                title: "Configure hooks",
                done: health.hooksConfigured,
                code: "nocrumbs install"
            )

            SetupStep(
                number: 3,
                title: "Start a session",
                done: false,
                code: nil,
                info: "Run Claude Code in any project. Prompts will appear here automatically."
            )

            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var projectRoot: String {
        // Best-effort: use the bundle path to infer project root
        Bundle.main.bundlePath
            .components(separatedBy: "/build/")
            .first ?? "~/nocrumbs"
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let done: Bool
    var code: String?
    var info: String?

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.body)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(number). \(title)")
                    .font(.callout.weight(.medium))

                if let info {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let code {
                    HStack(spacing: 0) {
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Spacer(minLength: 8)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copied = false
                            }
                        } label: {
                            Text(copied ? "Copied!" : "Copy")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 8)
    }
}
