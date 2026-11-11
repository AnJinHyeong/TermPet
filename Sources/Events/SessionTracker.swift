import Foundation

/// 진행 중인 AI 세션(프로젝트별 Claude/Codex 대화)의 상태를 기억하는 순수 로직.
/// React 비유: 이벤트를 받아 `Record<sessionKey, Session>`을 갱신하는 reducer.
///
/// - UserPromptSubmit / PostToolUse → 작업 중
/// - Notification(권한 요청 등)      → 권한 대기
/// - Stop → 끝남, StopFailure → 에러, SessionEnd → 목록에서 제거
/// 사용자가 Esc로 중단하면 Stop 훅이 오지 않으므로, 오래 소식이 없는 "작업 중"은 정리한다.
struct SessionTracker {
    enum State: String, Equatable { case working, waiting, done, error }

    struct Session: Identifiable, Equatable {
        let id: String
        var source: PetEvent.Source
        var projectName: String?
        var state: State
        /// 지금 상태가 시작된 시각 ("작업 중 · 3분")
        var since: Date
        /// 마지막으로 소식이 온 시각
        var lastSeen: Date
        /// 클릭 시 프로젝트 창으로 이동하기 위한 정보 (cwd, 호스트 앱)
        var focusEvent: PetEvent
    }

    /// 이 시간 동안 소식이 없는 "작업 중/권한 대기"는 중단된 것으로 보고 지운다
    static let staleAfter: TimeInterval = 15 * 60
    /// Claude 앱 채팅은 Claude가 끝 신호(termpet_notify)를 빠뜨릴 수 있어서, "답변 중"을 더 빨리 지운다
    /// (안 그러면 답이 끝났는데도 "…"이 계속 떠서 아직 답변 중인 것처럼 보인다)
    static let claudeChatStaleAfter: TimeInterval = 5 * 60
    /// 끝난 세션은 이 시간 동안만 목록에 남긴다
    static let keepFinishedFor: TimeInterval = 10 * 60

    private(set) var sessions: [String: Session] = [:]

    /// 같은 터미널이면 대화가 새로 시작돼도(/clear, 재실행) 한 줄로 합친다. 터미널을 모르면 대화 ID로 구분.
    static func key(for event: PetEvent) -> String? {
        guard let sid = event.sessionId, !sid.isEmpty else { return nil }
        if let tty = event.terminal, !tty.isEmpty { return "\(event.source.rawValue):tty:\(tty)" }
        return "\(event.source.rawValue):\(sid)"
    }

    /// 이벤트 반영. 세션 정보가 없는 이벤트(쉘 명령 등)는 무시하고 nil.
    /// 반환값: 이 세션의 이전 상태 (처음 보는 세션이면 nil)
    @discardableResult
    mutating func apply(_ event: PetEvent, now: Date = Date()) -> State? {
        guard let key = Self.key(for: event) else { return nil }
        let previous = sessions[key]

        if event.kind == .ended {
            // 같은 터미널에서 이미 새 대화가 시작됐다면 그건 지우지 않는다
            if let old = previous, old.focusEvent.sessionId != event.sessionId, event.terminal != nil {
                return old.state
            }
            sessions[key] = nil
            return previous?.state
        }

        let state: State
        switch event.kind {
        case .working: state = .working
        case .done: state = .done
        case .error: state = .error
        case .ask:
            // idle_prompt = "끝났고 입력을 기다리는 중" 리마인더 → 권한 대기가 아니다
            state = event.isIdlePrompt ? (previous?.state ?? .done) : .waiting
        case .ended: return previous?.state // 위에서 처리됨
        }

        // 도구 실행 신호는 cwd/호스트 정보가 빠져 있을 수 있으니 기존 값을 유지
        var focus = event
        if let old = previous?.focusEvent {
            focus.cwd = event.cwd ?? old.cwd
            focus.hostBundleId = event.hostBundleId ?? old.hostBundleId
            focus.termProgram = event.termProgram ?? old.termProgram
        }

        sessions[key] = Session(
            id: key,
            source: event.source,
            projectName: focus.projectName ?? previous?.projectName,
            state: state,
            since: previous?.state == state ? previous!.since : now,
            lastSeen: now,
            focusEvent: focus
        )
        return previous?.state
    }

    /// 오래된 세션 정리. 바뀐 게 있으면 true.
    @discardableResult
    mutating func prune(now: Date = Date()) -> Bool {
        let before = sessions.count
        sessions = sessions.filter { _, s in
            let age = now.timeIntervalSince(s.lastSeen)
            switch s.state {
            case .working, .waiting:
                let isClaudeChat = s.focusEvent.sessionId == ClaudeAppMCP.sessionId
                return age < (isClaudeChat ? Self.claudeChatStaleAfter : Self.staleAfter)
            case .done, .error: return age < Self.keepFinishedFor
            }
        }
        return sessions.count != before
    }

    /// 화면 표시 순서: 권한 대기 → 작업 중 → 끝남/에러, 같은 상태끼리는 최근 순
    var ordered: [Session] {
        sessions.values.sorted {
            let a = Self.rank($0.state), b = Self.rank($1.state)
            return a != b ? a < b : $0.lastSeen > $1.lastSeen
        }
    }

    var waitingCount: Int { sessions.values.filter { $0.state == .waiting }.count }
    var workingCount: Int { sessions.values.filter { $0.state == .working }.count }

    private static func rank(_ state: State) -> Int {
        switch state {
        case .waiting: return 0
        case .working: return 1
        case .error: return 2
        case .done: return 3
        }
    }
}

/// 펫 머리 위 표시 (우선순위: 권한 대기 > 미확인 알림 > 작업 중)
enum PetBadge: Equatable {
    case none
    case unread
    case working(Int)
    case waiting(Int)

    static func pick(waiting: Int, working: Int, hasUnread: Bool) -> PetBadge {
        if waiting > 0 { return .waiting(waiting) }
        if hasUnread { return .unread }
        if working > 0 { return .working(working) }
        return .none
    }
}
