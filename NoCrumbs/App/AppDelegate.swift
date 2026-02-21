import AppKit
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "App")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let socketServer = SocketServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try Database.shared.open()
            logger.info("[NC:App] Database opened")
        } catch {
            logger.error("[NC:App] Database failed: \(error.localizedDescription)")
        }

        Task {
            do {
                try await socketServer.start()
                logger.info("[NC:App] Socket server started")
            } catch {
                logger.error("[NC:App] Socket server failed: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await socketServer.stop()
        }
        Database.shared.close()
        logger.info("[NC:App] Shutdown complete")
    }
}
