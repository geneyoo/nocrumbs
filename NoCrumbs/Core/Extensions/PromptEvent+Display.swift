import Foundation

extension PromptEvent {
    var isEmptyPrompt: Bool {
        guard let text = promptText else { return true }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
