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
        let templateBody = json["template"] as? String

        // Build prompt data for rendering
        let promptData: [(text: String, fileCount: Int)] = prompts.compactMap { p in
            guard let text = p["text"] as? String else { return nil }
            let fc = p["file_count"] as? Int ?? 0
            return (text: text, fileCount: fc)
        }

        // Render using custom template or fall back to built-in format
        let annotation: String
        if let templateBody {
            annotation =
                "\n"
                + renderTemplate(
                    templateBody,
                    promptCount: prompts.count,
                    totalFiles: totalFiles,
                    sessionID: sessionID,
                    prompts: promptData
                ) + "\n"
        } else {
            annotation = buildDefaultAnnotation(
                prompts: promptData,
                totalFiles: totalFiles,
                sessionID: sessionID
            )
        }

        // Append to commit message
        guard var commitMsg = try? String(contentsOfFile: commitMsgPath, encoding: .utf8) else { return }

        // Don't double-annotate
        guard !commitMsg.contains("🍞") else { return }

        commitMsg += annotation
        try? commitMsg.write(toFile: commitMsgPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Template Rendering (lightweight CLI-side copy)

    private static func renderTemplate(
        _ template: String,
        promptCount: Int,
        totalFiles: Int,
        sessionID: String,
        prompts: [(text: String, fileCount: Int)]
    ) -> String {
        var result = template

        let summaryLine =
            "🍞 \(promptCount) prompt\(promptCount == 1 ? "" : "s") · "
            + "\(totalFiles) file\(totalFiles == 1 ? "" : "s") · "
            + "\(sessionID.prefix(8))"

        result = result.replacingOccurrences(of: "{{prompt_count}}", with: "\(promptCount)")
        result = result.replacingOccurrences(of: "{{total_files}}", with: "\(totalFiles)")
        result = result.replacingOccurrences(of: "{{session_id}}", with: String(sessionID.prefix(8)))
        result = result.replacingOccurrences(of: "{{summary_line}}", with: summaryLine)

        // Handle {{#prompts}}...{{/prompts}} loop
        let openTag = "{{#prompts}}"
        let closeTag = "{{/prompts}}"
        if let openRange = result.range(of: openTag),
            let closeRange = result.range(of: closeTag, range: openRange.upperBound..<result.endIndex)
        {
            let loopBody = String(result[openRange.upperBound..<closeRange.lowerBound])
            var expanded = ""
            for (i, prompt) in prompts.enumerated() {
                let truncated = prompt.text.count > 72 ? String(prompt.text.prefix(69)) + "..." : prompt.text
                var line = loopBody
                line = line.replacingOccurrences(of: "{{index}}", with: "\(i + 1)")
                line = line.replacingOccurrences(of: "{{text}}", with: truncated)
                line = line.replacingOccurrences(of: "{{file_count}}", with: "\(prompt.fileCount)")
                expanded += line
            }
            result = result.replacingCharacters(
                in: openRange.lowerBound..<closeRange.upperBound,
                with: expanded
            )
        }

        return result
    }

    private static func buildDefaultAnnotation(
        prompts: [(text: String, fileCount: Int)],
        totalFiles: Int,
        sessionID: String
    ) -> String {
        // Filter noise: skip prompts with 0 files and short meta-commands
        let meaningful = prompts.filter { !isNoisePrompt($0) }
        let displayPrompts = meaningful.isEmpty ? prompts : meaningful

        // Single prompt — collapsed one-liner
        if displayPrompts.count == 1, let prompt = displayPrompts.first {
            let truncated = prompt.text.count > 72 ? String(prompt.text.prefix(69)) + "..." : prompt.text
            let files = "\(totalFiles) file\(totalFiles == 1 ? "" : "s")"
            return "\n---\n🍞 \(truncated) · \(files) · \(sessionID.prefix(8))\n"
        }

        // Multi-prompt — expanded list
        var annotation = "\n---\n"
        annotation += "🍞 \(prompts.count) prompt\(prompts.count == 1 ? "" : "s") · "
        annotation += "\(totalFiles) file\(totalFiles == 1 ? "" : "s") · \(sessionID.prefix(8))\n\n"

        let maxDisplay = 10
        for (i, prompt) in displayPrompts.prefix(maxDisplay).enumerated() {
            let truncated = prompt.text.count > 72 ? String(prompt.text.prefix(69)) + "..." : prompt.text
            annotation += "\(i + 1). \(truncated) (\(prompt.fileCount) file\(prompt.fileCount == 1 ? "" : "s"))\n"
        }

        if displayPrompts.count > maxDisplay {
            annotation += "  + \(displayPrompts.count - maxDisplay) more\n"
        }

        return annotation
    }

    private static let noisePatterns: Set<String> = [
        "commit", "push", "save", "done", "ok", "yes", "no", "continue",
        "go ahead", "do it", "proceed", "lets commit", "lets push",
        "commit and push", "lets just commit", "lets just commit and push",
    ]

    private static func isNoisePrompt(_ prompt: (text: String, fileCount: Int)) -> Bool {
        let text = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Short meta-commands with no file changes
        if prompt.fileCount == 0 && text.count < 20 { return true }
        // Known noise patterns
        if noisePatterns.contains(text) { return true }
        return false
    }
}
