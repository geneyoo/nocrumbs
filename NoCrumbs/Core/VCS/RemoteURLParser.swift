import Foundation

enum RemoteURLParser {
    /// Parse a git remote URL into a web commit URL.
    /// Handles SSH (`git@host:user/repo.git`) and HTTPS (`https://host/user/repo.git`).
    /// Works for GitHub, GitLab, Bitbucket, Gitea — all use `/commit/{sha}`.
    static func commitURL(remoteURL: String, hash: String) -> URL? {
        guard !remoteURL.isEmpty, !hash.isEmpty else { return nil }

        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var host: String
        var path: String

        if let range = trimmed.range(of: "@"), trimmed.contains(":"), !trimmed.hasPrefix("http") {
            // SSH: git@github.com:user/repo.git
            let afterAt = trimmed[range.upperBound...]
            guard let colonIdx = afterAt.firstIndex(of: ":") else { return nil }
            host = String(afterAt[afterAt.startIndex..<colonIdx])
            path = String(afterAt[afterAt.index(after: colonIdx)...])
        } else if let url = URL(string: trimmed), let urlHost = url.host, !urlHost.isEmpty {
            // HTTPS: https://github.com/user/repo.git
            host = urlHost
            path = url.path
            // Remove leading slash
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        } else {
            return nil
        }

        // Strip .git suffix
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }

        guard !path.isEmpty else { return nil }

        return URL(string: "https://\(host)/\(path)/commit/\(hash)")
    }
}
