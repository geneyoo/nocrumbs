import SwiftUI
import Sparkle

@main
struct NoCrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // swiftlint:disable:this weak_delegate
    @State private var database: Database = {
        if DebugConfiguration.isMockDataEnabled {
            let db = Database(path: ":memory:")
            do {
                try db.open()
                try MockDataGenerator.populate(db)
            } catch {
                assertionFailure("Mock data failed: \(error)")
            }
            return db
        }
        return Database.shared
    }()
    @State private var themeManager = ThemeManager.shared
    @State private var appScale = AppScale.shared
    @State private var healthChecker = HookHealthChecker.shared
    @State private var deepLinkRouter = DeepLinkRouter.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
                .environment(database)
                .environment(themeManager)
                .environment(appScale)
                .environment(healthChecker)
                .environment(deepLinkRouter)
                .onAppear { themeManager.loadBundledThemes() }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { appScale.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { appScale.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { appScale.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            #if DEBUG
            CommandMenu("Debug") {
                if DebugConfiguration.isMockDataEnabled {
                    Button("Regenerate Mock Data") {
                        do {
                            try database.deleteAllData()
                            try MockDataGenerator.populate(database)
                        } catch {
                            assertionFailure("Regenerate failed: \(error)")
                        }
                    }
                }
            }
            #endif
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
            .keyboardShortcut("d", modifiers: [])
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
