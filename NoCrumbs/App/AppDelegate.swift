import AppKit
import OSLog
import ServiceManagement
import Sparkle

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "App")

final class AppDelegate: NSObject, NSApplicationDelegate {
    let socketServer = SocketServer()

    static var shared: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }
    lazy var updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "annotationEnabled": true,
            "deepLinkInAnnotation": true,
            "showPromptList": true,
            "showFileCountPerPrompt": true,
            "showSessionID": true,
            "confirmBeforeDelete": true,
            "retentionDays": 7,
        ])

        // Start Sparkle updater (only in Release builds with a real appcast)
        #if !DEBUG
        updaterController.startUpdater()
        #endif

        // Register URL scheme handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Database
        do {
            try Database.shared.open()
            logger.info("[NC:App] Database opened")
            let retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")
            if retentionDays > 0 {
                try Database.shared.evictOlderThan(days: retentionDays)
            }
            Task { await Database.shared.backfillBaseCommitHashes() }
        } catch {
            logger.error("[NC:App] Database failed: \(error.localizedDescription)")
        }

        // Socket server with retry
        Task {
            do {
                try await socketServer.start()
                logger.info("[NC:App] Socket server started")
            } catch {
                logger.warning("[NC:App] Socket start failed, retrying in 1s: \(error.localizedDescription)")
                // Legitimate hard timeout: socket bind can fail if stale file wasn't cleaned up
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                do {
                    try await socketServer.start()
                    logger.info("[NC:App] Socket server started (retry)")
                } catch {
                    logger.error("[NC:App] Socket server failed after retry: \(error.localizedDescription)")
                }
            }
        }

        // Launch at login
        do {
            try SMAppService.mainApp.register()
            logger.info("[NC:App] Registered launch at login")
        } catch {
            logger.warning("[NC:App] Launch at login failed: \(error.localizedDescription)")
        }

        // Start as accessory (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        // Track window visibility for activation policy
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeMain),
            name: NSWindow.didBecomeMainNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // Only go accessory if no other windows remain visible
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && !$0.className.contains("StatusBar") }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else { return }

        Task { @MainActor in
            DeepLinkRouter.shared.handle(url)
        }

        // Bring window to front
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // Keep running as menu bar daemon when window closes (Cmd+W)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Cmd+Q closes window and hides to menu bar instead of quitting
        // Real quit only via menu bar "Quit" button
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue == "main" }
        if hasVisibleWindow {
            NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.close() }
            NSApp.setActivationPolicy(.accessory)
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await socketServer.stop()
        }
        Database.shared.close()
        logger.info("[NC:App] Shutdown complete")
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
