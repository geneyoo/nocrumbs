import Foundation

enum SocketClient {
    static func send(_ data: Data, to path: String = SocketServer.defaultSocketPath) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }
        defer { close(fd) }

        var addr = makeUnixAddr(path: path)

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw SocketError.connectFailed(errno) }

        let written = data.withUnsafeBytes { buf in
            // swiftlint:disable:next force_unwrapping
            write(fd, buf.baseAddress!, buf.count)
        }
        guard written == data.count else { throw SocketError.sendFailed }
    }
}

func makeUnixAddr(path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        for i in 0..<min(pathBytes.count, maxLen - 1) {
            buf[i] = UInt8(bitPattern: pathBytes[i])
        }
    }
    return addr
}
