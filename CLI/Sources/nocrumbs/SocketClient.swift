import Foundation

enum SocketClient {
    static var defaultSocketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/NoCrumbs/nocrumbs.sock"
    }

    static func send(_ data: Data, to path: String = defaultSocketPath) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIError.socketFailed("create: \(errno)") }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for i in 0..<min(pathBytes.count, maxLen - 1) {
                buf[i] = UInt8(bitPattern: pathBytes[i])
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw CLIError.socketFailed("connect: \(errno)") }

        let written = data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress!, buf.count)
        }
        guard written == data.count else { throw CLIError.socketFailed("write incomplete") }
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
