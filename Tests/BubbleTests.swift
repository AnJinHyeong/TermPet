import SwiftUI
import XCTest
@testable import TermPet

final class NotificationQueueTests: XCTestCase {
    private func note(_ kind: PetEvent.Kind = .done, session: String? = nil,
                      source: PetEvent.Source = .claude, type: String? = nil, body: String = "x") -> PetNotification {
        PetNotification(event: PetEvent(source: source, kind: kind, sessionId: session, notificationType: type),
                        content: BubbleContent(title: "t", body: body))
    }

    func testFIFOAndBadge() {
        var q = NotificationQueue()
        let a = note(body: "a"), b = note(body: "b"), c = note(body: "c")
        q.push(a); q.push(b); q.push(c)
        XCTAssertEqual(q.current, a)
        XCTAssertEqual(q.pendingCount, 2)
        XCTAssertEqual(q.popCurrent(), a)
        XCTAssertEqual(q.current, b)
        XCTAssertEqual(q.pendingCount, 1)
        q.popCurrent(); q.popCurrent()
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.popCurrent())
        XCTAssertEqual(q.pendingCount, 0)
    }

    func testSameSessionReplacesInPlace() {
        var q = NotificationQueue()
        q.push(note(session: "s1", body: "first"))
        q.push(note(session: "s2", body: "other"))
        let newer = note(.ask, session: "s1", body: "permission")
        XCTAssertEqual(q.push(newer), .replaced)
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.current, newer)
    }

    func testIdlePromptIgnoredWhenSessionAlreadyUnread() {
        var q = NotificationQueue()
        q.push(note(.done, session: "s1", body: "done"))
        XCTAssertEqual(q.push(note(.ask, session: "s1", type: "idle_prompt")), .ignored)
        XCTAssertEqual(q.current?.content.body, "done")
    }

    func testIdlePromptAddedWhenNothingUnread() {
        var q = NotificationQueue()
        XCTAssertEqual(q.push(note(.ask, session: "s1", type: "idle_prompt")), .added)
    }

    func testDifferentSourcesWithSameSessionIdDoNotMerge() {
        var q = NotificationQueue()
        q.push(note(session: "s", source: .claude))
        XCTAssertEqual(q.push(note(session: "s", source: .codex)), .added)
    }

    func testEventsWithoutSessionAlwaysAppend() {
        var q = NotificationQueue()
        q.push(note(source: .shell))
        XCTAssertEqual(q.push(note(source: .shell)), .added)
        XCTAssertEqual(q.items.count, 2)
    }

    func testCapsSizeDroppingOldest() {
        var q = NotificationQueue()
        for i in 0..<(NotificationQueue.maxItems + 5) { q.push(note(body: "\(i)")) }
        XCTAssertEqual(q.items.count, NotificationQueue.maxItems)
        XCTAssertEqual(q.current?.content.body, "5")
    }
}

final class BubblePlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 80, width: 1000, height: 700) // visibleFrame (maxY 780)
    private let size = CGSize(width: 200, height: 80)

    func testCenteredAbovePet() {
        let pet = CGRect(x: 400, y: 80, width: 80, height: 80)
        let r = BubblePlacement.place(bubbleSize: size, petFrame: pet, screen: screen)
        XCTAssertFalse(r.below)
        XCTAssertEqual(r.origin.x, 340)
        XCTAssertEqual(r.origin.y, 160 - BubblePlacement.overlap)
        XCTAssertEqual(r.tailX, 100)
    }

    func testClampedAtScreenEdgesWithTailFollowingPet() {
        let left = BubblePlacement.place(bubbleSize: size, petFrame: CGRect(x: 0, y: 80, width: 80, height: 80), screen: screen)
        XCTAssertEqual(left.origin.x, BubblePlacement.screenMargin)
        XCTAssertEqual(left.tailX, 40 - BubblePlacement.screenMargin)

        let right = BubblePlacement.place(bubbleSize: size, petFrame: CGRect(x: 920, y: 80, width: 80, height: 80), screen: screen)
        XCTAssertEqual(right.origin.x, 1000 - 200 - BubblePlacement.screenMargin)
        XCTAssertEqual(right.tailX, 960 - right.origin.x) // 꼬리는 펫 중앙을 가리킴
    }

    func testFlipsBelowWhenNoRoomAbove() {
        let pet = CGRect(x: 400, y: 690, width: 80, height: 80)
        let r = BubblePlacement.place(bubbleSize: size, petFrame: pet, screen: screen)
        XCTAssertTrue(r.below)
        XCTAssertLessThan(r.origin.y + size.height, pet.maxY)
    }
}

