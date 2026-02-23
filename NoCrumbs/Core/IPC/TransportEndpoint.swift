import Foundation

/// Transport endpoint for NoCrumbs IPC — supports Unix domain socket and TCP.
enum TransportEndpoint: Equatable {
    case unix(String)
    case tcp(String, UInt16)

    /// Resolves the endpoint from environment variables and platform defaults.
    ///
    /// Priority:
    /// 1. `NOCRUMBS_SOCK` env var → Unix socket at that path
    /// 2. `NOCRUMBS_HOST` env var → TCP to host:port (default port 19876)
    /// 3. macOS → `~/Library/Application Support/NoCrumbs/nocrumbs.sock`
    /// 4. Linux → `/tmp/nocrumbs-$USER/nocrumbs.sock`
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> TransportEndpoint {
        if let sockPath = environment["NOCRUMBS_SOCK"] {
            return .unix(sockPath)
        }

        if let host = environment["NOCRUMBS_HOST"] {
            let port = environment["NOCRUMBS_PORT"].flatMap { UInt16($0) } ?? 19876
            return .tcp(host, port)
        }

        #if os(Linux)
        let user = environment["USER"] ?? "unknown"
        return .unix("/tmp/nocrumbs-\(user)/nocrumbs.sock")
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return .unix("\(home)/Library/Application Support/NoCrumbs/nocrumbs.sock")
        #endif
    }

    /// The default TCP port for remote connections.
    static let defaultTCPPort: UInt16 = 19876
}
