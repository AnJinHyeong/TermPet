import XCTest
@testable import TermPet

/// 메뉴 패널용 순수 로직: 최근 알림 기록, 설정값
final class PanelLogicTests: XCTestCase {
    private func content(_ body: String = "끝!") -> BubbleContent { BubbleContent(title: "proj", body: body) }

    func testHistoryKeepsNewestFirstAndSkipsProgressSignals() {
        var h = NotificationHistory()
        h.record(PetEvent(source: .shell, kind: .done, message: "a"), content: content("a"))
        h.record(PetEvent(source: .claude, kind: .working, sessionId: "s"), content: content("x"))
        h.record(PetEvent(source: .shell, kind: .error, message: "b"), content: content("b"))
        XCTAssertEqual(h.entries.map(\.body), ["b", "a"])
    }

    func testHistorySkipsIdlePrompt() {
        var h = NotificationHistory()
        h.record(PetEvent(source: .claude, kind: .ask, sessionId: "s", notificationType: "idle_prompt"), content: content())
        XCTAssertTrue(h.entries.isEmpty)
    }

    func testHistoryReplacesOldAskOfSameSession() {
        var h = NotificationHistory()
        h.record(PetEvent(source: .claude, kind: .ask, sessionId: "s", notificationType: "permission_prompt"), content: content("권한"))
        h.record(PetEvent(source: .claude, kind: .ask, sessionId: "other"), content: content("다른 세션"))
        h.record(PetEvent(source: .claude, kind: .done, sessionId: "s"), content: content("끝"))
        XCTAssertEqual(h.entries.map(\.body), ["끝", "다른 세션"])
    }

    func testHistoryIsCapped() {
        var h = NotificationHistory()
        for i in 0..<(NotificationHistory.maxItems + 5) {
            h.record(PetEvent(source: .shell, kind: .done, message: "\(i)"), content: content("\(i)"))
        }
        XCTAssertEqual(h.entries.count, NotificationHistory.maxItems)
        XCTAssertEqual(h.entries.first?.body, "\(NotificationHistory.maxItems + 4)")
    }

    func testPreferencesClampAndScale() {
        var p = PetPreferences()
        p.sizeScale = 5
        p.speedScale = 0
        p.bubbleSeconds = .nan
        XCTAssertEqual(p.sizeScale, PetPreferences.sizeRange.upperBound)
        XCTAssertEqual(p.speedScale, PetPreferences.speedRange.lowerBound)
        XCTAssertEqual(p.bubbleSeconds, PetPreferences.bubbleRange.lowerBound) // NaN → 최소값
        p.sizeScale = 0.6
        XCTAssertEqual(p.scaled(CGSize(width: 80, height: 30)), CGSize(width: 48, height: 24))
    }

    func testPreferencesRoundTrip() {
        let defaults = UserDefaults(suiteName: "PanelLogicTests-\(UUID())")!
        var p = PetPreferences()
        p.sizeScale = 1.3; p.speedScale = 0.7; p.bubbleSeconds = 6
        p.save(defaults)
        XCTAssertEqual(PetPreferences.load(defaults), p)
        XCTAssertEqual(PetPreferences.load(UserDefaults(suiteName: "empty-\(UUID())")!), PetPreferences())
    }
}
