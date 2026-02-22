import XCTest

@testable import NoCrumbs

final class TemplateRendererTests: XCTestCase {
    private let sampleContext = TemplateContext(
        promptCount: 3,
        totalFiles: 8,
        sessionID: "abcdef1234567890",
        prompts: [
            (text: "refactor auth to async/await", fileCount: 3),
            (text: "add error handling", fileCount: 3),
            (text: "update tests", fileCount: 2),
        ]
    )

    func testSimplePlaceholders() {
        let template = "{{prompt_count}} prompts, {{total_files}} files, {{session_id}}"
        let result = TemplateRenderer.render(template, context: sampleContext)
        XCTAssertEqual(result, "3 prompts, 8 files, abcdef12")
    }

    func testSummaryLine() {
        let template = "{{summary_line}}"
        let result = TemplateRenderer.render(template, context: sampleContext)
        XCTAssertEqual(result, "🍞 3 prompts · 8 files · abcdef12")
    }

    func testSummaryLineSingular() {
        let ctx = TemplateContext(
            promptCount: 1, totalFiles: 1, sessionID: "abc12345",
            prompts: [(text: "fix bug", fileCount: 1)]
        )
        let result = TemplateRenderer.render("{{summary_line}}", context: ctx)
        XCTAssertEqual(result, "🍞 1 prompt · 1 file · abc12345")
    }

    func testPromptLoop() {
        let template = "{{#prompts}}{{index}}. {{text}} ({{file_count}})\n{{/prompts}}"
        let result = TemplateRenderer.render(template, context: sampleContext)
        let expected = """
            1. refactor auth to async/await (3)
            2. add error handling (3)
            3. update tests (2)

            """
        XCTAssertEqual(result, expected)
    }

    func testPromptTextTruncation() {
        let longText = String(repeating: "a", count: 100)
        let ctx = TemplateContext(
            promptCount: 1, totalFiles: 1, sessionID: "abc",
            prompts: [(text: longText, fileCount: 1)]
        )
        let template = "{{#prompts}}{{text}}{{/prompts}}"
        let result = TemplateRenderer.render(template, context: ctx)
        XCTAssertEqual(result.count, 72)  // 69 chars + "..."
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testNoLoopBlock() {
        let template = "---\n{{summary_line}}"
        let result = TemplateRenderer.render(template, context: sampleContext)
        XCTAssertEqual(result, "---\n🍞 3 prompts · 8 files · abcdef12")
    }

    func testEmptyPrompts() {
        let ctx = TemplateContext(
            promptCount: 0, totalFiles: 0, sessionID: "empty123",
            prompts: []
        )
        let template = "{{#prompts}}{{index}}. {{text}}\n{{/prompts}}"
        let result = TemplateRenderer.render(template, context: ctx)
        XCTAssertEqual(result, "")
    }

    func testFullTemplate() {
        let template = """
            ---
            {{summary_line}}

            {{#prompts}}
            {{index}}. {{text}} ({{file_count}} files)
            {{/prompts}}
            """
        let result = TemplateRenderer.render(template, context: sampleContext)
        XCTAssertTrue(result.contains("🍞 3 prompts · 8 files · abcdef12"))
        XCTAssertTrue(result.contains("1. refactor auth to async/await (3 files)"))
        XCTAssertTrue(result.contains("3. update tests (2 files)"))
    }
}

@MainActor
final class CommitTemplateDBTests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var db: Database!
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var tempPath: String!

    override func setUp() {
        super.setUp()
        tempPath = NSTemporaryDirectory() + "nocrumbs_tmpl_test_\(UUID().uuidString).sqlite"
        db = Database(path: tempPath)
        try? db.open()
    }

    override func tearDown() {
        db.close()
        try? FileManager.default.removeItem(atPath: tempPath)
        super.tearDown()
    }

    func testSaveAndList() throws {
        try db.saveCommitTemplate(name: "test1", body: "{{summary_line}}")
        XCTAssertEqual(db.commitTemplates.count, 1)
        XCTAssertEqual(db.commitTemplates.first?.name, "test1")
        XCTAssertEqual(db.commitTemplates.first?.body, "{{summary_line}}")
        XCTAssertFalse(db.commitTemplates.first?.isActive ?? true)
    }

    func testUpsert() throws {
        try db.saveCommitTemplate(name: "test1", body: "v1")
        try db.saveCommitTemplate(name: "test1", body: "v2")
        XCTAssertEqual(db.commitTemplates.count, 1)
        XCTAssertEqual(db.commitTemplates.first?.body, "v2")
    }

    func testSetActive() throws {
        try db.saveCommitTemplate(name: "a", body: "body-a")
        try db.saveCommitTemplate(name: "b", body: "body-b")
        try db.setActiveTemplate(name: "a")

        XCTAssertEqual(db.activeTemplate?.name, "a")
        XCTAssertTrue(db.commitTemplates.first(where: { $0.name == "a" })?.isActive ?? false)
        XCTAssertFalse(db.commitTemplates.first(where: { $0.name == "b" })?.isActive ?? true)
    }

    func testSetActiveSwitches() throws {
        try db.saveCommitTemplate(name: "a", body: "body-a")
        try db.saveCommitTemplate(name: "b", body: "body-b")
        try db.setActiveTemplate(name: "a")
        try db.setActiveTemplate(name: "b")

        XCTAssertEqual(db.activeTemplate?.name, "b")
        XCTAssertFalse(db.commitTemplates.first(where: { $0.name == "a" })?.isActive ?? true)
    }

    func testDelete() throws {
        try db.saveCommitTemplate(name: "test1", body: "body")
        try db.deleteCommitTemplate(name: "test1")
        XCTAssertTrue(db.commitTemplates.isEmpty)
        XCTAssertNil(db.activeTemplate)
    }

    func testDeleteActiveTemplate() throws {
        try db.saveCommitTemplate(name: "a", body: "body-a")
        try db.setActiveTemplate(name: "a")
        try db.deleteCommitTemplate(name: "a")
        XCTAssertNil(db.activeTemplate)
    }
}
