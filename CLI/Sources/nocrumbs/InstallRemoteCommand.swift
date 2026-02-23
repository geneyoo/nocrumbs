import Foundation

enum InstallRemoteCommand {
    static func run() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let user = ProcessInfo.processInfo.environment["USER"] ?? "unknown"

        // Create socket directory (Linux convention)
        #if os(Linux)
        let socketDir = "/tmp/nocrumbs-\(user)"
        try FileManager.default.createDirectory(atPath: socketDir, withIntermediateDirectories: true)
        // Restrict to owner only
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: socketDir)
        #endif

        // Install Claude Code hooks (same as regular install)
        let settingsPath = home.appendingPathComponent(".claude/settings.json").path

        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath),
            let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = existing
        }

        let hookEntry: [[String: Any]] = [
            [
                "hooks": [
                    [
                        "type": "command",
                        "command": "nocrumbs event",
                    ]
                ]
            ]
        ]

        let hooks: [String: Any] = [
            "UserPromptSubmit": hookEntry,
            "PostToolUse": hookEntry,
            "Stop": hookEntry,
            "SessionStart": hookEntry,
            "SessionEnd": hookEntry,
        ]

        if var existingHooks = settings["hooks"] as? [String: Any] {
            for (key, value) in hooks {
                existingHooks[key] = value
            }
            settings["hooks"] = existingHooks
        } else {
            settings["hooks"] = hooks
        }

        let dir = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath))

        print("✅ Hooks installed to \(settingsPath) (remote mode)")
        print("")
        print("To connect to your Mac, choose one of:")
        print("")
        print("  Option 1: SSH socket forwarding (recommended)")
        print("  Add to ~/.ssh/config on your Mac:")
        print("")
        #if os(Linux)
        print("    Host <your-remote-host>")
        print("      RemoteForward /tmp/nocrumbs-\(user)/nocrumbs.sock ~/Library/Application\\ Support/NoCrumbs/nocrumbs.sock")
        #else
        print("    Host <your-remote-host>")
        print("      RemoteForward /tmp/nocrumbs-<user>/nocrumbs.sock ~/Library/Application\\ Support/NoCrumbs/nocrumbs.sock")
        #endif
        print("")
        print("  Option 2: Eternal Terminal / Mosh (TCP tunnel)")
        print("  1. Enable 'Accept remote connections' in NoCrumbs Settings")
        print("  2. On Mac: socat TCP-LISTEN:19876,reuseaddr,fork UNIX-CONNECT:$HOME/Library/Application\\ Support/NoCrumbs/nocrumbs.sock")
        print("     Or use the built-in TCP listener (Settings → Remote)")
        print("  3. Connect: et -r 19876:19876 <remote-host>")
        print("  4. On remote: export NOCRUMBS_HOST=localhost")
        print("")
        print("  Option 3: Direct TCP (if network allows)")
        print("  On remote: export NOCRUMBS_HOST=<mac-ip> NOCRUMBS_PORT=19876")
    }
}
