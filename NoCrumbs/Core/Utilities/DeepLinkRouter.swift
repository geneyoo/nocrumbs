import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "DeepLink")

@Observable @MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingSessionID: String?
    var pendingEventID: UUID?

    func handle(_ url: URL) {
        guard url.scheme == "nocrumbs" else { return }

        let components = url.pathComponents.filter { $0 != "/" }

        // nocrumbs://session/{id}
        // nocrumbs://session/{id}/event/{uuid}
        guard url.host == "session" || (components.first == "session") else {
            logger.warning("[NC:DeepLink] Unknown host: \(url.absoluteString)")
            return
        }

        let sessionID: String
        if let host = url.host, host == "session" {
            // nocrumbs://session/{id} — id is first path component
            guard let id = components.first else {
                logger.warning("[NC:DeepLink] Missing session ID")
                return
            }
            sessionID = id
        } else if components.first == "session", components.count >= 2 {
            sessionID = components[1]
        } else {
            logger.warning("[NC:DeepLink] Missing session ID")
            return
        }

        pendingSessionID = sessionID

        // Check for optional /event/{uuid}
        if let eventIdx = components.firstIndex(of: "event"),
            eventIdx + 1 < components.count,
            let uuid = UUID(uuidString: components[eventIdx + 1])
        {
            pendingEventID = uuid
        } else {
            pendingEventID = nil
        }

        logger.info("[NC:DeepLink] Pending navigation: session=\(sessionID) event=\(self.pendingEventID?.uuidString ?? "nil")")
    }

    func consume() -> (sessionID: String, eventID: UUID?)? {
        guard let sessionID = pendingSessionID else { return nil }
        let eventID = pendingEventID
        pendingSessionID = nil
        pendingEventID = nil
        return (sessionID, eventID)
    }
}
