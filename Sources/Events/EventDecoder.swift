import Foundation

/// 외부에서 들어온 JSON → `PetEvent` 변환. 모든 필드를 옵셔널로 방어적으로 읽는다.
///
/// `Codable`(≈ zod 스키마로 파싱) 대신 `[String: Any]` 딕셔너리로 읽는 이유:
/// 외부 도구의 형식이 바뀌어도(필드 추가/누락/타입 변경) 죽지 않고 최대한 살리기 위해서.
enum EventDecoder {
    enum DecodeError: Error, Equatable {
        case invalidJSON
        case missingField(String)
        case invalidValue(String)
        /// 받았지만 알림으로 보여줄 필요가 없는 이벤트 (예: auth_success)
        case ignored(String)
    }

    /// 요청 메타데이터 (훅 스크립트가 HTTP 헤더로 보냄)
    struct Context: Equatable {
        var hostBundleId: String?
        var termProgram: String?
        /// Claude가 실행 중인 터미널 (예: ttys016)
        var terminal: String?
    }

    // MARK: - 표준 이벤트 (POST /event)

    /// SPEC 3-5의 앱 표준 JSON 형식
    static func decodeStandard(_ data: Data, context: Context = Context()) throws -> PetEvent {
        let obj = try jsonObject(data)
        guard let sourceRaw = obj.string("source") else { throw DecodeError.missingField("source") }
        guard let source = PetEvent.Source(rawValue: sourceRaw) else { throw DecodeError.invalidValue("source") }

        let exitCode = obj.int("exitCode")
        let kind: PetEvent.Kind
        if let kindRaw = obj.string("kind") {
            guard let k = PetEvent.Kind(rawValue: kindRaw) else { throw DecodeError.invalidValue("kind") }
            kind = k
        } else if let exitCode {
            kind = exitCode == 0 ? .done : .error // 쉘: 종료 코드로 판단
        } else {
            throw DecodeError.missingField("kind")
        }

        var event = PetEvent(
            source: source,
            kind: kind,
            message: obj.string("message"),
            detail: obj.string("detail") ?? obj.string("command").map(oneLine),
            cwd: obj.string("cwd"),
            sessionId: obj.string("sessionId"),
            transcriptPath: obj.string("transcriptPath"),
            command: obj.string("command"),
            exitCode: exitCode,
            durationSec: obj.double("durationSec"),
            hostBundleId: obj.string("hostBundleId") ?? context.hostBundleId,
            termProgram: obj.string("termProgram") ?? context.termProgram
        )
        event.title = obj.string("title")
        return event
    }

    // MARK: - Claude Code 훅 원본 (POST /hook/claude)

    /// Claude Code 훅의 stdin JSON을 그대로 받아 해석한다.
    /// 문서(https://code.claude.com/docs/en/hooks) 기준 공통 필드:
    ///   session_id, transcript_path, cwd, hook_event_name, permission_mode
    /// Stop: last_assistant_message, stop_hook_active
    /// Notification: message, title, notification_type
    /// UserPromptSubmit: prompt / PostToolUse: tool_name (훅 스크립트가 큰 tool_response는 빼고 보냄) / SessionEnd: reason
    static func decodeClaudeHook(_ data: Data, context: Context = Context()) throws -> PetEvent {
        let obj = try jsonObject(data)
        let eventName = obj.string("hook_event_name") ?? ""

        var event = PetEvent(
            source: .claude,
            kind: .done,
            cwd: obj.string("cwd"),
            sessionId: obj.string("session_id"),
            transcriptPath: obj.string("transcript_path"),
            hostBundleId: context.hostBundleId,
            termProgram: context.termProgram
        )
        event.terminal = context.terminal

        switch eventName {
        case "Stop":
            event.kind = .done
            // 말풍선 본문은 캐릭터 문구("끝났어!"), 마지막 답변 첫 줄은 보조 설명으로
            event.detail = obj.string("last_assistant_message").map(oneLine).flatMap(nonEmpty)

        case "Notification":
            let type = obj.string("notification_type")
            event.notificationType = type
            switch type {
            case nil, "permission_prompt", "idle_prompt", "elicitation_dialog",
                 "elicitation_url_dialog", "agent_needs_input":
                event.kind = .ask
            case "agent_completed":
                event.kind = .done
            default:
                // auth_success, quota_* 등은 사용자 행동이 필요 없음
                throw DecodeError.ignored("notification_type=\(type ?? "")")
            }
            event.message = koreanNotification(obj.string("message").flatMap(nonEmpty), type: type)

        case "StopFailure":
            event.kind = .error
            event.message = obj.string("error").flatMap(nonEmpty)

        // 진행 상황 신호: 말풍선 없이 "작업 중" 표시만 갱신
        case "UserPromptSubmit":
            event.kind = .working
        case "PreToolUse", "PostToolUse":
            // 도구가 실행됐다 = 권한 대기가 풀렸거나 계속 일하는 중
            event.kind = .working
            event.detail = obj.string("tool_name")
        case "SessionEnd":
            event.kind = .ended

        default:
            // TODO: 다른 훅 이벤트(SubagentStop 등)를 연결하게 되면 여기에 추가
            throw DecodeError.ignored("hook_event_name=\(eventName)")
        }
        return event
    }

