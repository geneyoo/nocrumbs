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
                title: "Install",
                done: health.cliInstalled,
                code: "brew install --cask geneyoo/tap/nocrumbs"
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

            Link(destination: URL(string: "https://nocrumbs.ai/docs/getting-started")!) {
                Text("Full setup guide")
                    .font(.caption)
            }
            .padding(.bottom, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(copied ? .green : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy to clipboard")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 8)
    }
}
