import XCTest
@testable import TermPet

/// "GPT 앱 채팅": ChatGPT 앱 로그 줄 → 일반 채팅 신호 (실제 로그에서 가져온 줄)
final class ChatGPTAppLogTests: XCTestCase {
    let refetch = "2026-11-11T07:58:12.569Z info [electron-message-handler] chatgpt_conversation_refetch_completed asyncStatus=null conversationId=6af42003-045c-83ee-8b87-4716e0b39754 currentNodeApplied=true mappingSize=9 reason=explicit_update rendererWebContentsId=1"
    let ignored = "2026-11-11T07:55:17.420Z info [electron-message-handler] chatgpt_conversation_update_ignored conversationId=6af3fa1e-3e00-83ee-8ede-39fb3d94acbd reason=conversation_not_loaded rendererWebContentsId=1 updateType=completed"
    let shown = "2026-11-11T07:55:22.054Z info [electron-message-handler] [desktop-notifications] show turn-complete conversationId=6af3fa2c-4db4-8191-82cc-eea3cd30808e rendererWebContentsId=1"
    let started = "2026-11-11T07:54:44.856Z error [electron-message-handler] Received turn/started for unknown conversation conversationId=6af3fa2c-4db4-8191-82cc-eea3cd30808e rendererWebContentsId=1"

    func testParsesCompletionAndStart() {
        XCTAssertEqual(ChatGPTAppLog.parse(refetch), .completed(conversationId: "6af42003-045c-83ee-8b87-4716e0b39754"))
        XCTAssertEqual(ChatGPTAppLog.parse(ignored), .completedElsewhere(conversationId: "6af3fa1e-3e00-83ee-8ede-39fb3d94acbd"))
        XCTAssertEqual(ChatGPTAppLog.parse(shown), .completed(conversationId: "6af3fa2c-4db4-8191-82cc-eea3cd30808e"))
        XCTAssertEqual(ChatGPTAppLog.parse(started), .started(conversationId: "6af3fa2c-4db4-8191-82cc-eea3cd30808e"))
    }

    func testIgnoresCodexThreadsAndOtherLines() {
        // Codex 대화는 notify가 알려 주므로 건너뜀 (UUID v7)
        XCTAssertNil(ChatGPTAppLog.parse("… [desktop-notifications] show turn-complete conversationId=01a1c98a-03f6-7ea0-a0a2-ae7a0bf1510f rendererWebContentsId=1"))
        XCTAssertNil(ChatGPTAppLog.parse("… Received turn/started for unknown conversation conversationId=01a1c98a-1b41-7463-adb9-2ad05b1eada2"))
        // 이 앱에서 그 대화를 열었다는 줄은 알림이 아니라 '여기서 쓰는 대화' 표시
        let id = "6af42003-045c-83ee-8b87-4716e0b39754"
        XCTAssertEqual(ChatGPTAppLog.parse("… chatgpt_conversation_refetch_started conversationId=\(id) reason=explicit_update"), .seen(conversationId: id))
        XCTAssertEqual(ChatGPTAppLog.parse("… chatgpt_conversation_refetch_completed conversationId=\(id) reason=focus"), .seen(conversationId: id))
        XCTAssertEqual(ChatGPTAppLog.parse("… IAB_LIFECYCLE received browser sidebar owner sync ownerRoutePath=/c/\(id) windowId=1"), .seen(conversationId: id))
        // 서버가 밀어 준 소식·놓친 메시지 따라잡기는 다른 기기에서 한 대화에도 찍힌다 → 연 것으로 안 친다
        XCTAssertNil(ChatGPTAppLog.parse("… chatgpt_conversation_update_ignored conversationId=\(id) reason=conversation_not_loaded updateType=refetch"))
        XCTAssertNil(ChatGPTAppLog.parse("… chatgpt_conversation_refetch_completed conversationId=\(id) reason=missed_messages"))
        XCTAssertNil(ChatGPTAppLog.parse("… [desktop-notifications] show turn-complete conversationId=null"))
        XCTAssertTrue(ChatGPTAppLog.isCodexThread("019f20ee-0994-7022-876d-d68d432affce"))
        XCTAssertFalse(ChatGPTAppLog.isCodexThread("6af42003-045c-83ee-8b87-4716e0b39754"))
    }