final class HostAppTests: XCTestCase {
    func testResolveByBundleId() {
        XCTAssertEqual(HostApp.resolve(bundleId: "com.todesktop.230313mzl4w4u92", termProgram: "vscode"), .cursor)
        XCTAssertEqual(HostApp.resolve(bundleId: "com.microsoft.VSCode", termProgram: nil), .vscode)
        XCTAssertEqual(HostApp.resolve(bundleId: "com.googlecode.iterm2", termProgram: nil), .iterm)
        XCTAssertEqual(HostApp.resolve(bundleId: "com.example.foo", termProgram: nil), .other(bundleId: "com.example.foo"))
        for (id, app) in HostApp.knownBundleIds { XCTAssertEqual(app.bundleId, id) } // 표 하나로 양방향 일치
    }

    func testResolveByTermProgramFallback() {
        XCTAssertEqual(HostApp.resolve(bundleId: nil, termProgram: "vscode"), .vscode)
        XCTAssertEqual(HostApp.resolve(bundleId: "", termProgram: "iTerm.app"), .iterm)
        XCTAssertEqual(HostApp.resolve(bundleId: nil, termProgram: "Apple_Terminal"), .terminal)
        XCTAssertNil(HostApp.resolve(bundleId: nil, termProgram: "weird"))
        XCTAssertNil(HostApp.resolve(bundleId: nil, termProgram: nil))
    }

    func testFocusPlanOpensFolderForEditors() {
        let e = PetEvent(source: .claude, kind: .done, cwd: "/Users/me/fitin/src",
                         hostBundleId: "com.todesktop.230313mzl4w4u92")
        let plan = FocusAction.plan(for: e) { _ in "/Users/me/fitin" }
        XCTAssertEqual(plan, .openFolder(bundleId: "com.todesktop.230313mzl4w4u92", path: "/Users/me/fitin"))
    }

    func testFocusPlanActivatesTerminals() {
        let e = PetEvent(source: .shell, kind: .done, cwd: "/x", termProgram: "iTerm.app")
        XCTAssertEqual(FocusAction.plan(for: e) { $0 }, .activate(bundleId: "com.googlecode.iterm2"))
    }

    func testFocusPlanEditorWithoutCwdJustActivates() {
        let e = PetEvent(source: .claude, kind: .done, hostBundleId: "com.microsoft.VSCode")
        XCTAssertEqual(FocusAction.plan(for: e) { $0 }, .activate(bundleId: "com.microsoft.VSCode"))
    }

    /// ChatGPT 앱 대화는 딥링크로 그 대화를 연다
    func testFocusPlanOpensChatGPTThread() {
        let e = PetEvent(source: .codex, kind: .done, cwd: "/x", sessionId: "01a1-c98a", hostBundleId: "com.openai.codex")
        XCTAssertEqual(FocusAction.plan(for: e) { $0 }, .openURL(url: "codex://threads/01a1-c98a", bundleId: "com.openai.codex"))
        let noThread = PetEvent(source: .codex, kind: .done, hostBundleId: "com.openai.codex")
        XCTAssertEqual(FocusAction.plan(for: noThread) { $0 }, .activate(bundleId: "com.openai.codex"))
    }

    func testFocusPlanUnknownHost() {
        XCTAssertEqual(FocusAction.plan(for: PetEvent(source: .shell, kind: .done, cwd: "/x")) { $0 }, .none)
    }

    func testProjectRootFinder() {
        let gitDirs: Set<String> = ["/Users/me/fitin/.git"]
        let exists = { (p: String) in gitDirs.contains(p) }
        XCTAssertEqual(ProjectRootFinder.find(from: "/Users/me/fitin/src/app", home: "/Users/me", exists: exists),
                       "/Users/me/fitin")
        XCTAssertEqual(ProjectRootFinder.find(from: "/Users/me/fitin", home: "/Users/me", exists: exists),
                       "/Users/me/fitin")
        // git 저장소가 아니면 cwd 그대로
        XCTAssertEqual(ProjectRootFinder.find(from: "/Users/me/notes/a", home: "/Users/me", exists: exists),
                       "/Users/me/notes/a")
    }
}

final class BubbleTailClampTests: XCTestCase {
    func testTailNeverReachesBubbleCorner() {
        // 말풍선보다 펫이 훨씬 오른쪽(다른 화면에 걸친 경우 등)이어도 꼬리는 모서리 안쪽
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let r = BubblePlacement.place(bubbleSize: CGSize(width: 200, height: 80),
                                      petFrame: CGRect(x: 1100, y: 0, width: 80, height: 80), screen: screen)
        XCTAssertEqual(r.tailX, 200 - BubblePlacement.tailInset)
    }
}

