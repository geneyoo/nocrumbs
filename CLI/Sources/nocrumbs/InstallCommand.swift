import Foundation

enum InstallCommand {
    static func run() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsPath = home.appendingPathComponent(".claude/settings.json").path

        var settings: [String: Any] = [:]

        // Load existing settings if present
        if let data = FileManager.default.contents(atPath: settingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        // Build hook config
        let hooks: [String: Any] = [
            "UserPromptSubmit": [
                [
                    "hooks": [
                        [
                            "type": "command",
                            "command": "nocrumbs capture-prompt"
                        ]
                    ]
                ]
            ],
            "PostToolUse": [
                [
                    "matcher": "Write|Edit",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "nocrumbs capture-change"
                        ]
                    ]
                ]
            ]
        ]

        // Merge hooks into existing settings
        if var existingHooks = settings["hooks"] as? [String: Any] {
            for (key, value) in hooks {
                existingHooks[key] = value
            }
            settings["hooks"] = existingHooks
        } else {
            settings["hooks"] = hooks
        }

        // Write back
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath))

        print("✅ Hooks installed to \(settingsPath)")
        print("   UserPromptSubmit → nocrumbs capture-prompt")
        print("   PostToolUse (Write|Edit) → nocrumbs capture-change")
    }
}
