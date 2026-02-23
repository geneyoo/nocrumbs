import Foundation
import OSLog

private let logger = Logger(subsystem: "com.geneyoo.nocrumbs", category: "VCS")

enum VCSBinaryResolver {
    /// Resolves the full path to a VCS binary by checking known locations.
    /// GUI apps have no PATH, so `/usr/bin/env` won't work — we check explicit paths instead.
    static func resolve(_ name: String, knownPaths: [String]) -> String {
        for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            logger.info("Resolved \(name, privacy: .public) → \(path, privacy: .public)")
            return path
        }
        // Fallback: assume it's in /usr/local/bin (common for Homebrew on Intel)
        let fallback = "/usr/local/bin/\(name)"
        logger.warning("Could not resolve \(name, privacy: .public) — falling back to \(fallback, privacy: .public)")
        return fallback
    }
}
