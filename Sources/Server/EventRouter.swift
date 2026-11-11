import Foundation

/// HTTP 요청 → (응답, 이벤트) 라우팅. 네트워크와 무관한 순수 로직이라 테스트가 쉽다.
/// Express 비유: `app.get('/health')`, `app.post('/event')` 핸들러 모음.
///
/// 엔드포인트
/// - `GET  /health`        → 200 "ok" (토큰 불필요, 앱 실행 여부 확인용)
/// - `POST /event`         → 표준 JSON 이벤트
/// - `POST /hook/claude`   → Claude Code 훅 stdin 원본 JSON
/// - `POST /hook/codex`    → Codex notify 원본 JSON
/// 훅 스크립트는 jq 없이 원본을 그대로 body로 보내고, 호스트 앱 정보는 헤더로 보낸다:
///   `X-TermPet-Token`, `X-TermPet-Host-Bundle`, `X-TermPet-Term-Program`
struct EventRouter {
    let token: String

    struct Outcome: Equatable {
        var response: HTTPResponse
        var event: PetEvent?
    }

    func route(_ request: HTTPRequest) -> Outcome {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return Outcome(response: .text(200, "ok"))
        case ("POST", "/event"), ("POST", "/hook/claude"), ("POST", "/hook/codex"):
            return handleEvent(request)
        case (_, "/health"), (_, "/event"), (_, "/hook/claude"), (_, "/hook/codex"):
            return Outcome(response: .text(405, "method not allowed"))
        default:
            return Outcome(response: .text(404, "not found"))
        }
    }

    private func handleEvent(_ request: HTTPRequest) -> Outcome {
        // 브라우저가 보낸 요청은 Origin 헤더가 붙는다 → 웹페이지의 localhost 공격 차단
        if request.header("origin") != nil {
            return Outcome(response: .text(403, "forbidden"))
        }
        guard let given = request.header("x-termpet-token"),
              Self.constantTimeEquals(given, token) else {
            return Outcome(response: .text(401, "unauthorized"))
        }

        let context = EventDecoder.Context(
            hostBundleId: request.header("x-termpet-host-bundle").flatMap { $0.isEmpty ? nil : $0 },
            termProgram: request.header("x-termpet-term-program").flatMap { $0.isEmpty ? nil : $0 },
            terminal: request.header("x-termpet-tty").flatMap { $0.isEmpty ? nil : $0 }
        )

        do {
            var event: PetEvent
            switch request.path {
            case "/hook/claude": event = try EventDecoder.decodeClaudeHook(request.body, context: context)
            case "/hook/codex": event = try EventDecoder.decodeCodexNotify(request.body, context: context)
            default: event = try EventDecoder.decodeStandard(request.body, context: context)
            }
            event.clampTextFields() // 아주 긴 글이 알림 큐·기록에 쌓여 메모리를 차지하지 않게
            return Outcome(response: .text(202, "accepted"), event: event)
        } catch EventDecoder.DecodeError.ignored(let reason) {
            return Outcome(response: .text(200, "ignored: \(reason)"))
        } catch {
            return Outcome(response: .text(400, "bad request: \(error)"))
        }
    }

    /// 타이밍 공격 방지용 비교 (보안 습관)
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
