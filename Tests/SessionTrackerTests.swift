import XCTest
@testable import TermPet

final class SessionTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func claude(_ kind: PetEvent.Kind, sid: String = "s1", cwd: String? = "/work/fitin",
                        type: String? = nil, tool: String? = nil) -> PetEvent {
        PetEvent(source: .claude, kind: kind, detail: tool, cwd: cwd, sessionId: sid,
                 hostBundleId: cwd == nil ? nil : "com.todesktop.cursor", notificationType: type)
    }

    func testLifecycleWorkingWaitingDoneEnded() {
        var t = SessionTracker()
        t.apply(claude(.working), now: t0)
        XCTAssertEqual(t.sessions["claude:s1"]?.state, .working)
        XCTAssertEqual(t.sessions["claude:s1"]?.projectName, "fitin")
        XCTAssertEqual(t.workingCount, 1)

        t.apply(claude(.ask, type: "permission_prompt"), now: t0 + 30)
        XCTAssertEqual(t.waitingCount, 1)
        XCTAssertEqual(t.sessions["claude:s1"]?.since, t0 + 30)

        // 도구 실행 신호(cwd 없음)가 와도 프로젝트·호스트 정보는 유지
        t.apply(claude(.working, cwd: nil, tool: "Bash"), now: t0 + 60)
        XCTAssertEqual(t.sessions["claude:s1"]?.state, .working)
        XCTAssertEqual(t.sessions["claude:s1"]?.focusEvent.cwd, "/work/fitin")
        XCTAssertEqual(t.sessions["claude:s1"]?.focusEvent.hostBundleId, "com.todesktop.cursor")

        // 같은 상태가 이어지면 시작 시각은 그대로
        t.apply(claude(.working, cwd: nil, tool: "Read"), now: t0 + 90)
        XCTAssertEqual(t.sessions["claude:s1"]?.since, t0 + 60)

        t.apply(claude(.done), now: t0 + 120)
        XCTAssertEqual(t.sessions["claude:s1"]?.state, .done)
        t.apply(claude(.ended), now: t0 + 130)
        XCTAssertTrue(t.sessions.isEmpty)
    }

    func testIdlePromptIsNotWaiting() {
        var t = SessionTracker()
        t.apply(claude(.done), now: t0)
        t.apply(claude(.ask, type: "idle_prompt"), now: t0 + 60)
        XCTAssertEqual(t.sessions["claude:s1"]?.state, .done)
        XCTAssertEqual(t.waitingCount, 0)
    }

    func testEventsWithoutSessionAreIgnored() {
        var t = SessionTracker()
        XCTAssertNil(t.apply(PetEvent(source: .shell, kind: .error), now: t0))
        XCTAssertTrue(t.sessions.isEmpty)
    }

    func testPruneDropsStaleWorkingAndOldFinished() {
        var t = SessionTracker()
        t.apply(claude(.working, sid: "a"), now: t0)          // Esc로 중단돼 Stop이 안 온 세션
        t.apply(claude(.done, sid: "b"), now: t0)
        t.apply(claude(.working, sid: "c"), now: t0 + 14 * 60)
        XCTAssertFalse(t.prune(now: t0 + 5 * 60))
        XCTAssertTrue(t.prune(now: t0 + 15 * 60 + 1))
        XCTAssertEqual(Set(t.sessions.keys), ["claude:c"])
    }

    func testOrderingWaitingFirst() {
        var t = SessionTracker()
        t.apply(claude(.done, sid: "d"), now: t0 + 3)
        t.apply(claude(.working, sid: "w"), now: t0 + 2)
        t.apply(claude(.ask, sid: "q", type: "permission_prompt"), now: t0 + 1)
        XCTAssertEqual(t.ordered.map(\.id), ["claude:q", "claude:w", "claude:d"])
    }

    func testBadgePriority() {
        XCTAssertEqual(PetBadge.pick(waiting: 1, working: 2, hasUnread: true), .waiting(1))
        XCTAssertEqual(PetBadge.pick(waiting: 0, working: 2, hasUnread: true), .unread)
        XCTAssertEqual(PetBadge.pick(waiting: 0, working: 2, hasUnread: false), .working(2))
        XCTAssertEqual(PetBadge.pick(waiting: 0, working: 0, hasUnread: false), .none)
    }
}

