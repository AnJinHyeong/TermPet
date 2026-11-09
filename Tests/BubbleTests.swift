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
