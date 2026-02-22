import Foundation

enum DescribeCommand {
    static func run() throws {
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard !stdinData.isEmpty else {
            throw CLIError.invalidInput("No stdin data")
        }

        guard let raw = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any],
            let sessionID = raw["session_id"] as? String,
            let descriptions = raw["descriptions"] as? [[String: Any]]
        else {
            throw CLIError.invalidInput("Expected JSON with session_id and descriptions array")
        }

        let envelope: [String: Any] = [
            "type": "file-descriptions",
            "session_id": sessionID,
            "descriptions": descriptions,
        ]

        let data = try JSONSerialization.data(withJSONObject: envelope)
        try SocketClient.send(data)
    }
}
