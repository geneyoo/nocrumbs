import Foundation

enum SessionMarkdownFormatter {
    struct Input {
        let session: Session
        let events: [PromptEvent]
        let promptDiffStats: [UUID: PromptDiffStat]
        let uniqueFiles: [AggregatedFileStat]
        let aggregateAdditions: Int
        let aggregateDeletions: Int
        var fileDescriptions: [String: String] = [:]  // filePath → description
    }

    static func format(_ input: Input) -> String {
        let session = input.session
        let events = input.events
        let promptDiffStats = input.promptDiffStats
        let uniqueFiles = input.uniqueFiles

        var lines: [String] = []

        let projectName = (session.projectPath as NSString).lastPathComponent
        let shortID = String(session.id.prefix(8))
        let duration = formattedDuration(from: session.startedAt, to: session.lastActivityAt)
        let timeRange = formattedTimeRange(from: session.startedAt, to: session.lastActivityAt)

        lines.append("## Session: \(shortID)")
        lines.append("**Project:** \(projectName)")
        lines.append("**Duration:** \(timeRange) (\(duration))")

        let fileCount = uniqueFiles.count
        var statsLine = "**Prompts:** \(events.count) | **Files:** \(fileCount)"
        if input.aggregateAdditions > 0 || input.aggregateDeletions > 0 {
            statsLine += " | **+\(input.aggregateAdditions) / -\(input.aggregateDeletions)**"
        }
        lines.append(statsLine)

        // Prompts section
        if !events.isEmpty {
            lines.append("")
            lines.append("### Prompts")
            for (i, event) in events.reversed().enumerated() {
                let text = event.promptText ?? "(no prompt)"
                let stat = promptDiffStats[event.id]
                let fileNames = stat?.fileStats.map { ($0.filePath as NSString).lastPathComponent } ?? []
                var entry = "\(i + 1). \(text)"
                if !fileNames.isEmpty {
                    let fileList = fileNames.prefix(5).joined(separator: ", ")
                    let suffix = fileNames.count > 5 ? " +\(fileNames.count - 5) more" : ""
                    entry += " (\(fileNames.count) file\(fileNames.count == 1 ? "" : "s"): \(fileList)\(suffix))"
                }
                lines.append(entry)
            }
        }

        // Files section
        if !uniqueFiles.isEmpty {
            lines.append("")
            lines.append("### Files Changed")
            for file in uniqueFiles {
                var entry = "- \(file.filePath)"
                if file.totalAdditions > 0 || file.totalDeletions > 0 {
                    entry += " (+\(file.totalAdditions) / -\(file.totalDeletions))"
                }
                if let desc = input.fileDescriptions[file.filePath] {
                    entry += " — \(desc)"
                }
                lines.append(entry)
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func formattedDuration(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        if interval < 60 {
            return "<1 min"
        } else if interval < 3600 {
            return "\(Int(interval / 60)) min"
        } else {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        }
    }

    private static func formattedTimeRange(from start: Date, to end: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return "\(dateFormatter.string(from: start)) \u{2013} \(timeFormatter.string(from: end))"
    }
}
