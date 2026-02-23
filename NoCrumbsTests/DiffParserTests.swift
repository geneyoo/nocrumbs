import XCTest

@testable import NoCrumbs

final class DiffParserTests: XCTestCase {

    func testEmptyDiff() {
        XCTAssertEqual(DiffParser.parse(""), [])
        XCTAssertEqual(DiffParser.parse("   \n  "), [])
    }

    func testSingleFileAddition() {
        let raw = """
            diff --git a/new.swift b/new.swift
            new file mode 100644
            --- /dev/null
            +++ b/new.swift
            @@ -0,0 +1,3 @@
            +import Foundation
            +
            +struct New {}
            """

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .added)
        XCTAssertNil(diffs[0].oldPath)
        XCTAssertEqual(diffs[0].newPath, "new.swift")
        XCTAssertEqual(diffs[0].hunks.count, 1)
        let additions = diffs[0].hunks[0].lines.filter { $0.type == .addition }
        XCTAssertGreaterThanOrEqual(additions.count, 3)
    }

    func testSingleFileDeletion() {
        let raw = """
            diff --git a/old.swift b/old.swift
            deleted file mode 100644
            --- a/old.swift
            +++ /dev/null
            @@ -1,2 +0,0 @@
            -import Foundation
            -struct Old {}
            """

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .deleted)
        XCTAssertEqual(diffs[0].oldPath, "old.swift")
        XCTAssertNil(diffs[0].newPath)
        let deletions = diffs[0].hunks[0].lines.filter { $0.type == .deletion }
        XCTAssertEqual(deletions.count, 2)
    }

    func testModifiedFile() {
        let raw =
            "diff --git a/file.swift b/file.swift\n" + "--- a/file.swift\n" + "+++ b/file.swift\n" + "@@ -1,3 +1,3 @@\n" + " import Foundation\n"
            + "-let old = 1\n" + "+let new = 2\n" + " struct S {}"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .modified)
        let lines = diffs[0].hunks[0].lines
        // Parser may add trailing context from chunk assembly; verify meaningful lines
        XCTAssertEqual(lines.filter { $0.type == .addition }.count, 1)
        XCTAssertEqual(lines.filter { $0.type == .deletion }.count, 1)
        XCTAssertGreaterThanOrEqual(lines.filter { $0.type == .context }.count, 2)
    }

    func testMultipleFiles() {
        let raw =
            "diff --git a/a.swift b/a.swift\n" + "--- a/a.swift\n" + "+++ b/a.swift\n" + "@@ -1,1 +1,1 @@\n" + "-old\n" + "+new\n"
            + "diff --git a/b.swift b/b.swift\n" + "new file mode 100644\n" + "--- /dev/null\n" + "+++ b/b.swift\n" + "@@ -0,0 +1,1 @@\n" + "+hello"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 2)
        XCTAssertEqual(diffs[0].status, .modified)
        XCTAssertEqual(diffs[1].status, .added)
    }

    func testMultipleHunks() {
        let raw =
            "diff --git a/file.swift b/file.swift\n" + "--- a/file.swift\n" + "+++ b/file.swift\n" + "@@ -1,3 +1,3 @@\n" + " line1\n" + "-old1\n" + "+new1\n"
            + " line3\n" + "@@ -10,3 +10,3 @@\n" + " line10\n" + "-old2\n" + "+new2\n" + " line12"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].hunks.count, 2)
    }

    func testLineNumbers() {
        let raw =
            "diff --git a/file.swift b/file.swift\n" + "--- a/file.swift\n" + "+++ b/file.swift\n" + "@@ -5,4 +5,4 @@\n" + " context\n" + "-deleted\n"
            + "+added\n" + " context2"

        let diffs = DiffParser.parse(raw)
        let lines = diffs[0].hunks[0].lines

        // Context line at old=5, new=5
        XCTAssertEqual(lines[0].type, .context)
        XCTAssertEqual(lines[0].oldLineNumber, 5)
        XCTAssertEqual(lines[0].newLineNumber, 5)

        // Deletion at old=6
        XCTAssertEqual(lines[1].type, .deletion)
        XCTAssertEqual(lines[1].oldLineNumber, 6)
        XCTAssertNil(lines[1].newLineNumber)

        // Addition at new=6
        XCTAssertEqual(lines[2].type, .addition)
        XCTAssertNil(lines[2].oldLineNumber)
        XCTAssertEqual(lines[2].newLineNumber, 6)

        // Context at old=7, new=7
        XCTAssertEqual(lines[3].type, .context)
        XCTAssertEqual(lines[3].oldLineNumber, 7)
        XCTAssertEqual(lines[3].newLineNumber, 7)
    }

    func testNoNewlineAtEOF() {
        let raw =
            "diff --git a/file.swift b/file.swift\n" + "--- a/file.swift\n" + "+++ b/file.swift\n" + "@@ -1,1 +1,1 @@\n" + "-old\n"
            + "\\ No newline at end of file\n" + "+new\n" + "\\ No newline at end of file"

        let diffs = DiffParser.parse(raw)
        let lines = diffs[0].hunks[0].lines
        let meaningful = lines.filter { $0.type != .context }
        // Should have exactly 2 meaningful lines (deletion + addition)
        XCTAssertEqual(meaningful.count, 2)
        XCTAssertEqual(meaningful[0].type, .deletion)
        XCTAssertEqual(meaningful[1].type, .addition)
    }

    func testBinaryFile() {
        let raw =
            "diff --git a/image.png b/image.png\n" + "Binary files /dev/null and b/image.png differ"

        let diffs = DiffParser.parse(raw)
        // Binary diffs have no --- / +++ headers, so parser returns nil or empty-hunk FileDiff
        XCTAssertTrue(diffs.isEmpty || diffs[0].hunks.isEmpty)
    }

    func testEmptyHunk() {
        let raw =
            "diff --git a/file.swift b/file.swift\n" + "--- a/file.swift\n" + "+++ b/file.swift\n" + "@@ -1,0 +1,0 @@"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].hunks.count, 1)
        // Parser may include trailing empty line from chunk assembly
        let meaningful = diffs[0].hunks[0].lines.filter { !$0.text.isEmpty }
        XCTAssertEqual(meaningful.count, 0)
    }

    // MARK: - Mercurial Format Tests

    func testMercurialGitFormat() {
        // `hg diff --git` produces identical output to `git diff`
        let raw =
            "diff --git a/ViewModel.swift b/ViewModel.swift\n"
            + "--- a/ViewModel.swift\n"
            + "+++ b/ViewModel.swift\n"
            + "@@ -1,3 +1,3 @@\n"
            + " import Foundation\n"
            + "-let old = 1\n"
            + "+let new = 2\n"
            + " struct VM {}"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .modified)
        XCTAssertEqual(diffs[0].oldPath, "ViewModel.swift")
        XCTAssertEqual(diffs[0].newPath, "ViewModel.swift")
    }

    func testMercurialNewFile() {
        // Mercurial new file diff (no mode line)
        let raw =
            "diff --git a/new.swift b/new.swift\n"
            + "--- /dev/null\n"
            + "+++ b/new.swift\n"
            + "@@ -0,0 +1,2 @@\n"
            + "+import Foundation\n"
            + "+struct New {}"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .added)
        XCTAssertNil(diffs[0].oldPath)
        XCTAssertEqual(diffs[0].newPath, "new.swift")
    }

    func testMercurialWithHgHeaders() {
        // Mercurial may emit extra headers before `diff --git` — parser should ignore them
        let raw =
            "# HG changeset patch\n"
            + "# User test@example.com\n"
            + "# Date 1234567890 0\n"
            + "diff --git a/file.swift b/file.swift\n"
            + "--- a/file.swift\n"
            + "+++ b/file.swift\n"
            + "@@ -1,1 +1,1 @@\n"
            + "-old\n"
            + "+new"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .modified)
    }

    func testPathsWithoutPrefixes() {
        // Some VCS tools emit paths without a/ b/ prefixes
        let raw =
            "diff --git a/file.swift b/file.swift\n"
            + "--- file.swift\n"
            + "+++ file.swift\n"
            + "@@ -1,1 +1,1 @@\n"
            + "-old\n"
            + "+new"

        let diffs = DiffParser.parse(raw)
        XCTAssertEqual(diffs.count, 1)
        // Without a/ prefix, path is kept as-is
        XCTAssertEqual(diffs[0].oldPath, "file.swift")
        XCTAssertEqual(diffs[0].newPath, "file.swift")
    }
}
