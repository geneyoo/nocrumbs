import Foundation

enum AnnotateCommitCommand {
    static func run() throws {
        // $1 = commit message file path (passed by git prepare-commit-msg hook)
        guard CommandLine.arguments.count >= 3 else {
            fputs("nocrumbs annotate-commit: missing commit message file path\n", stderr)
            return
        }

        let commitMsgPath = CommandLine.arguments[2]

        // Optional $2 = commit source (message, template, merge, squash, commit)
        // Skip annotation for merge/squash commits
        if CommandLine.arguments.count >= 4 {
            let source = CommandLine.arguments[3]
            if source == "merge" || source == "squash" { return }
        }

        // Query the app for recent prompts
        let cwd = FileManager.default.currentDirectoryPath
        let request: [String: Any] = [
            "type": "query-prompts",
            "cwd": cwd,
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else { return }

        let responseData: Data
        do {
            responseData = try SocketClient.sendAndReceive(requestData)
        } catch {
            // App not running — silent fail
            return
        }

        guard !responseData.isEmpty,
            let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let prompts = json["prompts"] as? [[String: Any]],
            !prompts.isEmpty
        else {
            return
        }

        // Respect annotation toggle from app settings
        if let enabled = json["annotation_enabled"] as? Bool, !enabled { return }

        let sessionID = json["session_id"] as? String ?? ""
        let totalFiles = json["total_files"] as? Int ?? 0

        // Build annotation block
        var annotation = "\n---\n"
        annotation += "🍞 \(prompts.count) prompt\(prompts.count == 1 ? "" : "s") · \(totalFiles) file\(totalFiles == 1 ? "" : "s") · \(sessionID.prefix(8))\n"

        let maxDisplay = 3
        for (i, prompt) in prompts.prefix(maxDisplay).enumerated() {
            let text = prompt["text"] as? String ?? ""
            let fileCount = prompt["file_count"] as? Int ?? 0
            let truncated = text.count > 72 ? String(text.prefix(69)) + "..." : text
            annotation += "  \(i + 1). \(truncated) (\(fileCount) file\(fileCount == 1 ? "" : "s"))\n"
        }

        if prompts.count > maxDisplay {
            annotation += "  + \(prompts.count - maxDisplay) more\n"
        }

        // Append to commit message
        guard var commitMsg = try? String(contentsOfFile: commitMsgPath, encoding: .utf8) else { return }

        // Don't double-annotate
        guard !commitMsg.contains("🍞") else { return }

        commitMsg += annotation
        try? commitMsg.write(toFile: commitMsgPath, atomically: true, encoding: .utf8)
    }
}