    // MARK: - 알림 문구 한국어로

    /// Claude Code 알림(영어)을 한국어로. 이미 한국어거나 모르는 문장이면 종류별 기본 문구, 그것도 없으면 원문.
    /// 예) "Claude needs your permission to use Bash" → "Bash 사용을 허락해 줄래요?"
    /// 원문이 없으면 nil 그대로 (말풍선이 캐릭터 대사를 쓰게)
    static func koreanNotification(_ message: String?, type: String?) -> String? {
        guard let message else { return nil }
        if message.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
            return message // 이미 한국어
        }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let usePrefix = "claude needs your permission to use "
        if lower.hasPrefix(usePrefix) {
            let tool = String(text.dropFirst(usePrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            return tool.isEmpty ? "권한 확인이 필요해요" : "\(tool) 사용을 허락해 줄래요?"
        }
        if lower.contains("needs your permission") || lower.contains("permission") { return "권한 확인이 필요해요" }
        if lower.contains("waiting for your input") || lower.contains("waiting for input") { return "입력을 기다리고 있어요" }
        if lower.contains("needs your attention") { return "확인이 필요해요" }
        switch type {
        case "permission_prompt": return "권한 확인이 필요해요"
        case "idle_prompt": return "입력을 기다리고 있어요"
        case "elicitation_dialog": return "선택해 줄 게 있어요"
        case "elicitation_url_dialog": return "링크에서 확인해 줄 게 있어요"
        case "agent_needs_input": return "입력이 필요해요"
        case "agent_completed": return "작업이 끝났어요"
        default: return message
        }
    }

    // MARK: - Codex notify (POST /hook/codex)

    /// TODO(Phase 5): Codex 공식 문서 확인 후 보강. 현재는 알려진 형태만 방어적으로 처리.
    /// 예상 형식: {"type":"agent-turn-complete","turn-id":..., "last-assistant-message":..., "cwd":...}
    static func decodeCodexNotify(_ data: Data, context: Context = Context()) throws -> PetEvent {
        let obj = try jsonObject(data)
        let type = obj.string("type") ?? ""
        guard type == "agent-turn-complete" else { throw DecodeError.ignored("type=\(type)") }
        return PetEvent(
            source: .codex,
            kind: .done,
            detail: obj.string("last-assistant-message").map(oneLine).flatMap(nonEmpty),
            cwd: obj.string("cwd"),
            sessionId: obj.string("thread-id") ?? obj.string("session-id"),
            hostBundleId: context.hostBundleId,
            termProgram: context.termProgram
        )
    }

    // MARK: - helpers

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.invalidJSON
        }
        return obj
    }

    /// 여러 줄 텍스트 → 첫 번째 내용 있는 줄, 최대 120자
    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        // 마크다운 강조 기호 제거 (**굵게**, `코드`, __밑줄__) + 앞쪽 제목/목록 기호 제거
        let cleaned = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*-> "))
        return cleaned.count > 120 ? String(cleaned.prefix(119)) + "…" : cleaned
    }

    private static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// 딕셔너리에서 타입이 맞을 때만 값을 꺼내는 헬퍼 (TS의 `typeof x === 'string' ? x : undefined`)
private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        guard let s = self[key] as? String else { return nil }
        return s.isEmpty ? nil : s
    }

    /// JSON 숫자만 (true/false 제외). 주의: Swift에서 NSNumber 0/1은 `is Bool`도 true가 되므로
    /// CoreFoundation 타입 ID로 진짜 불리언인지 구분한다.
    func number(_ key: String) -> NSNumber? {
        guard let n = self[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n
    }

    func int(_ key: String) -> Int? {
        if let n = number(key) { return n.intValue }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let n = number(key) { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }
}
