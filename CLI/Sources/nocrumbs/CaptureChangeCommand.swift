import Foundation

enum CaptureChangeCommand {
    static func run() throws {
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard !stdinData.isEmpty else {
            throw CLIError.invalidInput("No stdin data")
        }

        let input = try JSONDecoder().decode(PostToolUseInput.self, from: stdinData)

        guard let filePath = input.tool_input.file_path else {
            // No file path in tool input — skip silently
            return
        }

        let message = SocketMessage(
            type: "change",
            session_id: input.session_id,
            cwd: input.cwd,
            prompt: nil,
            file_path: filePath,
            tool_name: input.tool_name
        )

        let data = try JSONEncoder().encode(message)
        try SocketClient.send(data)
    }
}
