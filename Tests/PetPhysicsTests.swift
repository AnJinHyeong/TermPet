import XCTest
@testable import TermPet

final class PetPhysicsTests: XCTestCase {
    private let size = CGSize(width: 80, height: 80)

    private func physics(x: CGFloat, y: CGFloat) -> PetPhysics {
        PetPhysics(origin: CGPoint(x: x, y: y), size: size)
    }

    /// 착지할 때까지 낙하 (무한 루프 방지 상한)
    private func fallUntilLanded(_ p: inout PetPhysics, layout: ScreenLayout) {
        p.prepareFall(layout: layout)
        for _ in 0..<2000 where !p.fall(dt: 1.0 / 60, layout: layout) {}
    }

    // MARK: - 걷기

    func testWalkMovesHorizontally() {
        let layout = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        var p = physics(x: 100, y: 0)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout), .moved)
        XCTAssertEqual(p.origin.x, 150)
        XCTAssertEqual(p.walk(direction: .left, speed: 100, dt: 1, layout: layout), .moved)
        XCTAssertEqual(p.origin.x, 50)
    }

    func testWalkHitsWallAtScreenEdge() {
        let layout = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        var p = physics(x: 900, y: 0)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout), .hitWall)
        XCTAssertEqual(p.origin.x, 920)

        var q = physics(x: 10, y: 0)
        XCTAssertEqual(q.walk(direction: .left, speed: 100, dt: 0.5, layout: layout), .hitWall)
        XCTAssertEqual(q.origin.x, 0)
    }

    func testWalkCrossesIntoAdjacentScreenWithSameFloor() {
        let layout = ScreenLayout(frames: [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1000, height: 800),
        ])
        var p = physics(x: 930, y: 0)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout), .moved)
        XCTAssertEqual(p.origin.x, 980)
    }

    func testAdjacentScreenWithHigherFloorActsAsWall() {
        let layout = ScreenLayout(frames: [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 80, width: 1000, height: 720), // Dock 때문에 바닥이 더 높음
        ])
        var p = physics(x: 930, y: 0)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout), .hitWall)
    }

    func testWalkingOntoLowerAdjacentScreenStartsFalling() {
        let layout = ScreenLayout(frames: [
            CGRect(x: 0, y: 80, width: 1000, height: 720),
            CGRect(x: 1000, y: 0, width: 1000, height: 800),
        ])
        var p = physics(x: 930, y: 80)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout), .startFalling)
        fallUntilLanded(&p, layout: layout)
        XCTAssertEqual(p.origin.y, 0)
    }

    // MARK: - 낙하

    func testFallLandsOnFloor() {
        let layout = ScreenLayout(frames: [CGRect(x: 0, y: 80, width: 1000, height: 720)])
        var p = physics(x: 100, y: 600)
        p.prepareFall(layout: layout)
        XCTAssertFalse(p.fall(dt: 1.0 / 60, layout: layout))
        XCTAssertLessThan(p.origin.y, 600)
        fallUntilLanded(&p, layout: layout)
        XCTAssertEqual(p.origin.y, 80)
        XCTAssertEqual(p.velocityY, 0)
    }

    func testDroppedBelowFloorSnapsUp() {
        // Dock 위(바닥 아래)에 놓은 경우
        let layout = ScreenLayout(frames: [CGRect(x: 0, y: 80, width: 1000, height: 720)])
        var p = physics(x: 100, y: 20)
        p.prepareFall(layout: layout)
        XCTAssertTrue(p.fall(dt: 1.0 / 60, layout: layout))
        XCTAssertEqual(p.origin.y, 80)
    }

    func testDroppedOffScreenIsPulledBackToNearestScreen() {
        let layout = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        var p = physics(x: 1500, y: 300)
        fallUntilLanded(&p, layout: layout)
        XCTAssertEqual(p.origin.x, 920)
        XCTAssertEqual(p.origin.y, 0)
    }

    func testPartiallyOffScreenIsClampedOnLanding() {
        let layout = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        var p = physics(x: -30, y: 300)
        fallUntilLanded(&p, layout: layout)
        XCTAssertEqual(p.origin.x, 0)
    }

    func testFallLandsOnUpperScreenOfVerticalStack() {
        // 위아래로 쌓인 모니터: 위 화면에서 떨어지면 위 화면 바닥에 착지
        let layout = ScreenLayout(frames: [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 0, y: 800, width: 1000, height: 800),
        ])
        var p = physics(x: 100, y: 1400)
        fallUntilLanded(&p, layout: layout)
        XCTAssertEqual(p.origin.y, 800)
    }
}
