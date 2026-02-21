import Foundation

enum CapturePromptCommand {
    static func run() throws {
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard !stdinData.isEmpty else {
            throw CLIError.invalidInput("No stdin data")
        }

        let input = try JSONDecoder().decode(UserPromptSubmitInput.self, from: stdinData)

        let message = SocketMessage(
            type: "prompt",
            session_id: input.session_id,
            cwd: input.cwd,
            prompt: input.prompt,
            file_path: nil,
            tool_name: nil
        )

        let data = try JSONEncoder().encode(message)
        try SocketClient.send(data)
    }
}
