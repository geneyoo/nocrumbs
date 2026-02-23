import XCTest

@testable import NoCrumbs

/// Integration tests that spin up real Unix and TCP socket servers
/// and verify the app-side SocketClient can send/receive through them.
final class SocketTransportTests: XCTestCase {

    // MARK: - Unix Socket Tests

    func testSend_unixSocket() throws {
        let (serverFD, path) = try makeUnixServer()
        defer {
            close(serverFD)
            unlink(path)
        }

        let payload = "hello unix".data(using: .utf8)!

        // Accept in background
        let expectation = expectation(description: "received data")
        var received = Data()

        DispatchQueue.global().async {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }
            received = self.readAll(fd: clientFD)
            expectation.fulfill()
        }

        // Send via app-side SocketClient
        try NoCrumbs.SocketClient.send(payload, to: path)

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(received, payload)
    }

    func testSendAndReceive_unixSocket() throws {
        let (serverFD, path) = try makeUnixServer()
        defer {
            close(serverFD)
            unlink(path)
        }

        let request = #"{"type":"query-prompts","cwd":"/"}"#.data(using: .utf8)!
        let responsePayload = #"{"prompts":[]}"#.data(using: .utf8)!

        // Echo server: read request, write response
        DispatchQueue.global().async {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }
            _ = self.readAll(fd: clientFD)
            _ = responsePayload.withUnsafeBytes { buf in
                write(clientFD, buf.baseAddress!, buf.count)
            }
        }

        let response = try sendAndReceiveUnix(request, path: path)
        XCTAssertEqual(response, responsePayload)
    }

    // MARK: - TCP Socket Tests

    func testSend_tcpSocket() throws {
        let (serverFD, port) = try makeTCPServer()
        defer { close(serverFD) }

        let payload = "hello tcp".data(using: .utf8)!

        let expectation = expectation(description: "received tcp data")
        var received = Data()

        DispatchQueue.global().async {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }
            received = self.readAll(fd: clientFD)
            expectation.fulfill()
        }

        try sendTCP(payload, host: "127.0.0.1", port: port)

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(received, payload)
    }

    func testSendAndReceive_tcpSocket() throws {
        let (serverFD, port) = try makeTCPServer()
        defer { close(serverFD) }

        let request = "request".data(using: .utf8)!
        let responsePayload = "response".data(using: .utf8)!

        DispatchQueue.global().async {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }
            _ = self.readAll(fd: clientFD)
            _ = responsePayload.withUnsafeBytes { buf in
                write(clientFD, buf.baseAddress!, buf.count)
            }
        }

        let response = try sendAndReceiveTCP(request, host: "127.0.0.1", port: port)
        XCTAssertEqual(response, responsePayload)
    }

    // MARK: - Failure Tests

    func testSend_noListener_throws() {
        let bogusPath = "/tmp/nocrumbs-test-\(UUID().uuidString).sock"
        XCTAssertThrowsError(
            try NoCrumbs.SocketClient.send("x".data(using: .utf8)!, to: bogusPath)
        )
    }

    func testSendTCP_noListener_throws() {
        // Port 1 is almost certainly not listening
        XCTAssertThrowsError(
            try sendTCP("x".data(using: .utf8)!, host: "127.0.0.1", port: 1)
        )
    }

    // MARK: - TCP Server Lifecycle Tests

    /// Verifies that a TCP listener on a port accepts connections (pure socket level, no SocketServer).
    func testTCPListener_acceptsAndEchoes() throws {
        let (serverFD, port) = try makeTCPServer()
        defer { close(serverFD) }

        let payload = #"{"type":"event"}"#.data(using: .utf8)!
        let responsePayload = #"{"ok":true}"#.data(using: .utf8)!

        // Server: accept, read, respond
        DispatchQueue.global().async {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }
            _ = self.readAll(fd: clientFD)
            _ = responsePayload.withUnsafeBytes { buf in
                write(clientFD, buf.baseAddress!, buf.count)
            }
        }

        // Client: connect via TCP, send, receive
        let response = try sendAndReceiveTCP(payload, host: "127.0.0.1", port: port)
        XCTAssertEqual(response, responsePayload)
    }

    /// Verifies that closing a TCP server fd prevents new connections.
    func testTCPListener_closedFD_refusesConnection() throws {
        let (serverFD, port) = try makeTCPServer()
        close(serverFD) // immediately close

        XCTAssertThrowsError(
            try sendTCP("x".data(using: .utf8)!, host: "127.0.0.1", port: port),
            "Connection should fail after server fd is closed"
        )
    }

    // MARK: - Large Payload

    func testSend_largePayload_unixSocket() throws {
        let (serverFD, path) = try makeUnixServer()
        defer {
            close(serverFD)
            unlink(path)
        }

        // 128KB payload — larger than a single read buffer
        let payload = Data(repeating: 0x41, count: 131_072)

        let expectation = expectation(description: "received large data")
        var received = Data()

        DispatchQueue.global().async {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }
            received = self.readAll(fd: clientFD)
            expectation.fulfill()
        }

        try NoCrumbs.SocketClient.send(payload, to: path)

        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(received.count, payload.count)
    }

    // MARK: - Helpers

    /// Creates a Unix domain socket server bound to a temp path. Returns (fd, path).
    private func makeUnixServer() throws -> (Int32, String) {
        let path = "/tmp/nocrumbs-test-\(UUID().uuidString).sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }

        var addr = makeUnixAddr(path: path)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw SocketError.bindFailed(errno)
        }
        guard listen(fd, 1) == 0 else {
            close(fd)
            throw SocketError.listenFailed(errno)
        }
        return (fd, path)
    }

    /// Creates a TCP server on localhost with an ephemeral port. Returns (fd, port).
    private func makeTCPServer() throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }

        var reuseAddr: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ephemeral
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw SocketError.bindFailed(errno)
        }
        guard listen(fd, 1) == 0 else {
            close(fd)
            throw SocketError.listenFailed(errno)
        }

        // Read back actual port
        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        getsockname(fd, withUnsafeMutablePointer(to: &boundAddr) { ptr in
            UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: sockaddr.self)
        }, &boundLen)
        let port = UInt16(bigEndian: boundAddr.sin_port)

        return (fd, port)
    }

    private func readAll(fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[..<n])
        }
        return data
    }

    /// Sends data via a raw TCP connection (bypasses SocketClient to test independently).
    private func sendTCP(_ data: Data, host: String, port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw SocketError.connectFailed(errno) }

        let written = data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress!, buf.count)
        }
        guard written == data.count else { throw SocketError.sendFailed }
    }

    /// Sends data and reads response via a raw TCP connection.
    private func sendAndReceiveTCP(_ data: Data, host: String, port: UInt16) throws -> Data {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw SocketError.connectFailed(errno) }

        let written = data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress!, buf.count)
        }
        guard written == data.count else { throw SocketError.sendFailed }

        shutdown(fd, SHUT_WR)
        return readAll(fd: fd)
    }

    /// Sends data and reads response via a raw Unix socket connection.
    private func sendAndReceiveUnix(_ data: Data, path: String) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.createFailed(errno) }
        defer { close(fd) }

        var addr = makeUnixAddr(path: path)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw SocketError.connectFailed(errno) }

        let written = data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress!, buf.count)
        }
        guard written == data.count else { throw SocketError.sendFailed }

        shutdown(fd, SHUT_WR)
        return readAll(fd: fd)
    }
}
