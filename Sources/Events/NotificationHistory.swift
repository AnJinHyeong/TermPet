import Foundation

/// 최근 알림 기록 (순수 로직). 말풍선을 놓쳐도 메뉴 패널 "최근 알림"에서 다시 보고 그 창으로 갈 수 있게.
/// React 비유: 새 항목을 앞에 붙이고 길이를 자르는 reducer — `[item, ...prev].slice(0, max)`.
struct NotificationHistory: Equatable {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let event: PetEvent
        let title: String
        let body: String
        var date: Date { event.receivedAt }
    }

    static let maxItems = 30

    /// 최신이 맨 앞
    private(set) var entries: [Entry] = []

    /// 알림 하나 기록. 진행 신호(작업 중 등)·"입력 기다리는 중" 리마인더는 기록하지 않는다.
    /// 같은 세션의 이전 권한 요청은 새 알림으로 대체한다 (승인했거나 끝났으니 의미 없음).
    mutating func record(_ event: PetEvent, content: BubbleContent) {
        guard event.isNotification, !event.isIdlePrompt else { return }
        if let sid = event.sessionId {
            entries.removeAll { $0.event.sessionId == sid && $0.event.source == event.source && $0.event.kind == .ask }
        }
        entries.insert(Entry(id: event.id, event: event, title: content.title, body: content.body), at: 0)
        if entries.count > Self.maxItems { entries.removeLast(entries.count - Self.maxItems) }
    }

    mutating func removeAll() { entries.removeAll() }
}
