import Foundation
#if canImport(Glibc)
import Glibc
#endif

enum SocketClient {
    // MARK: - Endpoint Resolution

    /// Transport endpoint — Unix domain socket or TCP.
    enum Endpoint: Equatable {
        case unix(String)
        case tcp(String, UInt16)

        static let defaultTCPPort: UInt16 = 19876
    }

    /// Resolves endpoint from env vars and platform defaults.
    ///
    /// Priority:
    /// 1. `NOCRUMBS_SOCK` → Unix socket at that path
    /// 2. `NOCRUMBS_HOST` → TCP to host:port (default 19876)
    /// 3. macOS → `~/Library/Application Support/NoCrumbs/nocrumbs.sock`
    /// 4. Linux → `/tmp/nocrumbs-$USER/nocrumbs.sock`
    static func resolveEndpoint(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Endpoint {
        if let sockPath = environment["NOCRUMBS_SOCK"] {
            return .unix(sockPath)
        }

        if let host = environment["NOCRUMBS_HOST"] {
            let port = environment["NOCRUMBS_PORT"].flatMap { UInt16($0) } ?? Endpoint.defaultTCPPort
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

    // MARK: - Connection

    /// Opens a connected socket to the given endpoint. Caller owns the fd and must close it.
    private static func connectSocket(to endpoint: Endpoint) throws -> Int32 {
        switch endpoint {
        case .unix(let path):
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw CLIError.socketFailed("create: \(errno)") }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = path.utf8CString
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
            withUnsafeMutableBytes(of: &addr.sun_path) { buf in
                for i in 0..<min(pathBytes.count, maxLen - 1) {
                    buf[i] = UInt8(bitPattern: pathBytes[i])
                }
            }

            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else {
                close(fd)
                throw CLIError.socketFailed("connect: \(errno)")
            }
            return fd

        case .tcp(let host, let port):
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw CLIError.socketFailed("create: \(errno)") }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
                close(fd)
                throw CLIError.socketFailed("invalid host: \(host)")
            }

            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else {
                close(fd)
                throw CLIError.socketFailed("connect: \(errno)")
            }
            return fd
        }
    }

    // MARK: - Send

    static func send(_ data: Data, to endpoint: Endpoint? = nil) throws {
        let ep = endpoint ?? resolveEndpoint()
        let fd = try connectSocket(to: ep)
        defer { close(fd) }

        let written = data.withUnsafeBytes { buf in
            // swiftlint:disable:next force_unwrapping
            write(fd, buf.baseAddress!, buf.count)
        }
        guard written == data.count else { throw CLIError.socketFailed("write incomplete") }
    }

    static func sendAndReceive(_ data: Data, to endpoint: Endpoint? = nil) throws -> Data {
        let ep = endpoint ?? resolveEndpoint()
        let fd = try connectSocket(to: ep)
        defer { close(fd) }

        // Write request
        let written = data.withUnsafeBytes { buf in
            // swiftlint:disable:next force_unwrapping
            write(fd, buf.baseAddress!, buf.count)
        }
        guard written == data.count else { throw CLIError.socketFailed("write incomplete") }

        // Signal write end done
        shutdown(fd, SHUT_WR)

        // Read response
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            response.append(contentsOf: buffer[..<n])
        }
        return response
    }
}

enum CLIError: Error, CustomStringConvertible {
    case socketFailed(String)
    case invalidInput(String)

    var description: String {
        switch self {
        case .socketFailed(let msg): "socket: \(msg)"
        case .invalidInput(let msg): "input: \(msg)"
        }
    }
}
