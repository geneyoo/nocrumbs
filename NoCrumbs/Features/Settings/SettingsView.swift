import SwiftUI

struct SettingsView: View {
    @AppStorage("annotationEnabled") private var annotationEnabled = true

    var body: some View {
        Form {
            Toggle("Annotate commit messages with prompt history", isOn: $annotationEnabled)
                .help("Appends a summary of recent prompts to git commit messages via prepare-commit-msg hook")
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .fixedSize()
    }
}
