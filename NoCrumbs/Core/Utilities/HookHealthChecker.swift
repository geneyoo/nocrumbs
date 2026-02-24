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
        cliInstalled = findCLI()
        hooksConfigured = checkHooksConfigured()

        socketActive = probeSocket()
    }

    private func findCLI() -> Bool {
        // Check common Homebrew paths + app bundle
        let paths = [
            "/opt/homebrew/bin/nocrumbs",       // Apple Silicon Homebrew
            "/usr/local/bin/nocrumbs",           // Intel Homebrew
            Bundle.main.bundlePath + "/Contents/Resources/nocrumbs",
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }
        // Fallback: check PATH via which
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["nocrumbs"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Probes the Unix domain socket with a real POSIX connect.
    /// File existence alone can't detect ECONNREFUSED (dead listener).
    private func probeSocket() -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let sockPath = appSupport?.appendingPathComponent("NoCrumbs/nocrumbs.sock").path ?? ""

        guard FileManager.default.fileExists(atPath: sockPath) else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = sockPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for i in 0..<pathBytes.count { dest[i] = pathBytes[i] }
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
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

        // Claude Code hooks use a nested structure:
        // hooks.<EventName>[].hooks[].command
        for key in hooks.keys {
            guard let hookArray = hooks[key] as? [[String: Any]] else { continue }
            for entry in hookArray {
                // Check nested hooks array (current format)
                if let innerHooks = entry["hooks"] as? [[String: Any]] {
                    for inner in innerHooks {
                        if let command = inner["command"] as? String, command.contains("nocrumbs") {
                            return true
                        }
                    }
                }
                // Also check flat command (legacy format)
                if let command = entry["command"] as? String, command.contains("nocrumbs") {
                    return true
                }
            }
        }
        return false
    }
}
