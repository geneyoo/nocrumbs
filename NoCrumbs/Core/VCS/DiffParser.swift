import Foundation

enum DiffParser {

    static func parse(_ raw: String) -> [FileDiff] {
        let fileChunks = splitFileChunks(raw)
        return fileChunks.compactMap { parseFileDiff($0) }
    }

    // MARK: - Private

    private static func splitFileChunks(_ raw: String) -> [String] {
        let marker = "diff --git "
        var chunks: [String] = []
        var current = ""

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(marker) {
                if !current.isEmpty { chunks.append(current) }
                current = String(line) + "\n"
            } else {
                current += String(line) + "\n"
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func parseFileDiff(_ chunk: String) -> FileDiff? {
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }

        var oldPath: String?
        var newPath: String?
        var hunkLines: [(header: String, body: [String])] = []
        var currentBody: [String] = []
        var currentHeader: String?

        for line in lines {
            if line.hasPrefix("--- ") {
                let path = String(line.dropFirst(4))
                oldPath = path == "/dev/null" ? nil : path.hasPrefix("a/") ? String(path.dropFirst(2)) : path
            } else if line.hasPrefix("+++ ") {
                let path = String(line.dropFirst(4))
                newPath = path == "/dev/null" ? nil : path.hasPrefix("b/") ? String(path.dropFirst(2)) : path
            } else if line.hasPrefix("@@ ") {
                if let header = currentHeader {
                    hunkLines.append((header: header, body: currentBody))
                }
                currentHeader = line
                currentBody = []
            } else if currentHeader != nil {
                currentBody.append(line)
            }
        }
        if let header = currentHeader {
            hunkLines.append((header: header, body: currentBody))
        }

        let status: FileDiff.FileStatus
        if oldPath == nil { status = .added }
        else if newPath == nil { status = .deleted }
        else { status = .modified }

        let hunks = hunkLines.compactMap { parseHunk(header: $0.header, body: $0.body) }

        return FileDiff(
            id: UUID(),
            oldPath: oldPath,
            newPath: newPath,
            hunks: hunks,
            status: status
        )
    }

    private static func parseHunk(header: String, body: [String]) -> DiffHunk? {
        // Parse @@ -oldStart,oldCount +newStart,newCount @@
        guard let rangeStart = header.firstIndex(of: "-"),
              let rangeEnd = header.range(of: " @@") else { return nil }

        let rangeStr = String(header[rangeStart..<rangeEnd.lowerBound])
        let parts = rangeStr.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let oldParts = parseRange(String(parts[0]))
        let newParts = parseRange(String(parts[1]))

        var oldLine = oldParts.start
        var newLine = newParts.start
        var diffLines: [DiffLine] = []

        for line in body {
            if line.hasPrefix("+") {
                diffLines.append(DiffLine(
                    id: UUID(),
                    type: .addition,
                    text: String(line.dropFirst()),
                    oldLineNumber: nil,
                    newLineNumber: newLine
                ))
                newLine += 1
            } else if line.hasPrefix("-") {
                diffLines.append(DiffLine(
                    id: UUID(),
                    type: .deletion,
                    text: String(line.dropFirst()),
                    oldLineNumber: oldLine,
                    newLineNumber: nil
                ))
                oldLine += 1
            } else if line.hasPrefix(" ") || line.isEmpty {
                let text = line.isEmpty ? "" : String(line.dropFirst())
                diffLines.append(DiffLine(
                    id: UUID(),
                    type: .context,
                    text: text,
                    oldLineNumber: oldLine,
                    newLineNumber: newLine
                ))
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — skip
                continue
            }
        }

        return DiffHunk(
            id: UUID(),
            oldStart: oldParts.start,
            oldCount: oldParts.count,
            newStart: newParts.start,
            newCount: newParts.count,
            lines: diffLines
        )
    }

    private static func parseRange(_ str: String) -> (start: Int, count: Int) {
        // "-3,7" or "+1,5" or "-3" (count=1)
        let cleaned = str.hasPrefix("-") || str.hasPrefix("+") ? String(str.dropFirst()) : str
        let parts = cleaned.split(separator: ",")
        let start = Int(parts[0]) ?? 1
        let count = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        return (start, count)
    }
}
