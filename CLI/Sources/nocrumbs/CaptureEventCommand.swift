import Foundation

enum CaptureEventCommand {
    /// Keys to forward from stdin JSON to the app. Everything else is dropped.
    private static let forwardKeys: Set<String> = [
        "session_id", "cwd", "hook_event_name",
        "prompt", "tool_name", "tool_input",
        "stop_hook_active", "agent_id", "agent_type",
    ]

    static func run() throws {
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard !stdinData.isEmpty else {
            throw CLIError.invalidInput("No stdin data")
        }

        guard let raw = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] else {
            throw CLIError.invalidInput("Invalid JSON on stdin")
        }

        // Build envelope with only interesting keys
        var envelope: [String: Any] = ["type": "event"]
        for key in forwardKeys {
            guard let value = raw[key] else { continue }
            // For tool_input, extract only file_path to keep payload small
            if key == "tool_input", let dict = value as? [String: Any] {
                if let filePath = dict["file_path"] {
                    envelope["tool_input"] = ["file_path": filePath]
                }
            } else {
                envelope[key] = value
            }
        }

        let data = try JSONSerialization.data(withJSONObject: envelope)
        try SocketClient.send(data)
    }
}