    func testReducerMakesChatGPTEventsOncePerTurn() {
        var r = ChatGPTAppLog.Reducer()
        let t0 = Date(timeIntervalSince1970: 1000)
        let e = r.event(for: .completed(conversationId: "c1"), now: t0)
        XCTAssertEqual(e?.kind, .done)
        XCTAssertEqual(e?.projectName, "ChatGPT")
        XCTAssertEqual(e?.hostBundleId, "com.openai.codex")
        // 같은 턴의 다른 줄(앱 알림)은 한 번만
        XCTAssertNil(r.event(for: .completed(conversationId: "c1"), now: t0.addingTimeInterval(5)))
        XCTAssertNotNil(r.event(for: .completed(conversationId: "c2"), now: t0.addingTimeInterval(5)))
        XCTAssertNotNil(r.event(for: .completed(conversationId: "c1"), now: t0.addingTimeInterval(60)))
        XCTAssertEqual(r.event(for: .started(conversationId: "c1"), now: t0.addingTimeInterval(61))?.kind, .working)
    }

    /// 휴대폰·웹에서 한 대화가 끝나도 맥 앱 로그에 '안 열린 대화 완료'가 찍힌다 → 이 앱에서 연 대화만 알린다
    func testCompletionOfConversationNotOpenedHereIsSilent() {
        var r = ChatGPTAppLog.Reducer()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(r.event(for: .completedElsewhere(conversationId: "phone"), now: t0))
        XCTAssertNil(r.event(for: .completedElsewhere(conversationId: "phone"), now: t0.addingTimeInterval(300)))
        // 여기서 열었던 대화면(물어 놓고 다른 대화로 넘어감) 알린다
        XCTAssertNil(r.event(for: .seen(conversationId: "here"), now: t0))
        XCTAssertEqual(r.event(for: .completedElsewhere(conversationId: "here"), now: t0.addingTimeInterval(60))?.kind, .done)
        // 연 지 오래됐으면 다시 조용히
        XCTAssertNil(r.event(for: .completedElsewhere(conversationId: "here"), now: t0.addingTimeInterval(60 + ChatGPTAppLog.localWindow)))
        // 여기서 끝난 답도 '연 대화'로 친다
        XCTAssertNotNil(r.event(for: .completed(conversationId: "c3"), now: t0))
        XCTAssertNotNil(r.event(for: .completedElsewhere(conversationId: "c3"), now: t0.addingTimeInterval(120)))
    }

    func testGPTChatClickJustActivatesApp() {
        var e = PetEvent(source: .codex, kind: .done, sessionId: "6af42003-045c-83ee-8b87-4716e0b39754", hostBundleId: "com.openai.codex")
        XCTAssertEqual(FocusAction.plan(for: e) { $0 }, .activate(bundleId: "com.openai.codex"))
        e.sessionId = "01a1c98a-03f6-7ea0-a0a2-ae7a0bf1510f"
        XCTAssertEqual(FocusAction.plan(for: e) { $0 },
                       .openURL(url: "codex://threads/01a1c98a-03f6-7ea0-a0a2-ae7a0bf1510f", bundleId: "com.openai.codex"))
    }

    func testLogDirectoryUsesUTCDate() {
        // 한국 시간 11월 12일 오전 8시 = UTC 11월 11일 23시
        let date = ISO8601DateFormatter().date(from: "2026-11-11T23:00:00Z")!
        XCTAssertEqual(ChatGPTAppLog.logDirectory(home: URL(fileURLWithPath: "/Users/me"), date: date).path,
                       "/Users/me/Library/Logs/com.openai.codex/2026/11/11")
    }

    func testToggleOnlyFlipsPreference() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-gpt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let defaults = UserDefaults(suiteName: "termpet-test-\(UUID().uuidString)")!
        let manager = IntegrationManager(home: home, defaults: defaults)
        XCTAssertFalse(manager.isAvailable(.chatgptApp))
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Logs/com.openai.codex"), withIntermediateDirectories: true)
        XCTAssertTrue(manager.isAvailable(.chatgptApp))
        XCTAssertEqual(manager.installed[.chatgptApp], false)
        XCTAssertNil(try manager.toggle(.chatgptApp))
        XCTAssertEqual(manager.installed[.chatgptApp], true)
        try manager.toggle(.chatgptApp)
        XCTAssertEqual(manager.installed[.chatgptApp], false)
    }
}
