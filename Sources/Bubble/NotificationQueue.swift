import Foundation

/// 말풍선 한 장 = 알림 하나
struct PetNotification: Identifiable, Equatable {
    let id: UUID
    let event: PetEvent
    let content: BubbleContent

    init(event: PetEvent, content: BubbleContent) {
        self.id = event.id
        self.event = event
        self.content = content
    }
}

/// 미확인 알림 큐 (순수 로직). 맨 앞(`current`)이 지금 말풍선에 보이는 알림.
///
/// 같은 세션(sessionId)에서 또 알림이 오면 새로 쌓지 않고 기존 것을 교체한다.
/// 예: Claude가 "끝났어" 후 60초 뒤 "입력 기다리는 중(idle_prompt)"을 보내면 → 무시
struct NotificationQueue {
    static let maxItems = 20

    private(set) var items: [PetNotification] = []

    var current: PetNotification? { items.first }
    /// 말풍선의 "+N" 배지 숫자
    var pendingCount: Int { max(0, items.count - 1) }
    var isEmpty: Bool { items.isEmpty }

    enum PushResult: Equatable { case added, replaced, ignored }

    @discardableResult
    mutating func push(_ notification: PetNotification) -> PushResult {
        let event = notification.event
        if let sid = event.sessionId,
           let index = items.firstIndex(where: { $0.event.sessionId == sid && $0.event.source == event.source }) {
            // 이미 확인 안 한 알림이 있는데 "아직 기다리는 중" 리마인더면 의미 없음
            if event.isIdlePrompt { return .ignored }
            items[index] = notification
            return .replaced
        }
        items.append(notification)
        if items.count > Self.maxItems {
            items.removeFirst(items.count - Self.maxItems)
        }
        return .added
    }

    /// 현재 알림을 꺼낸다 (말풍선 클릭/닫기). 다음 알림이 `current`가 된다.
    @discardableResult
    mutating func popCurrent() -> PetNotification? {
        items.isEmpty ? nil : items.removeFirst()
    }

    mutating func removeAll() { items.removeAll() }
}
