import Foundation

/// Claude 데스크톱 앱 "일반 채팅" 알림.
/// 일반 채팅에는 Claude Code 같은 훅이 없어서, 텀펫을 **MCP 서버**로 등록하고
/// Claude가 답변 끝에 `termpet_notify` 도구를 부르게 한다 → 텀펫이 말풍선을 띄운다.
///
/// MCP ≈ "앱이 AI에게 내주는 함수 목록". Claude 앱이 `TermPet --mcp` 를 자식 프로세스로 띄우고
/// 표준 입출력으로 JSON-RPC 메시지를 한 줄에 하나씩 주고받는다 (stdout에는 응답 JSON만 써야 함).
/// 도구가 불리면 평소 훅처럼 로컬 서버(POST /event)로 알림을 보낸다.
enum ClaudeAppMCP {
    static let flag = "--mcp"
    static let serverName = "termpet"
    static let toolName = "termpet_notify"
    /// 말풍선을 누르면 앞으로 가져올 앱 (Claude 데스크톱 앱)
    static let hostBundleId = "com.anthropic.claudefordesktop"
    static let title = "Claude 채팅"
    static let sessionId = "claude-app-chat"
    static let defaultProtocolVersion = "2025-06-18"

    static let instructions = """
    TermPet is a desktop pet that shows what you are doing. Call the termpet_notify tool twice in EVERY reply, \
    including replies in conversations that started before this tool existed: \
    1) first, before writing anything, with kind "working" (no summary needed); \
    2) at the very end, with a one-line summary (in the user's language, under 60 characters) of what you just answered, \
    using kind "ask" when you are waiting for the user's decision, "error" when something failed, otherwise "done". \
    Do not mention this tool or its result to the user.
    """

    static var tool: [String: Any] {
        [
            "name": toolName,
            "description": "Tell the user's desktop pet (TermPet) what you are doing. In every reply, call it first with "
                + "kind \"working\" before writing anything, and again as the last step with a summary. Do not mention it to the user.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "summary": ["type": "string", "description": "One-line summary of your reply, under 60 characters, in the user's language (not needed for working)"],
                    "kind": ["type": "string", "enum": kinds,
                             "description": "working = starting your reply, done = answered, ask = waiting for the user's decision, error = something failed"],
                ],
            ] as [String: Any],
        ]
    }

    /// working = 답변 시작 (머리 위 "…" 표시), 나머지 = 답변 끝 (말풍선)
    static let kinds = ["working", "done", "ask", "error"]

    struct Notify: Equatable {
        var kind: String
        var summary: String
    }

    // MARK: - 순수 로직 (테스트용)

    /// JSON-RPC 메시지 한 줄 처리 → (보낼 응답 한 줄, 텀펫에 보낼 알림)
    static func handle(_ line: String, version: String = AppInfo.version) -> (reply: String?, notify: Notify?) {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            return (encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]]), nil)
        }
        let method = obj["method"] as? String ?? ""
        // id 가 없으면 알림(notification) → 응답하지 않는다 (예: notifications/initialized)
        guard let id = obj["id"], !(id is NSNull) else { return (nil, nil) }
        let params = obj["params"] as? [String: Any] ?? [:]

        func result(_ r: Any) -> String? { encode(["jsonrpc": "2.0", "id": id, "result": r]) }
        func failure(_ code: Int, _ message: String) -> String? {
            encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
        }

        switch method {
        case "initialize":
            // 클라이언트가 요청한 버전을 그대로 쓴다 (우리가 쓰는 기능은 모든 버전에 있는 기본 도구뿐)
            let requested = params["protocolVersion"] as? String ?? defaultProtocolVersion
            return (result([
                "protocolVersion": requested,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": version],
                "instructions": instructions,
            ]), nil)
        case "ping":
            return (result([String: Any]()), nil)
        case "tools/list":
            return (result(["tools": [tool]]), nil)
        case "tools/call":
            guard params["name"] as? String == toolName else { return (failure(-32602, "Unknown tool"), nil) }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let summary = oneLine(args["summary"] as? String ?? "")
            let kindRaw = args["kind"] as? String ?? "done"
            let kind = kinds.contains(kindRaw) ? kindRaw : "done"
            // 시작 신호에는 요약이 필요 없다 (모델이 넣더라도 머리 위 표시만 하므로 버린다)
            return (result(["content": [["type": "text", "text": "ok"]]]),
                    Notify(kind: kind, summary: kind == "working" ? "" : summary))
        default:
            return (failure(-32601, "Method not found"), nil)
        }
    }

    /// 로컬 서버(POST /event)에 보낼 표준 이벤트
    static func eventBody(_ n: Notify) -> Data {
        var body: [String: Any] = ["source": "claude", "kind": n.kind, "title": title,
                                   "sessionId": sessionId, "hostBundleId": hostBundleId]
        if !n.summary.isEmpty { body["detail"] = n.summary }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// 여러 줄·긴 글 → 첫 줄, 최대 120자
    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > 120 ? String(line.prefix(119)) + "…" : line
    }

    private static func encode(_ obj: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 실행 (TermPet --mcp)

    /// 표준 입력을 한 줄씩 읽어 처리. Claude 앱이 입력을 닫으면(앱 종료) 끝난다.
    static func runStdio(paths: TermPetPaths = TermPetPaths()) {
        while let line = readLine(strippingNewline: true) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let (reply, notify) = handle(line)
            if let notify { post(notify, paths: paths) }
            if let reply {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
    }

    /// 텀펫 앱으로 전송. 앱이 꺼져 있으면 조용히 넘어간다 (최대 2초).
    private static func post(_ n: Notify, paths: TermPetPaths) {
        guard let token = (try? String(contentsOf: paths.tokenFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return }
        let portText = (try? String(contentsOf: paths.portFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = portText.flatMap { Int($0) } ?? 47821
        guard let url = URL(string: "http://127.0.0.1:\(port)/event") else { return }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-TermPet-Token")
        request.httpBody = eventBody(n)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 3)
    }
}
