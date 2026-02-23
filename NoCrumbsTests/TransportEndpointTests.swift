import XCTest

@testable import NoCrumbs

final class TransportEndpointTests: XCTestCase {

    // MARK: - Default (no env vars)

    func testDefaultEndpoint_macOS_isUnixSocket() {
        let endpoint = TransportEndpoint.resolve(environment: [:])
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = "\(home)/Library/Application Support/NoCrumbs/nocrumbs.sock"
        XCTAssertEqual(endpoint, .unix(expected))
    }

    func testDefaultEndpoint_matchesSocketServerPath() {
        let endpoint = TransportEndpoint.resolve(environment: [:])
        let serverPath = SocketServer.defaultSocketPath
        XCTAssertEqual(endpoint, .unix(serverPath))
    }

    // MARK: - NOCRUMBS_SOCK override

    func testEndpoint_NOCRUMBS_SOCK_overridesDefault() {
        let env = ["NOCRUMBS_SOCK": "/tmp/custom.sock"]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .unix("/tmp/custom.sock"))
    }

    func testEndpoint_NOCRUMBS_SOCK_takesPriorityOverHost() {
        let env = [
            "NOCRUMBS_SOCK": "/tmp/custom.sock",
            "NOCRUMBS_HOST": "192.168.1.1",
        ]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .unix("/tmp/custom.sock"))
    }

    // MARK: - NOCRUMBS_HOST (TCP)

    func testEndpoint_NOCRUMBS_HOST_selectsTCP() {
        let env = ["NOCRUMBS_HOST": "localhost"]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .tcp("localhost", 19876))
    }

    func testEndpoint_NOCRUMBS_HOST_withCustomPort() {
        let env = ["NOCRUMBS_HOST": "10.0.0.5", "NOCRUMBS_PORT": "12345"]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .tcp("10.0.0.5", 12345))
    }

    func testEndpoint_NOCRUMBS_HOST_invalidPort_fallsBackToDefault() {
        let env = ["NOCRUMBS_HOST": "localhost", "NOCRUMBS_PORT": "notanumber"]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .tcp("localhost", 19876))
    }

    // MARK: - Edge Cases

    func testEndpoint_NOCRUMBS_PORT_withoutHost_isIgnored() {
        let env = ["NOCRUMBS_PORT": "12345"]
        let endpoint = TransportEndpoint.resolve(environment: env)
        // PORT without HOST should fall through to platform default (Unix socket)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(endpoint, .unix("\(home)/Library/Application Support/NoCrumbs/nocrumbs.sock"))
    }

    func testEndpoint_emptySOCK_stillUsesIt() {
        // Empty string is still a valid override (user explicitly set it)
        let env = ["NOCRUMBS_SOCK": ""]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .unix(""))
    }

    func testEndpoint_NOCRUMBS_PORT_zero_usesTCP() {
        let env = ["NOCRUMBS_HOST": "localhost", "NOCRUMBS_PORT": "0"]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .tcp("localhost", 0))
    }

    func testEndpoint_NOCRUMBS_PORT_overflow_fallsBackToDefault() {
        // Port > UInt16.max should fall back to default
        let env = ["NOCRUMBS_HOST": "localhost", "NOCRUMBS_PORT": "99999"]
        let endpoint = TransportEndpoint.resolve(environment: env)
        XCTAssertEqual(endpoint, .tcp("localhost", 19876))
    }

    // MARK: - Default port constant

    func testDefaultTCPPort_is19876() {
        XCTAssertEqual(TransportEndpoint.defaultTCPPort, 19876)
    }
}
