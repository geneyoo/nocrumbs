import Foundation

enum InstallGitHooksCommand {
    static func run() throws {
        // Find .git directory (walk up from cwd)
        var dir = FileManager.default.currentDirectoryPath
        var gitDir: String?
        while true {
            let candidate = (dir as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: candidate) {
                gitDir = candidate
                break
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }

        guard let gitDir else {
            fputs("Not a git repository (no .git found)\n", stderr)
            exit(1)
        }

        let hooksDir = (gitDir as NSString).appendingPathComponent("hooks")
        try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        let hookPath = (hooksDir as NSString).appendingPathComponent("prepare-commit-msg")

        let hookScript = """
            #!/bin/bash
            nocrumbs annotate-commit "$1" "$2"
            """

        try hookScript.write(toFile: hookPath, atomically: true, encoding: .utf8)

        // chmod +x
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: hookPath)

        print("✅ Git hook installed: \(hookPath)")
        print("   Commits will be annotated with NoCrumbs prompt context")
    }
}

enum InstallCommand {
    static func run() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsPath = home.appendingPathComponent(".claude/settings.json").path

        var settings: [String: Any] = [:]

        // Load existing settings if present
        if let data = FileManager.default.contents(atPath: settingsPath),
            let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = existing
        }

        // Build hook config — all events pipe through `nocrumbs event`
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
        print("   UserPromptSubmit → nocrumbs event")
        print("   PostToolUse      → nocrumbs event")
        print("   Stop             → nocrumbs event")
        print("   SessionStart     → nocrumbs event")
        print("   SessionEnd       → nocrumbs event")
    }
}
