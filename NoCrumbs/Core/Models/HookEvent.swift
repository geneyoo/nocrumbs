import Foundation

struct HookEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: String
    let hookEventName: String
    let projectPath: String
    let timestamp: Date
    let payload: String?  // JSON string, schema-free

    // Convenience accessors — parse payload lazily
    var prompt: String? { payloadValue(forKey: "prompt") as? String }
    var toolName: String? { payloadValue(forKey: "tool_name") as? String }
    var filePath: String? {
        guard let toolInput = payloadValue(forKey: "tool_input") as? [String: Any] else { return nil }
        return toolInput["file_path"] as? String
    }

    private func payloadValue(forKey key: String) -> Any? {
        guard let payload,
            let data = payload.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return dict[key]
    }

    static func == (lhs: HookEvent, rhs: HookEvent) -> Bool {
        lhs.id == rhs.id
    }
}
