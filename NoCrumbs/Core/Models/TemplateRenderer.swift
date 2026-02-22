import Foundation

struct TemplateContext {
    let promptCount: Int
    let totalFiles: Int
    let sessionID: String
    let prompts: [(text: String, fileCount: Int)]
}

enum TemplateRenderer {
    static func render(_ template: String, context: TemplateContext) -> String {
        var result = template

        let summaryLine =
            "🍞 \(context.promptCount) prompt\(context.promptCount == 1 ? "" : "s") · "
            + "\(context.totalFiles) file\(context.totalFiles == 1 ? "" : "s") · "
            + "\(context.sessionID.prefix(8))"

        // Replace simple placeholders
        result = result.replacingOccurrences(of: "{{prompt_count}}", with: "\(context.promptCount)")
        result = result.replacingOccurrences(of: "{{total_files}}", with: "\(context.totalFiles)")
        result = result.replacingOccurrences(of: "{{session_id}}", with: String(context.sessionID.prefix(8)))
        result = result.replacingOccurrences(of: "{{summary_line}}", with: summaryLine)

        // Handle {{#prompts}}...{{/prompts}} loop block
        if let loopRange = findLoopBlock(in: result, tag: "prompts") {
            let loopBody = String(result[loopRange.bodyRange])
            var expanded = ""
            for (i, prompt) in context.prompts.enumerated() {
                let truncated = prompt.text.count > 72 ? String(prompt.text.prefix(69)) + "..." : prompt.text
                var line = loopBody
                line = line.replacingOccurrences(of: "{{index}}", with: "\(i + 1)")
                line = line.replacingOccurrences(of: "{{text}}", with: truncated)
                line = line.replacingOccurrences(of: "{{file_count}}", with: "\(prompt.fileCount)")
                expanded += line
            }
            result = result.replacingCharacters(in: loopRange.fullRange, with: expanded)
        }

        return result
    }

    private struct LoopBlock {
        let fullRange: Range<String.Index>
        let bodyRange: Range<String.Index>
    }

    private static func findLoopBlock(in string: String, tag: String) -> LoopBlock? {
        let openTag = "{{#\(tag)}}"
        let closeTag = "{{/\(tag)}}"

        guard let openRange = string.range(of: openTag),
            let closeRange = string.range(of: closeTag, range: openRange.upperBound..<string.endIndex)
        else { return nil }

        return LoopBlock(
            fullRange: openRange.lowerBound..<closeRange.upperBound,
            bodyRange: openRange.upperBound..<closeRange.lowerBound
        )
    }
}
