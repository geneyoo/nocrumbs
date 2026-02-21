import Foundation

// Minimal model structs for CLI → Socket JSON encoding
// Duplicated from app because CLI can't link the app target

struct SocketMessage: Encodable {
    let type: String
    let session_id: String
    let cwd: String
    let prompt: String?
    let file_path: String?
    let tool_name: String?
}

// Stdin JSON shapes from Claude Code hooks

struct UserPromptSubmitInput: Decodable {
    let session_id: String
    let prompt: String
    let cwd: String
}

struct PostToolUseInput: Decodable {
    let session_id: String
    let tool_name: String
    let tool_input: ToolInput
    let cwd: String

    struct ToolInput: Decodable {
        let file_path: String?
    }
}
