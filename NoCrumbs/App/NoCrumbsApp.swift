import SwiftUI

@main
struct NoCrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var database = Database.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
                .environment(database)
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
        }

        MenuBarExtra("NoCrumbs", systemImage: "doc.text.magnifyingglass") {
            Button("Show NoCrumbs") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
