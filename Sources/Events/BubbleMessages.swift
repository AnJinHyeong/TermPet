import Foundation

/// 말풍선 문구 세트. Phase 3에서 캐릭터 팩의 `messages`로 대체된다.
struct BubbleMessages: Equatable {
    var done: [String]
    var error: [String]
    var ask: [String]

    static let `default` = BubbleMessages(
        done: ["끝났어!", "작업 완료~", "다 됐어!"],
        error: ["에러 났어…", "빨간 줄 떴어!", "뭔가 잘못됐어!"],
        ask: ["확인해줘!", "허락이 필요해", "나 좀 봐줘!"]
    )

    func pool(for kind: PetEvent.Kind) -> [String] {
        switch kind {
        case .done: return done
        case .error: return error
        case .ask: return ask
        }
    }
}

/// 말풍선 한 장에 표시할 내용
struct BubbleContent: Equatable {
    /// 상단 작은 글씨: 프로젝트 이름 (없으면 소스 이름)
    var title: String
    /// 본문: 이벤트 message 또는 랜덤 문구
    var body: String
    /// 보조 설명 (회색, 최대 2줄)
    var detail: String?

    static func make(for event: PetEvent, messages: BubbleMessages = .default,
                     using rng: inout some RandomNumberGenerator) -> BubbleContent {
        let title = event.projectName ?? sourceLabel(event.source)
        let body = event.message ?? messages.pool(for: event.kind).randomElement(using: &rng) ?? "!"

        var detail = event.detail
        if event.source == .shell, let d = event.durationSec {
            let time = formatDuration(d)
            detail = detail.map { "\($0) · \(time)" } ?? time
        }
        return BubbleContent(title: title, body: body, detail: detail)
    }

    static func sourceLabel(_ source: PetEvent.Source) -> String {
        switch source {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .shell: return "터미널"
        }
    }

    /// 42 → "42초", 125 → "2분 5초", 3700 → "1시간 1분"
    static func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)초" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60)분" : "\(s / 60)분 \(s % 60)초" }
        let m = (s % 3600) / 60
        return m == 0 ? "\(s / 3600)시간" : "\(s / 3600)시간 \(m)분"
    }
}
