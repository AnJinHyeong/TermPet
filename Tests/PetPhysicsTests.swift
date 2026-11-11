import XCTest
@testable import TermPet

final class PetPhysicsTests: XCTestCase {
    private let size = CGSize(width: 80, height: 80)

    private func isHitWall(_ r: PetPhysics.WalkResult) -> Bool {
        if case .hitWall = r { return true }
        return false
    }

    private func physics(x: CGFloat, y: CGFloat) -> PetPhysics {
        PetPhysics(origin: CGPoint(x: x, y: y), size: size)
    }

    /// 착지할 때까지 낙하 (무한 루프 방지 상한)
    private func fallUntilLanded(_ p: inout PetPhysics, layout: ScreenLayout) {
        p.prepareFall(layout: layout)
        for _ in 0..<2000 where !p.fall(dt: 1.0 / 60, layout: layout) {}
    }

    /// 모니터 경계 폴짝 → 착지할 때까지
    private func hopUntilLanded(_ p: inout PetPhysics, _ dir: Direction, layout: ScreenLayout) {
        let t = Terrain(screens: layout, petSize: p.size)
        p.prepareFall(terrain: t, velocity: p.screenHop(dir))
        for _ in 0..<2000 where !p.fall(dt: 1.0 / 60, terrain: t) {}
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
        XCTAssertTrue(isHitWall(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout)))
        XCTAssertEqual(p.origin.x, 920)

        var q = physics(x: 10, y: 0)
        XCTAssertTrue(isHitWall(q.walk(direction: .left, speed: 100, dt: 0.5, layout: layout)))
        XCTAssertEqual(q.origin.x, 0)
    }

    func testWalkCrossesIntoAdjacentScreenWithSameFloor() {
        let layout = ScreenLayout(frames: [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 1000, height: 800),
        ])
        var p = physics(x: 900, y: 0)
        // 경계에서 멈춰 서고(건너뛸지 두뇌가 정함) → 폴짝 뛰면 몸 전체가 옆 화면에 착지
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout), .reachedScreenEdge)
        XCTAssertEqual(p.origin.x, 920)
        hopUntilLanded(&p, .right, layout: layout)
        XCTAssertEqual(p.origin.y, 0)
        XCTAssertGreaterThanOrEqual(p.origin.x, 1000)
    }

    func testAdjacentScreenWithHigherFloorActsAsWall() {
        let layout = ScreenLayout(frames: [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 80, width: 1000, height: 720), // Dock 때문에 바닥이 더 높음
        ])
        var p = physics(x: 930, y: 0)
        // 옆 화면 바닥 높이까지만 벽(턱)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout),
                       .hitWall(Terrain.Wall(x: 1000, top: 80, windowID: nil, side: .right, leadsToScreen: true)))
    }

    func testWalkingOntoLowerAdjacentScreenStartsFalling() {
        let layout = ScreenLayout(frames: [
            CGRect(x: 0, y: 80, width: 1000, height: 720),
            CGRect(x: 1000, y: 0, width: 1000, height: 800),
        ])
        var p = physics(x: 900, y: 80)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.5, layout: layout), .reachedScreenEdge)
        hopUntilLanded(&p, .right, layout: layout)
        XCTAssertEqual(p.origin.y, 0)
        XCTAssertGreaterThanOrEqual(p.origin.x, 1000)
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

final class FallSpeedTests: XCTestCase {
    /// 화면 맨 위(1100pt)에서 떨어져도 1.5초 넘게 걸리고, 속도는 상한을 넘지 않는다 (캐릭터가 보이게)
    func testFallIsSlowEnoughToSeeTheCharacter() {
        let layout = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1600, height: 1100)])
        var p = PetPhysics(origin: CGPoint(x: 500, y: 1000), size: CGSize(width: 92, height: 92))
        p.prepareFall(layout: layout)
        var elapsed = 0.0, fastest: CGFloat = 0
        while !p.fall(dt: 1.0 / 60, layout: layout), elapsed < 10 {
            elapsed += 1.0 / 60
            fastest = max(fastest, -p.velocity.dy)
        }
        XCTAssertGreaterThan(elapsed, 1.5)
        XCTAssertLessThanOrEqual(fastest, p.maxFallSpeed + 0.001)
        XCTAssertEqual(p.origin.y, 0, accuracy: 0.5)
    }
}
