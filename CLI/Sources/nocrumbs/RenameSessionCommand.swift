import Foundation

enum RenameSessionCommand {
    static func run() throws {
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard !stdinData.isEmpty else {
            throw CLIError.invalidInput("No stdin data")
        }

        guard let raw = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any],
            let sessionID = raw["session_id"] as? String
        else {
            throw CLIError.invalidInput("Expected JSON with session_id and optional name")
        }

        let name = raw["name"] as? String

        var envelope: [String: Any] = [
            "type": "session-rename",
            "session_id": sessionID,
        ]
        if let name, !name.isEmpty {
            envelope["name"] = name
        }

        let data = try JSONSerialization.data(withJSONObject: envelope)
        try SocketClient.send(data)
    }
}
