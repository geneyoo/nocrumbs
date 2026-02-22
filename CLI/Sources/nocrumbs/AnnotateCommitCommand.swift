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
        let deepLinkEnabled = json["deep_link_enabled"] as? Bool ?? true
        let showPromptList = json["show_prompt_list"] as? Bool ?? true
        let showFileCountPerPrompt = json["show_file_count_per_prompt"] as? Bool ?? true
        let showSessionID = json["show_session_id"] as? Bool ?? true

        // Build prompt data for rendering
        let promptData: [(text: String, fileCount: Int)] = prompts.compactMap { p in
            guard let text = p["text"] as? String else { return nil }
            let fc = p["file_count"] as? Int ?? 0
            return (text: text, fileCount: fc)
        }

        let deepLink =
            deepLinkEnabled && !sessionID.isEmpty
            ? "nocrumbs://session/\(sessionID.prefix(8))" : ""

        let flags = ContentFlags(
            showPromptList: showPromptList,
            showFileCountPerPrompt: showFileCountPerPrompt,
            showSessionID: showSessionID
        )

        // Render using custom template or fall back to built-in format
        let annotation: String
        if let templateBody {
            let ctx = RenderContext(
                promptCount: prompts.count,
                totalFiles: totalFiles,
                sessionID: sessionID,
                prompts: promptData,
                deepLink: deepLink
            )
            annotation = "\n" + renderTemplate(templateBody, context: ctx, flags: flags) + "\n"
        } else {
            annotation = buildDefaultAnnotation(
                prompts: promptData,
                totalFiles: totalFiles,
                sessionID: sessionID,
                deepLink: deepLink,
                flags: flags
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

    private struct ContentFlags {
        let showPromptList: Bool
        let showFileCountPerPrompt: Bool
        let showSessionID: Bool
    }

    private struct RenderContext {
        let promptCount: Int
        let totalFiles: Int
        let sessionID: String
        let prompts: [(text: String, fileCount: Int)]
        let deepLink: String
    }

    private static func renderTemplate(
        _ template: String, context ctx: RenderContext, flags: ContentFlags
    ) -> String {
        let promptCount = ctx.promptCount
        let totalFiles = ctx.totalFiles
        let sessionID = ctx.sessionID
        let prompts = ctx.prompts
        let deepLink = ctx.deepLink
        var result = template

        let sessionSuffix = flags.showSessionID ? " · \(sessionID.prefix(8))" : ""
        let summaryLine =
            "🍞 \(promptCount) prompt\(promptCount == 1 ? "" : "s") · "
            + "\(totalFiles) file\(totalFiles == 1 ? "" : "s")"
            + sessionSuffix

        result = result.replacingOccurrences(of: "{{prompt_count}}", with: "\(promptCount)")
        result = result.replacingOccurrences(of: "{{total_files}}", with: "\(totalFiles)")
        result = result.replacingOccurrences(
            of: "{{session_id}}", with: flags.showSessionID ? String(sessionID.prefix(8)) : "")
        result = result.replacingOccurrences(of: "{{summary_line}}", with: summaryLine)
        result = result.replacingOccurrences(of: "{{deep_link}}", with: deepLink)

        // Handle {{#prompts}}...{{/prompts}} loop
        let openTag = "{{#prompts}}"
        let closeTag = "{{/prompts}}"
        if let openRange = result.range(of: openTag),
            let closeRange = result.range(of: closeTag, range: openRange.upperBound..<result.endIndex)
        {
            var expanded = ""
            if flags.showPromptList {
                let loopBody = String(result[openRange.upperBound..<closeRange.lowerBound])
                for (i, prompt) in prompts.enumerated() {
                    let truncated =
                        prompt.text.count > 72 ? String(prompt.text.prefix(69)) + "..." : prompt.text
                    var line = loopBody
                    line = line.replacingOccurrences(of: "{{index}}", with: "\(i + 1)")
                    line = line.replacingOccurrences(of: "{{text}}", with: truncated)
                    line = line.replacingOccurrences(
                        of: "{{file_count}}",
                        with: flags.showFileCountPerPrompt ? "\(prompt.fileCount)" : "")
                    expanded += line
                }
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
        sessionID: String,
        deepLink: String,
        flags: ContentFlags
    ) -> String {
        // Filter noise: skip prompts with 0 files and short meta-commands
        let meaningful = prompts.filter { !isNoisePrompt($0) }
        let displayPrompts = meaningful.isEmpty ? prompts : meaningful

        let deepLinkSuffix = deepLink.isEmpty ? "" : "\n\(deepLink)"
        let sessionSuffix = flags.showSessionID ? " · \(sessionID.prefix(8))" : ""

        // Single prompt — collapsed one-liner
        if displayPrompts.count == 1, let prompt = displayPrompts.first {
            let truncated = prompt.text.count > 72 ? String(prompt.text.prefix(69)) + "..." : prompt.text
            let files = "\(totalFiles) file\(totalFiles == 1 ? "" : "s")"
            return "\n---\n🍞 \(truncated) · \(files)\(sessionSuffix)\(deepLinkSuffix)\n"
        }

        // Multi-prompt — expanded list
        var annotation = "\n---\n"
        annotation += "🍞 \(prompts.count) prompt\(prompts.count == 1 ? "" : "s") · "
        annotation += "\(totalFiles) file\(totalFiles == 1 ? "" : "s")\(sessionSuffix)\n"

        if flags.showPromptList {
            annotation += "\n"
            let maxDisplay = 10
            for (i, prompt) in displayPrompts.prefix(maxDisplay).enumerated() {
                let truncated =
                    prompt.text.count > 72 ? String(prompt.text.prefix(69)) + "..." : prompt.text
                if flags.showFileCountPerPrompt {
                    annotation +=
                        "\(i + 1). \(truncated) (\(prompt.fileCount) file\(prompt.fileCount == 1 ? "" : "s"))\n"
                } else {
                    annotation += "\(i + 1). \(truncated)\n"
                }
            }

            if displayPrompts.count > maxDisplay {
                annotation += "  + \(displayPrompts.count - maxDisplay) more\n"
            }
        }

        if !deepLink.isEmpty {
            annotation += "\n\(deepLink)\n"
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
