import XCTest
@testable import TermPet

final class ClaudeAppMCPTests: XCTestCase {
    private func json(_ line: String?) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data((line ?? "").utf8))) as? [String: Any] ?? [:]
    }

    func testInitializeEchoesClientVersionAndListsTool() {
        let (reply, notify) = ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#, version: "9.9")
        XCTAssertNil(notify)
        let result = json(reply)["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-11-25")
        XCTAssertNotNil((result?["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual(json(reply)["id"] as? Int, 1)

        let list = json(ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#).reply)
        XCTAssertEqual(list["id"] as? String, "a") // id 는 문자열이어도 그대로
        let tools = (list["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.first?["name"] as? String, "termpet_notify")
    }

    func testNotificationsGetNoReply() {
        let (reply, notify) = ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(reply)
        XCTAssertNil(notify)
    }

    func testToolCallReturnsOkAndNotifies() {
        let line = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"termpet_notify","arguments":{"summary":"첫 줄 요약\n둘째 줄","kind":"ask"}}}"#
        let (reply, notify) = ClaudeAppMCP.handle(line)
        XCTAssertEqual(notify, .init(kind: "ask", summary: "첫 줄 요약"))
        let content = (json(reply)["result"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        // 모르는 kind 는 done 으로
        XCTAssertEqual(ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"termpet_notify","arguments":{"summary":"x","kind":"weird"}}}"#).notify?.kind, "done")
    }

    func testUnknownMethodAndToolAndGarbage() {
        XCTAssertEqual((json(ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","id":5,"method":"server/discover"}"#).reply)["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual((json(ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope"}}"#).reply)["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertNil(ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"nope"}}"#).notify)
        XCTAssertEqual((json(ClaudeAppMCP.handle("not json").reply)["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertNotNil(json(ClaudeAppMCP.handle(#"{"jsonrpc":"2.0","id":8,"method":"ping"}"#).reply)["result"])
    }

    func testEventBodyDecodesAsClaudeChatEvent() throws {
        let event = try EventDecoder.decodeStandard(ClaudeAppMCP.eventBody(.init(kind: "done", summary: "요약")))
        XCTAssertEqual(event.source, .claude)
        XCTAssertEqual(event.kind, .done)
        XCTAssertEqual(event.detail, "요약")
        XCTAssertEqual(event.projectName, "Claude 채팅") // 말풍선 제목
        XCTAssertEqual(event.hostBundleId, "com.anthropic.claudefordesktop") // 누르면 Claude 앱으로
    }
}

final class ClaudeDesktopConfigTests: XCTestCase {
    func testInstallKeepsOtherSettingsAndServers() throws {
        let original = Data(#"{"preferences":{"x":1},"mcpServers":{"other":{"command":"/bin/other"}}}"#.utf8)
        let out = try ClaudeDesktopConfig.install(into: original, command: "/Applications/TermPet.app/Contents/MacOS/TermPet")
        let root = try JSONSerialization.jsonObject(with: out) as! [String: Any]
        XCTAssertNotNil(root["preferences"])
        let servers = root["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other"])
        let ours = servers["termpet"] as! [String: Any]
        XCTAssertEqual(ours["args"] as? [String], ["--mcp"])
        XCTAssertTrue(ClaudeDesktopConfig.isInstalled(out))
        XCTAssertFalse(ClaudeDesktopConfig.needsUpdate(out, command: "/Applications/TermPet.app/Contents/MacOS/TermPet"))
        XCTAssertTrue(ClaudeDesktopConfig.needsUpdate(out, command: "/elsewhere/TermPet"))

        let removed = try ClaudeDesktopConfig.uninstall(from: out)
        XCTAssertFalse(ClaudeDesktopConfig.isInstalled(removed))
        let after = try JSONSerialization.jsonObject(with: removed) as! [String: Any]
        XCTAssertNotNil((after["mcpServers"] as? [String: Any])?["other"])
        XCTAssertNotNil(after["preferences"])
    }

    func testMissingFileAndBrokenFile() throws {
        XCTAssertTrue(ClaudeDesktopConfig.isInstalled(try ClaudeDesktopConfig.install(into: nil, command: "/x")))
        XCTAssertThrowsError(try ClaudeDesktopConfig.install(into: Data("{oops".utf8), command: "/x"))
    }
}
