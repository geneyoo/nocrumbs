import XCTest

@testable import NoCrumbs

final class RemoteURLParserTests: XCTestCase {
    private let testHash = "abc1234def5678"

    // MARK: - GitHub

    func testGitHubSSH() {
        let url = RemoteURLParser.commitURL(remoteURL: "git@github.com:user/repo.git", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://github.com/user/repo/commit/\(testHash)")
    }

    func testGitHubHTTPS() {
        let url = RemoteURLParser.commitURL(remoteURL: "https://github.com/user/repo.git", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://github.com/user/repo/commit/\(testHash)")
    }

    func testGitHubHTTPSNoSuffix() {
        let url = RemoteURLParser.commitURL(remoteURL: "https://github.com/user/repo", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://github.com/user/repo/commit/\(testHash)")
    }

    // MARK: - GitLab

    func testGitLabSSH() {
        let url = RemoteURLParser.commitURL(remoteURL: "git@gitlab.com:org/project.git", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://gitlab.com/org/project/commit/\(testHash)")
    }

    func testGitLabHTTPS() {
        let url = RemoteURLParser.commitURL(remoteURL: "https://gitlab.com/org/project.git", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://gitlab.com/org/project/commit/\(testHash)")
    }

    // MARK: - Bitbucket

    func testBitbucketSSH() {
        let url = RemoteURLParser.commitURL(remoteURL: "git@bitbucket.org:team/repo.git", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://bitbucket.org/team/repo/commit/\(testHash)")
    }

    func testBitbucketHTTPS() {
        let url = RemoteURLParser.commitURL(remoteURL: "https://bitbucket.org/team/repo.git", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://bitbucket.org/team/repo/commit/\(testHash)")
    }

    // MARK: - Edge Cases

    func testEmptyRemoteURL() {
        XCTAssertNil(RemoteURLParser.commitURL(remoteURL: "", hash: testHash))
    }

    func testEmptyHash() {
        XCTAssertNil(RemoteURLParser.commitURL(remoteURL: "git@github.com:user/repo.git", hash: ""))
    }

    func testWhitespaceHandling() {
        let url = RemoteURLParser.commitURL(remoteURL: "  git@github.com:user/repo.git\n", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://github.com/user/repo/commit/\(testHash)")
    }

    func testNestedPath() {
        let url = RemoteURLParser.commitURL(remoteURL: "git@gitlab.com:org/sub/repo.git", hash: testHash)
        XCTAssertEqual(url?.absoluteString, "https://gitlab.com/org/sub/repo/commit/\(testHash)")
    }

    func testInvalidURL() {
        XCTAssertNil(RemoteURLParser.commitURL(remoteURL: "not-a-url", hash: testHash))
    }
}
