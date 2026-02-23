import Foundation

extension String {
    /// Whether this string is a task-notification XML payload (system noise, not user intent).
    var isTaskNotification: Bool {
        hasPrefix("<task-notification>")
    }

    /// Extracts human-readable text from task-notification XML, or returns self.
    var displayPromptText: String {
        guard isTaskNotification else { return self }

        // Try to extract task-subject
        if let subject = extractXMLValue(tag: "task-subject"), !subject.isEmpty {
            let status = extractXMLValue(tag: "task-status")
            if let status, !status.isEmpty {
                return "\(subject) [\(status)]"
            }
            return subject
        }

        // Fallback: strip all XML tags
        let stripped = replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return stripped.isEmpty ? "(task notification)" : stripped
    }

    private func extractXMLValue(tag: String) -> String? {
        guard let start = range(of: "<\(tag)>"),
              let end = range(of: "</\(tag)>", range: start.upperBound..<endIndex)
        else { return nil }
        return String(self[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
