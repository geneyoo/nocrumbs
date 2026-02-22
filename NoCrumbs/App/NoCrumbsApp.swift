import SwiftUI

@main
struct NoCrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // swiftlint:disable:this weak_delegate
    @State private var database = Database.shared
    @State private var themeManager = ThemeManager.shared
    @State private var appScale = AppScale.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
                .environment(database)
                .environment(themeManager)
                .environment(appScale)
                .onAppear { themeManager.loadBundledThemes() }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { appScale.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { appScale.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { appScale.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(themeManager)
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
