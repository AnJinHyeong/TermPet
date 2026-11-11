import XCTest
@testable import TermPet

final class EventDecoderTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: 표준 이벤트

    func testStandardFullEvent() throws {
        let e = try EventDecoder.decodeStandard(data("""
        {"source":"claude","kind":"done","message":"hi","cwd":"/Users/me/fitin","sessionId":"s",
         "transcriptPath":"/t.jsonl","exitCode":0,"durationSec":42,"hostBundleId":"b","termProgram":"vscode"}
        """))
        XCTAssertEqual(e.source, .claude)
        XCTAssertEqual(e.kind, .done)
        XCTAssertEqual(e.message, "hi")
        XCTAssertEqual(e.projectName, "fitin")
        XCTAssertEqual(e.durationSec, 42)
        XCTAssertEqual(e.hostBundleId, "b")
    }

    func testShellKindInferredFromExitCode() throws {
        let ok = try EventDecoder.decodeStandard(data(#"{"source":"shell","exitCode":0,"command":"make"}"#))
        XCTAssertEqual(ok.kind, .done)
        let fail = try EventDecoder.decodeStandard(data(#"{"source":"shell","exitCode":2,"command":"make\nall"}"#))
        XCTAssertEqual(fail.kind, .error)
        XCTAssertEqual(fail.detail, "make")
    }

    func testStandardMissingOrInvalidFields() {
        XCTAssertThrowsError(try EventDecoder.decodeStandard(data(#"{"kind":"done"}"#)))
        XCTAssertThrowsError(try EventDecoder.decodeStandard(data(#"{"source":"shell"}"#)))
        XCTAssertThrowsError(try EventDecoder.decodeStandard(data(#"{"source":"nope","kind":"done"}"#)))
        XCTAssertThrowsError(try EventDecoder.decodeStandard(data(#"{"source":"shell","kind":"meh"}"#)))
        XCTAssertThrowsError(try EventDecoder.decodeStandard(data("[1,2]")))
    }

    func testWrongFieldTypesAreTolerated() throws {
        let e = try EventDecoder.decodeStandard(data(#"{"source":"shell","kind":"done","exitCode":"3","durationSec":true,"cwd":5}"#))
        XCTAssertEqual(e.exitCode, 3)
        XCTAssertNil(e.durationSec)
        XCTAssertNil(e.cwd)
    }

    func testContextFillsHostWhenBodyLacksIt() throws {
        let e = try EventDecoder.decodeStandard(data(#"{"source":"shell","kind":"done"}"#),
                                                context: .init(hostBundleId: "h", termProgram: "t"))
        XCTAssertEqual(e.hostBundleId, "h")
        XCTAssertEqual(e.termProgram, "t")
    }

    // MARK: Claude Code 훅

    func testClaudeStop() throws {
        let e = try EventDecoder.decodeClaudeHook(data("""
        {"session_id":"abc123","transcript_path":"/Users/me/.claude/projects/x/abc.jsonl","cwd":"/Users/me/fitin",
         "permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false,
         "last_assistant_message":"\\n## I've completed the refactoring.\\nHere's a summary...","background_tasks":[]}
        """))
        XCTAssertEqual(e.source, .claude)
        XCTAssertEqual(e.kind, .done)
        XCTAssertEqual(e.sessionId, "abc123")
        XCTAssertEqual(e.transcriptPath, "/Users/me/.claude/projects/x/abc.jsonl")
        XCTAssertEqual(e.detail, "I've completed the refactoring.")
        XCTAssertNil(e.message)
        XCTAssertEqual(e.mood, .happy)
    }

    func testClaudeStopWithMinimalFields() throws {
        let e = try EventDecoder.decodeClaudeHook(data(#"{"hook_event_name":"Stop"}"#))
        XCTAssertEqual(e.kind, .done)
        XCTAssertNil(e.cwd)
        XCTAssertNil(e.detail)
    }

    func testClaudeNotificationPermission() throws {
        let e = try EventDecoder.decodeClaudeHook(data("""
        {"session_id":"abc123","cwd":"/p","hook_event_name":"Notification","message":"Claude needs your permission",
         "title":"Permission needed","notification_type":"permission_prompt"}
        """))
        XCTAssertEqual(e.kind, .ask)
        XCTAssertEqual(e.message, "권한 확인이 필요해요") // 한국어로
        XCTAssertEqual(e.notificationType, "permission_prompt")
        XCTAssertFalse(e.isIdlePrompt)
    }

    func testClaudeNotificationWithoutTypeIsAsk() throws {
        let e = try EventDecoder.decodeClaudeHook(data(#"{"hook_event_name":"Notification","message":"waiting"}"#))
        XCTAssertEqual(e.kind, .ask)
    }

    func testClaudeIdlePrompt() throws {
        let e = try EventDecoder.decodeClaudeHook(data(#"{"hook_event_name":"Notification","notification_type":"idle_prompt"}"#))
        XCTAssertTrue(e.isIdlePrompt)
    }

    func testClaudeIgnoredEvents() {
        for body in [#"{"hook_event_name":"Notification","notification_type":"auth_success"}"#,
                     #"{"hook_event_name":"SubagentStart"}"#,
                     #"{}"#] {
            XCTAssertThrowsError(try EventDecoder.decodeClaudeHook(data(body))) { error in
                guard case EventDecoder.DecodeError.ignored = error else { return XCTFail("\(error)") }
            }
        }
    }

    // MARK: Codex

    func testCodexTurnComplete() throws {
        let e = try EventDecoder.decodeCodexNotify(data(#"{"type":"agent-turn-complete","last-assistant-message":"Done.","cwd":"/p/app"}"#))
        XCTAssertEqual(e.source, .codex)
        XCTAssertEqual(e.kind, .done)
        XCTAssertEqual(e.detail, "Done.")
        XCTAssertThrowsError(try EventDecoder.decodeCodexNotify(data(#"{"type":"other"}"#)))
    }

    /// ChatGPT(Codex) 앱이 대화 제목을 지으려고 돌리는 작업의 알림은 무시 (말풍선에 JSON이 그대로 보이던 문제)
    func testCodexTitleGenerationIgnored() throws {
        let title = #"{\"title\":\"텀펫 알람 기능 추가\",\"description\":\"알람 기능 검토\"}"#
        XCTAssertThrowsError(try EventDecoder.decodeCodexNotify(data(#"{"type":"agent-turn-complete","last-assistant-message":""# + title + #""}"#)))
        let e = try EventDecoder.decodeCodexNotify(data(#"{"type":"agent-turn-complete","last-assistant-message":"{괄호로 시작하는 답}"}"#))
        XCTAssertEqual(e.detail, "{괄호로 시작하는 답}")
    }

    /// Codex 훅: 질문을 보내면 "작업 중", 그 밖의 훅은 무시
    func testCodexPromptHookMeansWorking() throws {
        let e = try EventDecoder.decodeCodexNotify(data(#"{"hook_event_name":"UserPromptSubmit","session_id":"t1","cwd":"/p/app","prompt":"hi"}"#),
                                                   context: .init(termProgram: "iTerm.app"))
        XCTAssertEqual(e.kind, .working)
        XCTAssertEqual(e.sessionId, "t1")
        XCTAssertNil(e.hostBundleId)
        XCTAssertThrowsError(try EventDecoder.decodeCodexNotify(data(#"{"hook_event_name":"Stop","session_id":"t1"}"#)))
        // notify 의 thread-id 와 같은 세션으로 묶여서 끝나면 "작업 중"이 풀린다
        let done = try EventDecoder.decodeCodexNotify(data(#"{"type":"agent-turn-complete","thread-id":"t1","cwd":"/p/app"}"#),
                                                      context: .init(termProgram: "iTerm.app"))
        XCTAssertEqual(SessionTracker.key(for: e), SessionTracker.key(for: done))
    }

    /// 터미널 밖(호스트 정보 없음) = ChatGPT 앱. 앱이 만든 임시 폴더면 제목은 "ChatGPT"
    func testCodexWithoutHostIsChatGPTApp() throws {
        let home = NSHomeDirectory()
        let e = try EventDecoder.decodeCodexNotify(data(#"{"type":"agent-turn-complete","thread-id":"t2","cwd":""# + home + #"/Documents/Codex/2026-11-11/new-chat-2"}"#))
        XCTAssertEqual(e.hostBundleId, "com.openai.codex")
        XCTAssertEqual(e.projectName, "ChatGPT")
        let project = try EventDecoder.decodeCodexNotify(data(#"{"type":"agent-turn-complete","thread-id":"t2","cwd":"/p/app"}"#))
        XCTAssertEqual(project.projectName, "app")
    }

    func testOneLineTruncates() {
        XCTAssertEqual(EventDecoder.oneLine("\n\n  **Hello**  \nworld"), "Hello")
        XCTAssertEqual(EventDecoder.oneLine(String(repeating: "a", count: 300)).count, 120)
    }
}

final class BubbleContentTests: XCTestCase {
    private var rng = SeededGenerator(seed: 1)

    func testUsesProjectNameAndRandomMessage() {
        let e = PetEvent(source: .claude, kind: .done, cwd: "/Users/me/fitin")
        let c = BubbleContent.make(for: e, using: &rng)
        XCTAssertEqual(c.title, "fitin")
        XCTAssertTrue(BubbleMessages.default.done.contains(c.body))
    }

    func testEventMessageWins() {
        let e = PetEvent(source: .claude, kind: .ask, message: "Claude needs your permission")
        let c = BubbleContent.make(for: e, using: &rng)
        XCTAssertEqual(c.body, "Claude needs your permission")
        XCTAssertEqual(c.title, "Claude Code") // cwd 없으면 소스 이름
    }

    func testCustomMessagePool() {
        let messages = BubbleMessages(done: ["야옹"], error: ["캬악"], ask: ["냥?"])
        let e = PetEvent(source: .shell, kind: .error)
        XCTAssertEqual(BubbleContent.make(for: e, messages: messages, using: &rng).body, "캬악")
    }

    func testShellDetailIncludesDuration() {
        let e = PetEvent(source: .shell, kind: .done, detail: "npm test", durationSec: 125)
        XCTAssertEqual(BubbleContent.make(for: e, using: &rng).detail, "npm test · 2분 5초")
    }

    func testFormatDuration() {
        XCTAssertEqual(BubbleContent.formatDuration(42), "42초")
        XCTAssertEqual(BubbleContent.formatDuration(120), "2분")
        XCTAssertEqual(BubbleContent.formatDuration(3600), "1시간")
        XCTAssertEqual(BubbleContent.formatDuration(3720), "1시간 2분")
    }

    func testProjectNameEdgeCases() {
        XCTAssertNil(PetEvent(source: .shell, kind: .done, cwd: "/").projectName)
        XCTAssertNil(PetEvent(source: .shell, kind: .done, cwd: "").projectName)
        XCTAssertEqual(PetEvent(source: .shell, kind: .done, cwd: "/a/b/").projectName, "b")
    }
}

final class OneLineMarkdownTests: XCTestCase {
    func testStripsMarkdownEmphasis() {
        XCTAssertEqual(EventDecoder.oneLine("스크린샷 덕분에 **알림이 도착한 것**도 `확인`했습니다."),
                       "스크린샷 덕분에 알림이 도착한 것도 확인했습니다.")
        XCTAssertEqual(EventDecoder.oneLine("- 목록 항목"), "목록 항목")
        XCTAssertEqual(EventDecoder.oneLine("> 인용"), "인용")
    }

    func testNotificationMessagesInKorean() {
        XCTAssertEqual(EventDecoder.koreanNotification("Claude is waiting for your input", type: "idle_prompt"), "입력을 기다리고 있어요")
        XCTAssertEqual(EventDecoder.koreanNotification("Claude needs your permission to use Bash", type: "permission_prompt"),
                       "Bash 사용을 허락해 줄래요?")
        XCTAssertEqual(EventDecoder.koreanNotification("Claude needs your permission", type: nil), "권한 확인이 필요해요")
        XCTAssertNil(EventDecoder.koreanNotification(nil, type: "idle_prompt")) // 원문 없으면 캐릭터 대사
        XCTAssertEqual(EventDecoder.koreanNotification("Some new english text", type: "elicitation_dialog"), "선택해 줄 게 있어요")
        XCTAssertEqual(EventDecoder.koreanNotification("이미 한국어", type: "idle_prompt"), "이미 한국어")
        XCTAssertEqual(EventDecoder.koreanNotification("Unknown", type: nil), "Unknown")
    }
}

final class EventClampTests: XCTestCase {
    func testLongTextIsClamped() {
        var e = PetEvent(source: .claude, kind: .done, message: String(repeating: "가", count: 5000))
        e.detail = "짧음"
        e.clampTextFields()
        XCTAssertEqual(e.message?.count, PetEvent.maxTextLength)
        XCTAssertTrue(e.message!.hasSuffix("…"))
        XCTAssertEqual(e.detail, "짧음")
    }
}