final class ProgressEventDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> PetEvent {
        try EventDecoder.decodeClaudeHook(Data(json.utf8))
    }

    func testProgressHooks() throws {
        XCTAssertEqual(try decode(#"{"hook_event_name":"UserPromptSubmit","session_id":"s","prompt":"hi","cwd":"/p"}"#).kind, .working)
        let tool = try decode(#"{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash"}"#)
        XCTAssertEqual(tool.kind, .working)
        XCTAssertEqual(tool.detail, "Bash")
        XCTAssertFalse(tool.isNotification)
        XCTAssertEqual(try decode(#"{"hook_event_name":"SessionEnd","session_id":"s","reason":"clear"}"#).kind, .ended)
        XCTAssertTrue(try decode(#"{"hook_event_name":"Stop","session_id":"s"}"#).isNotification)
    }
}

final class QuietModeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testDecision() {
        XCTAssertTrue(QuietMode.isQuiet(now: now, manualUntil: now + 10, duringMeetings: false, micInUse: false))
        XCTAssertFalse(QuietMode.isQuiet(now: now, manualUntil: now - 1, duringMeetings: false, micInUse: true))
        XCTAssertTrue(QuietMode.isQuiet(now: now, manualUntil: nil, duringMeetings: true, micInUse: true))
        XCTAssertFalse(QuietMode.isQuiet(now: now, manualUntil: nil, duringMeetings: true, micInUse: false))
    }

    func testManualExpiresAndMeetingFollowsMic() {
        let defaults = UserDefaults(suiteName: "quiet-\(UUID().uuidString)")!
        let quiet = QuietMode(defaults: defaults)
        var mic = false
        quiet.micProbe = { mic }
        var changes: [Bool] = []
        quiet.onChange = { changes.append($0) }

        quiet.toggleManual(now: now)
        XCTAssertTrue(quiet.isQuiet)
        quiet.refresh(now: now + QuietMode.manualDuration + 1)   // 1시간 지나면 자동으로 꺼짐
        XCTAssertFalse(quiet.isQuiet)

        quiet.duringMeetings = true
        mic = true
        quiet.refresh(now: now + 7200)
        XCTAssertTrue(quiet.isQuiet)
        mic = false
        quiet.refresh(now: now + 7300)
        XCTAssertEqual(changes, [true, false, true, false])
        XCTAssertTrue(defaults.bool(forKey: QuietMode.meetingsKey)) // 설정은 저장됨
    }
}

@MainActor
final class BubbleProgressTests: XCTestCase {
    private func ask(_ sid: String) -> PetEvent {
        PetEvent(source: .claude, kind: .ask, sessionId: sid, notificationType: "permission_prompt")
    }

    func testQueueRemovesSession() {
        var q = NotificationQueue()
        let a = ask("a"), b = PetEvent(source: .claude, kind: .done, sessionId: "b")
        q.push(PetNotification(event: a, content: BubbleContent(title: "", body: "")))
        q.push(PetNotification(event: b, content: BubbleContent(title: "", body: "")))
        XCTAssertFalse(q.removeSession(of: PetEvent(source: .codex, kind: .working, sessionId: "a"))) // 다른 소스
        XCTAssertTrue(q.removeSession(of: PetEvent(source: .claude, kind: .working, sessionId: "a")))
        XCTAssertEqual(q.current?.event.sessionId, "b")
    }

    func testStickyOnlyForRealPermissionPrompts() {
        XCTAssertTrue(BubbleController.isSticky(ask("a")))
        XCTAssertFalse(BubbleController.isSticky(PetEvent(source: .claude, kind: .ask, sessionId: "a", notificationType: "idle_prompt")))
        XCTAssertFalse(BubbleController.isSticky(PetEvent(source: .claude, kind: .ask)))
        XCTAssertFalse(BubbleController.isSticky(PetEvent(source: .claude, kind: .done, sessionId: "a")))
    }

    func testQuietHoldsBubblesAndShowsWhenOver() {
        let bubble = BubbleController()
        bubble.isQuiet = true
        bubble.enqueue(PetEvent(source: .shell, kind: .done))
        XCTAssertFalse(bubble.isShowing)
        XCTAssertTrue(bubble.hasUnread)
        bubble.isQuiet = false
        XCTAssertTrue(bubble.isShowing)
        bubble.clearAll()
    }

    func testResolveHidesAnsweredPermissionBubble() {
        let bubble = BubbleController()
        bubble.enqueue(ask("a"))
        XCTAssertTrue(bubble.isShowing)
        bubble.resolve(sessionOf: PetEvent(source: .claude, kind: .working, sessionId: "a"))
        XCTAssertFalse(bubble.isShowing)
        XCTAssertFalse(bubble.hasUnread)
    }
}
