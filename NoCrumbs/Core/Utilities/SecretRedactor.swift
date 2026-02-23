import Foundation

enum SecretRedactor {
    private static let patterns: [(NSRegularExpression, String)] = {
        let defs: [(String, String)] = [
            // OpenAI / Anthropic keys (sk-proj-..., sk-ant-...)
            (#"sk-[a-zA-Z0-9_-]{20,}"#, "[REDACTED]"),
            // AWS access key IDs
            (#"AKIA[0-9A-Z]{16}"#, "[REDACTED]"),
            // GitHub personal access tokens
            (#"ghp_[a-zA-Z0-9]{36}"#, "[REDACTED]"),
            // GitHub OAuth tokens
            (#"gho_[a-zA-Z0-9]{36}"#, "[REDACTED]"),
            // GitLab PATs
            (#"glpat-[a-zA-Z0-9_-]{20,}"#, "[REDACTED]"),
            // Slack bot tokens
            (#"xoxb-[a-zA-Z0-9-]+"#, "[REDACTED]"),
            // Slack user tokens
            (#"xoxp-[a-zA-Z0-9-]+"#, "[REDACTED]"),
            // JWTs (3-part base64)
            (#"eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}"#, "[REDACTED]"),
            // Generic base64 secrets preceded by key-like words
            (#"(?i)(?:password|passwd|secret|token|api_key|apikey)\s*[=:]\s*[a-zA-Z0-9+/]{40,}={0,2}"#, "[REDACTED]"),
            // Key-value assignments with secret-like keys
            (#"(?i)(?:password|passwd|secret|token|api_key|apikey)\s*[=:]\s*\S+"#, "[REDACTED]"),
        ]
        return defs.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, replacement)
        }
    }()

    static func redact(_ text: String) -> String {
        var result = text
        for (regex, replacement) in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }
}
