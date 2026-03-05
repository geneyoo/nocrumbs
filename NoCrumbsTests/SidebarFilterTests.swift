import XCTest
@testable import NoCrumbs

final class SidebarFilterTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvent(
        id: UUID = UUID(),
        sessionID: String = "session-1",
        promptText: String? = "some prompt",
        sequenceID: String? = "seq-1"
    ) -> PromptEvent {
        PromptEvent(
            id: id,
            sessionID: sessionID,
            projectPath: "/tmp/test",
            promptText: promptText,
            timestamp: Date(),
            vcs: nil,
            baseCommitHash: nil,
            sequenceID: sequenceID
        )
    }

    private func makeFileChange(eventID: UUID) -> [FileChange] {
        [FileChange(id: UUID(), eventID: eventID, filePath: "/tmp/test/file.swift", toolName: "Write", timestamp: Date(), description: nil)]
    }

    // MARK: - isEmptyPrompt

    func testEmptyPromptDetection() {
        XCTAssertTrue(makeEvent(promptText: nil).isEmptyPrompt)
        XCTAssertTrue(makeEvent(promptText: "").isEmptyPrompt)
        XCTAssertTrue(makeEvent(promptText: "  \n  ").isEmptyPrompt)
        XCTAssertTrue(makeEvent(promptText: "\t\n").isEmptyPrompt)
    }

    func testNonEmptyPromptDetection() {
        XCTAssertFalse(makeEvent(promptText: "fix bug").isEmptyPrompt)
        XCTAssertFalse(makeEvent(promptText: " hello ").isEmptyPrompt)
        XCTAssertFalse(makeEvent(promptText: "a").isEmptyPrompt)
    }

    // MARK: - collapseNoChangePrompts

    func testAllNoChange_CollapsesAllButLatest() {
        // 5 events, none with changes. Latest (index 0) always shows.
        let events = (0..<5).map { _ in makeEvent() }
        let result = SidebarFilter.collapseNoChangePrompts(events, fileChangesCache: [:], sessionID: "s1")

        // Should be: [event(latest), collapsed(4)]
        XCTAssertEqual(result.count, 2)
        if case .event(let e) = result[0] {
            XCTAssertEqual(e.id, events[0].id, "Latest event always visible")
        } else {
            XCTFail("Expected event for latest")
        }
        if case .collapsed(let events, _) = result[1] {
            XCTAssertEqual(events.count,4)
        } else {
            XCTFail("Expected collapsed group")
        }
    }

    func testChangeEvents_AlwaysVisible() {
        // 6 events: index 0 (latest), 2, 4 have changes
        let events = (0..<6).map { _ in makeEvent() }
        var cache: [UUID: [FileChange]] = [:]
        cache[events[0].id] = makeFileChange(eventID: events[0].id)
        cache[events[2].id] = makeFileChange(eventID: events[2].id)
        cache[events[4].id] = makeFileChange(eventID: events[4].id)

        let result = SidebarFilter.collapseNoChangePrompts(events, fileChangesCache: cache, sessionID: "s1")

        let visibleEvents = result.compactMap { item -> PromptEvent? in
            if case .event(let e) = item { return e }
            return nil
        }
        // Must include events 0, 2, 4
        XCTAssertTrue(visibleEvents.contains { $0.id == events[0].id })
        XCTAssertTrue(visibleEvents.contains { $0.id == events[2].id })
        XCTAssertTrue(visibleEvents.contains { $0.id == events[4].id })
    }

    func testNoiseBetweenChanges_Collapsed() {
        // Pattern: [change, noise, noise, change, noise]
        let events = (0..<5).map { _ in makeEvent() }
        var cache: [UUID: [FileChange]] = [:]
        cache[events[0].id] = makeFileChange(eventID: events[0].id)
        cache[events[3].id] = makeFileChange(eventID: events[3].id)

        let result = SidebarFilter.collapseNoChangePrompts(events, fileChangesCache: cache, sessionID: "s1")

        // Expected: [event(0), collapsed(2), event(3), collapsed(1)]
        XCTAssertEqual(result.count, 4)
        if case .event(let e) = result[0] { XCTAssertEqual(e.id, events[0].id) }
        else { XCTFail("Expected event at 0") }
        if case .collapsed(let events, _) = result[1] { XCTAssertEqual(events.count,2) }
        else { XCTFail("Expected collapsed(2) at 1") }
        if case .event(let e) = result[2] { XCTAssertEqual(e.id, events[3].id) }
        else { XCTFail("Expected event at 2") }
        if case .collapsed(let events, _) = result[3] { XCTAssertEqual(events.count,1) }
        else { XCTFail("Expected collapsed(1) at 3") }
    }

    func testAllHaveChanges_NoCollapsing() {
        let events = (0..<4).map { _ in makeEvent() }
        var cache: [UUID: [FileChange]] = [:]
        for event in events { cache[event.id] = makeFileChange(eventID: event.id) }

        let result = SidebarFilter.collapseNoChangePrompts(events, fileChangesCache: cache, sessionID: "s1")

        XCTAssertEqual(result.count, 4)
        for item in result {
            if case .event = item {} else { XCTFail("Expected all events, no collapsing") }
        }
    }

    func testSingleEvent_NeverCollapsed() {
        let event = makeEvent()
        let result = SidebarFilter.collapseNoChangePrompts([event], fileChangesCache: [:], sessionID: "s1")

        XCTAssertEqual(result.count, 1)
        if case .event(let e) = result[0] {
            XCTAssertEqual(e.id, event.id)
        } else {
            XCTFail("Single event should pass through")
        }
    }

    func testEmpty_ReturnsEmpty() {
        let result = SidebarFilter.collapseNoChangePrompts([], fileChangesCache: [:], sessionID: "s1")
        XCTAssertTrue(result.isEmpty)
    }

    func testCollapsedGroupKeys_AreUnique() {
        // Multiple collapsed groups should have distinct keys
        let events = (0..<7).map { _ in makeEvent() }
        var cache: [UUID: [FileChange]] = [:]
        cache[events[0].id] = makeFileChange(eventID: events[0].id)
        cache[events[3].id] = makeFileChange(eventID: events[3].id)

        let result = SidebarFilter.collapseNoChangePrompts(events, fileChangesCache: cache, sessionID: "s1")

        let keys = result.compactMap { item -> String? in
            if case .collapsed(_, let key) = item { return key }
            return nil
        }
        XCTAssertEqual(keys.count, Set(keys).count, "Group keys must be unique")
    }
}