final class BubbleWidthTests: XCTestCase {
    /// 글자당 7pt로 단순 측정 (폰트 무관하게 결정적)
    private let measure: (String, NSFont) -> CGFloat = { s, _ in CGFloat(s.count) * 7 }

    func testShortTextUsesMinimumWidth() {
        let c = BubbleContent(title: "a", body: "끝!")
        XCTAssertEqual(BubbleMetrics.bodyWidth(for: c, badge: 0, measure: measure), BubbleMetrics.minBodyWidth)
    }

    func testLongTextIsCappedAtMaximumWidth() {
        let c = BubbleContent(title: "TermPet", body: "끝났어!",
                              detail: String(repeating: "원인으로 보이는 문제를 두 가지 찾아서 고쳤습니다. ", count: 5))
        XCTAssertEqual(BubbleMetrics.bodyWidth(for: c, badge: 0, measure: measure), BubbleMetrics.maxBodyWidth)
    }

    func testMediumTextFitsBetween() {
        let c = BubbleContent(title: "fitin", body: String(repeating: "가", count: 20))
        let w = BubbleMetrics.bodyWidth(for: c, badge: 0, measure: measure)
        XCTAssertEqual(w, 20 * 7 + BubbleMetrics.horizontalPadding * 2 + 2)
    }

    func testBadgeWidensTitleLine() {
        let c = BubbleContent(title: String(repeating: "a", count: 16), body: "x")
        XCTAssertGreaterThan(BubbleMetrics.bodyWidth(for: c, badge: 3, measure: measure),
                             BubbleMetrics.bodyWidth(for: c, badge: 0, measure: measure))
    }
}

@MainActor
final class BubbleWindowSizingTests: XCTestCase {
    /// 회귀 테스트: 짧은 알림 → 긴 알림으로 창 크기가 바뀌어도 SwiftUI 뷰가 창에 정확히 맞아야 한다
    /// (예전 버그: host가 창보다 넓어져 말풍선 오른쪽/양쪽이 잘림)
    func testHostAlwaysMatchesWindowWhenContentChanges() throws {
        let bubble = BubbleController()
        bubble.follow(petFrame: CGRect(x: 400, y: 100, width: 80, height: 80))
        defer { bubble.clearAll() }

        let events = [
            PetEvent(source: .shell, kind: .error, message: "짧음", cwd: "/a/fitin"),
            PetEvent(source: .claude, kind: .done, detail: String(repeating: "아주 긴 답변 문장입니다. ", count: 20),
                     cwd: "/a/TermPet"),
            PetEvent(source: .claude, kind: .ask, message: "중간 길이의 확인 요청 메시지예요", cwd: "/a/x"),
        ]
        for event in events {
            bubble.enqueue(event)
            // 현재 표시 중인 알림을 바꿔가며 확인
            while bubble.queue.current?.event.id != event.id { bubble.dismissCurrent() }
            bubble.show()
            let window = try XCTUnwrap(bubble.windowForTesting)
            let host = try XCTUnwrap(bubble.hostForTesting)
            let root = try XCTUnwrap(window.contentView)
            XCTAssertEqual(host.frame, root.bounds, "host must exactly fill the window")
            XCTAssertEqual(window.frame.width, bubble.model.width + BubbleMetrics.outerPadding * 2)
            XCTAssertLessThanOrEqual(bubble.model.width, BubbleMetrics.maxBodyWidth)
        }
    }

    /// 회귀 테스트: 내용이 바뀐 직후 창 높이가 "새 내용"의 실제 높이와 같아야 한다
    /// (예전 버그: 이전 내용 기준 높이로 창을 맞춰서 2줄 문장일 때 말풍선 위/아래가 잘림)
    func testWindowHeightMatchesNewContentImmediately() throws {
        let bubble = BubbleController()
        bubble.follow(petFrame: CGRect(x: 400, y: 100, width: 80, height: 80))
        defer { bubble.clearAll() }

        let events = [
            PetEvent(source: .shell, kind: .error, message: "짧음", cwd: "/a/fitin"),
            PetEvent(source: .claude, kind: .done, message: "긴 메시지 " + String(repeating: "줄바꿈 확인 ", count: 12),
                     detail: String(repeating: "상세 설명 ", count: 15), cwd: "/a/TermPet"),
            PetEvent(source: .shell, kind: .done, message: "다시 짧음", cwd: "/a/b"),
        ]
        for event in events {
            bubble.enqueue(event)
            while bubble.queue.current?.event.id != event.id { bubble.dismissCurrent() }
            bubble.show()
            let window = try XCTUnwrap(bubble.windowForTesting)
            let expected = NSHostingView(rootView: BubbleView(model: bubble.model)).fittingSize.height.rounded(.up)
            XCTAssertEqual(window.frame.height, expected, "\(event.message ?? "")")
        }
    }
}
