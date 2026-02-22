import Foundation

@MainActor @Observable
final class HookHealthChecker {
    static let shared = HookHealthChecker()

    var cliInstalled = false
    var hooksConfigured = false
    var socketActive = false

    var isFullyConfigured: Bool {
        cliInstalled && hooksConfigured && socketActive
    }

    private init() {
        refresh()
    }

    func refresh() {
        cliInstalled = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/nocrumbs")

        hooksConfigured = checkHooksConfigured()

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let sockPath = appSupport?.appendingPathComponent("NoCrumbs/nocrumbs.sock").path ?? ""
        socketActive = FileManager.default.fileExists(atPath: sockPath)
    }

    private func checkHooksConfigured() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hooks = json["hooks"] as? [String: Any]
        else {
            return false
        }

        // Check both PreToolUse and PostToolUse (common hook points)
        for key in hooks.keys {
            guard let hookArray = hooks[key] as? [[String: Any]] else { continue }
            for hook in hookArray {
                if let command = hook["command"] as? String, command.contains("nocrumbs") {
                    return true
                }
            }
        }
        return false
    }
}
