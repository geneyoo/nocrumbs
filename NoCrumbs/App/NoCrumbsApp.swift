import SwiftUI

@main
struct NoCrumbsApp: App {
    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 700)

        MenuBarExtra("NoCrumbs", systemImage: "doc.text.magnifyingglass") {
            Button("Show NoCrumbs") {
                // TODO: M2 - open main window
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
