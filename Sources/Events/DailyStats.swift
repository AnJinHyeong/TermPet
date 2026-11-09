import Foundation

/// 오늘 하루 기록 (순수 로직). 날짜가 바뀌면 새로 시작한다.
/// `Codable`이라 UserDefaults에 JSON으로 저장 (앱을 껐다 켜도 오늘 기록 유지).
struct DailyStats: Codable, Equatable {
    /// "2026-11-09" (사용자 지역 시간 기준)
    var day: String
    /// Claude·Codex가 응답을 마친 횟수
    var aiDone = 0
    /// 오래 걸린 터미널 명령이 성공한 횟수
    var shellDone = 0
    var errors = 0
    /// 권한 요청 횟수
    var asks = 0
    var longestCommand: String?
    var longestSeconds: Double = 0

    var total: Int { aiDone + shellDone + errors }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    init(day: String) { self.day = day }

    /// 알림 이벤트 하나 기록. 진행 신호(작업 중 등)와 "입력 기다리는 중" 리마인더는 세지 않는다.
    mutating func record(_ event: PetEvent, now: Date = Date(), calendar: Calendar = .current) {
        let today = Self.dayKey(now, calendar: calendar)
        if day != today { self = DailyStats(day: today) }
        guard event.isNotification, !event.isIdlePrompt else { return }

        switch event.kind {
        case .done: if event.source == .shell { shellDone += 1 } else { aiDone += 1 }
        case .error: errors += 1
        case .ask: asks += 1
        case .working, .ended: break
        }
        if event.source == .shell, let d = event.durationSec, d > longestSeconds {
            longestSeconds = d
            longestCommand = event.command.map(EventDecoder.oneLine)
        }
    }

    /// 날짜가 지났으면 빈 기록으로 보여주기 위한 값
    func current(now: Date = Date(), calendar: Calendar = .current) -> DailyStats {
        day == Self.dayKey(now, calendar: calendar) ? self : DailyStats(day: Self.dayKey(now, calendar: calendar))
    }

    /// 펫을 눌렀을 때 하는 말
    var speech: BubbleContent {
        if total == 0 && asks == 0 {
            return BubbleContent(title: "오늘", body: "오늘은 아직 한가해요", detail: "작업이 끝나면 알려줄게요")
        }
        var body = "오늘 \(aiDone + shellDone)번 끝냈어요!"
        if aiDone + shellDone == 0 { body = "오늘은 아직 끝낸 일이 없어요" }
        var parts: [String] = []
        if aiDone > 0 { parts.append("AI \(aiDone)") }
        if shellDone > 0 { parts.append("명령 \(shellDone)") }
        if errors > 0 { parts.append("에러 \(errors)") }
        if asks > 0 { parts.append("권한 요청 \(asks)") }
        var detail = parts.joined(separator: " · ")
        if let cmd = longestCommand, longestSeconds > 0 {
            detail += (detail.isEmpty ? "" : "\n") + "가장 오래: \(cmd) (\(BubbleContent.formatDuration(longestSeconds)))"
        }
        return BubbleContent(title: "오늘", body: body, detail: detail.isEmpty ? nil : detail)
    }

    /// 메뉴 패널 맨 위 한 줄 요약
    var summaryLine: String? {
        guard total > 0 || asks > 0 else { return nil }
        var parts = ["✓ \(aiDone + shellDone)"]
        if errors > 0 { parts.append("✗ \(errors)") }
        if asks > 0 { parts.append("✋ \(asks)") }
        if longestSeconds > 0 { parts.append("가장 긴 명령 \(BubbleContent.formatDuration(longestSeconds))") }
        return parts.joined(separator: " · ")
    }
}

/// 펫 기분 (순수 로직): 최근 30분의 성공/실패로 정한다.
enum PetMood: String, Equatable {
    case cheerful, normal, gloomy

    static let window: TimeInterval = 30 * 60

    /// outcomes: (시각, 성공 여부) — 오래된 것부터
    static func from(_ outcomes: [(Date, Bool)], now: Date) -> PetMood {
        let recent = outcomes.filter { now.timeIntervalSince($0.0) < window }
        guard !recent.isEmpty else { return .normal }
        let errors = recent.filter { !$0.1 }.count
        let successes = recent.count - errors
        // 마지막 3개 중 2개 이상 실패 → 시무룩
        let lastThree = recent.suffix(3)
        if lastThree.filter({ !$0.1 }).count >= 2 { return .gloomy }
        // 실패 없이 3번 이상 성공 → 신남
        if errors == 0 && successes >= 3 { return .cheerful }
        // 최근 연속 성공 3번 이상이면 다시 신남
        if recent.suffix(3).count == 3 && recent.suffix(3).allSatisfy({ $0.1 }) { return .cheerful }
        return .normal
    }

    /// 걷는 속도 배율
    var walkFactor: CGFloat {
        switch self {
        case .cheerful: return 1.25
        case .normal: return 1
        case .gloomy: return 0.6
        }
    }
}
