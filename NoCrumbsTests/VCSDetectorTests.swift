import XCTest

@testable import NoCrumbs

// swiftlint:disable force_unwrapping implicitly_unwrapped_optional
final class VCSDetectorTests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "nocrumbs-vcs-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tmpDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    func testDetectGit() throws {
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/.git", withIntermediateDirectories: true
        )
        XCTAssertEqual(VCSDetector.detect(at: tmpDir), .git)
    }

    func testDetectMercurial() throws {
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/.hg", withIntermediateDirectories: true
        )
        XCTAssertEqual(VCSDetector.detect(at: tmpDir), .mercurial)
    }

    func testDetectSapling() throws {
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/.sl", withIntermediateDirectories: true
        )
        XCTAssertEqual(VCSDetector.detect(at: tmpDir), .sapling)
    }

    func testDetectNone() {
        XCTAssertNil(VCSDetector.detect(at: tmpDir))
    }

    func testDetectNested() throws {
        let child = "\(tmpDir!)/child"
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/.git", withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: "\(child)/.hg", withIntermediateDirectories: true
        )
        XCTAssertEqual(VCSDetector.detect(at: child), .mercurial)
        XCTAssertEqual(VCSDetector.detect(at: tmpDir), .git)
    }

    func testRepoRoot() throws {
        let nested = "\(tmpDir!)/a/b/c"
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/.git", withIntermediateDirectories: true
        )
        let root = VCSDetector.repoRoot(at: nested, for: .git)
        XCTAssertEqual(root, tmpDir)
    }
    func testRepoRootSapling() throws {
        let nested = "\(tmpDir!)/a/b/c"
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/.sl", withIntermediateDirectories: true
        )
        let root = VCSDetector.repoRoot(at: nested, for: .sapling)
        XCTAssertEqual(root, tmpDir)
    }
    func testDetectWithTrailingSlash() throws {
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/.hg", withIntermediateDirectories: true
        )
        // Trailing slash should not break detection
        XCTAssertEqual(VCSDetector.detect(at: tmpDir + "/"), .mercurial)
    }

    func testNormalizePath() {
        // Trailing slash removed
        XCTAssertFalse(VCSDetector.normalizePath("/tmp/test/").hasSuffix("/"))

        // Root path preserved
        XCTAssertEqual(VCSDetector.normalizePath("/"), "/")

        // Normal path unchanged
        let normal = VCSDetector.normalizePath("/tmp/test")
        XCTAssertEqual(normal, "/tmp/test")
    }

    func testDetectWithSymlink() throws {
        // Create actual .hg dir and a symlink to the parent
        try FileManager.default.createDirectory(
            atPath: "\(tmpDir!)/real/.hg", withIntermediateDirectories: true
        )
        let symlink = "\(tmpDir!)/link"
        try FileManager.default.createSymbolicLink(
            atPath: symlink, withDestinationPath: "\(tmpDir!)/real"
        )
        // Symlink should be resolved and .hg found
        XCTAssertEqual(VCSDetector.detect(at: symlink), .mercurial)
    }
}
// swiftlint:enable force_unwrapping implicitly_unwrapped_optional
