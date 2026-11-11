import XCTest
@testable import TermPet

final class ScreenFloorTests: XCTestCase {
    let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    let pet = CGSize(width: 80, height: 80)

    func testWalkableFrameGoesToScreenBottom() {
        let visible = CGRect(x: 0, y: 81, width: 1800, height: 1049)
        XCTAssertEqual(ScreenFloor.walkableFrame(frame: frame, visible: visible),
                       CGRect(x: 0, y: 0, width: 1800, height: 1130))
    }

    func testNoDockWhenHidden() {
        XCTAssertNil(ScreenFloor.dockBox(frame: frame, visible: CGRect(x: 0, y: 0, width: 1800, height: 1130), dockWidth: 900))
    }

    func testDockBoxCenteredAtBottom() throws {
        let box = try XCTUnwrap(ScreenFloor.dockBox(frame: frame, visible: CGRect(x: 0, y: 81, width: 1800, height: 1049), dockWidth: 1000))
        XCTAssertEqual(box.frame, CGRect(x: 400, y: 0, width: 1000, height: 77))
        XCTAssertTrue(ScreenFloor.isDock(box.id))
        XCTAssertFalse(ScreenFloor.isDock(12345))
        XCTAssertFalse(ScreenFloor.isDock(nil))
    }

    private func terrain() -> Terrain {
        let visible = CGRect(x: 0, y: 81, width: 1800, height: 1049)
        let dock = ScreenFloor.dockBox(frame: frame, visible: visible, dockWidth: 1000)!
        return Terrain(screens: ScreenLayout(frames: [ScreenFloor.walkableFrame(frame: frame, visible: visible)]),
                       windows: [dock], petSize: pet)
    }

    func testFallsOntoDockOrBottom() {
        let t = terrain()
        XCTAssertEqual(t.landing(centerX: 900, fromY: 500, toY: -10)?.y, 77)
        XCTAssertTrue(ScreenFloor.isDock(t.landing(centerX: 900, fromY: 500, toY: -10)?.windowID))
        XCTAssertEqual(t.landing(centerX: 100, fromY: 500, toY: -10), Terrain.Floor(y: 0, windowID: nil))
    }

    func testWalkingOnDockReachesEdge() {
        let t = terrain()
        var p = PetPhysics(origin: CGPoint(x: 1360, y: 77), size: pet)
        p.standingOn = ScreenFloor.dockIDBase
        var result: PetPhysics.WalkResult = .moved
        for _ in 0..<100 where result == .moved {
            result = p.walk(direction: .right, speed: 100, dt: 0.1, terrain: t)
        }
        XCTAssertEqual(result, .reachedEdge)
    }

    func testBottomWalkerHitsDockSideAndClimbsOnto() throws {
        let t = terrain()
        var p = PetPhysics(origin: CGPoint(x: 200, y: 0), size: pet)
        var result: PetPhysics.WalkResult = .moved
        for _ in 0..<100 where result == .moved {
            result = p.walk(direction: .right, speed: 100, dt: 0.1, terrain: t)
        }
        guard case .hitWall(let wall) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(wall.x, 400)
        var climb: PetPhysics.ClimbResult = .climbing
        for _ in 0..<100 where climb == .climbing {
            climb = p.climb(wall, speed: 60, dt: 0.1, terrain: t, limitY: .infinity)
        }
        XCTAssertEqual(climb, .reachedTop(windowID: ScreenFloor.dockIDBase))
        XCTAssertEqual(p.origin.y, 77)
    }

    func testOverlapCenterOnDockLiftsOntoDock() throws {
        let dock = CGRect(x: 400, y: 0, width: 1000, height: 77)
        let fix = try XCTUnwrap(ScreenFloor.resolveDockOverlap(origin: CGPoint(x: 600, y: 0), size: pet, dock: dock))
        XCTAssertEqual(fix.origin, CGPoint(x: 600, y: 77))
        XCTAssertTrue(fix.onDock)
    }

    /// 몸 중심은 Dock 밖인데 몸이 걸쳐 있으면 옆으로 밀어낸다 (Dock 밑으로 걸어 들어가지 않게)
    func testOverlapAtEdgePushesOutSideways() throws {
        let dock = CGRect(x: 400, y: 0, width: 1000, height: 77)
        let left = try XCTUnwrap(ScreenFloor.resolveDockOverlap(origin: CGPoint(x: 340, y: 0), size: pet, dock: dock))
        XCTAssertEqual(left.origin, CGPoint(x: 320, y: 0))
        XCTAssertFalse(left.onDock)
        let right = try XCTUnwrap(ScreenFloor.resolveDockOverlap(origin: CGPoint(x: 1370, y: 0), size: pet, dock: dock))
        XCTAssertEqual(right.origin, CGPoint(x: 1400, y: 0))
    }

    func testNoOverlapLeavesPetAlone() {
        let dock = CGRect(x: 400, y: 0, width: 1000, height: 77)
        XCTAssertNil(ScreenFloor.resolveDockOverlap(origin: CGPoint(x: 200, y: 0), size: pet, dock: dock))   // 옆 바닥
        XCTAssertNil(ScreenFloor.resolveDockOverlap(origin: CGPoint(x: 600, y: 77), size: pet, dock: dock))  // Dock 위
        XCTAssertNil(ScreenFloor.resolveDockOverlap(origin: CGPoint(x: 600, y: 300), size: pet, dock: dock)) // 공중
    }

    /// 실측: tilesize 55, 앱 23 + 최소화 창 2 + 휴지통 = 26칸, 구분선 1 → 실제 Dock 폭 약 1578pt
    func testDockWidthEstimateMatchesMeasuredDock() {
        XCTAssertEqual(ScreenFloor.estimatedDockWidth(tileSize: 55, items: 26, separators: 1), 1578, accuracy: 8)
    }

    func testFullscreenWindowHidesDock() {
        func full(_ r: CGRect) -> Bool { ScreenFloor.hasFullscreenWindow([WindowBox(id: 1, frame: r)], screen: frame) }
        XCTAssertTrue(full(frame))                                              // 화면 전체
        XCTAssertTrue(full(CGRect(x: 0, y: 0, width: 1800, height: 1124)))      // 노치 MacBook 전체 화면(노치 줄 제외)
        XCTAssertFalse(full(CGRect(x: 0, y: 81, width: 1800, height: 1049)))    // 최대화(Dock 위까지만)
        XCTAssertFalse(full(CGRect(x: 0, y: 0, width: 1200, height: 1124)))     // 폭이 모자람
        XCTAssertFalse(full(CGRect(x: 0, y: 0, width: 1800, height: 600)))      // 아래쪽 반만
    }

    /// 크롬 전체 화면: 웹페이지 창(0~1008) + 툴바 창(972~1130) 여러 장 → 합쳐서 전체 화면
    func testChromeSplitFullscreenWindowsCount() {
        let chrome: [WindowBox] = [
            WindowBox(id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1008), owner: 42),
            WindowBox(id: 2, frame: CGRect(x: 0, y: 972, width: 1800, height: 158), owner: 42),
        ]
        XCTAssertTrue(ScreenFloor.hasFullscreenWindow(chrome, screen: frame))
        // 다른 앱 창끼리는 합치지 않는다
        var mixed = chrome; mixed[1].owner = 7
        XCTAssertFalse(ScreenFloor.hasFullscreenWindow(mixed, screen: frame))
        // 사이가 떠 있으면 아님
        let gap = [WindowBox(id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 500), owner: 42),
                   WindowBox(id: 2, frame: CGRect(x: 0, y: 700, width: 1800, height: 430), owner: 42)]
        XCTAssertFalse(ScreenFloor.hasFullscreenWindow(gap, screen: frame))
    }
}

/// 두뇌 + 물리를 컨트롤러처럼 돌려 보는 통합 시뮬레이션:
/// Dock 위에서 놀다 → 끝에서 뛰어내려 맨 바닥 → Dock 옆면을 기어 다시 Dock 위로.
final class DockPlaySimulationTests: XCTestCase {
    func testPetJumpsOffDockAndClimbsBack() {
        for seed in UInt64(1)...8 { simulate(seed: seed) }
    }

    private func simulate(seed: UInt64) {
        let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let visible = CGRect(x: 0, y: 81, width: 1800, height: 1049)
        let pet = CGSize(width: 92, height: 92)
        let dock = ScreenFloor.dockBox(frame: frame, visible: visible, dockWidth: 1000)!
        let terrain = Terrain(screens: ScreenLayout(frames: [ScreenFloor.walkableFrame(frame: frame, visible: visible)]),
                              windows: [dock], petSize: pet)
        var rng = SeededGenerator(seed: seed)
        var brain = PetBrain()
        var p = PetPhysics(origin: CGPoint(x: 850, y: dock.frame.maxY), size: pet)
        p.standingOn = dock.id
        var wall: Terrain.Wall?
        var sawFloor = false, climbedBack = false
        let dt = 1.0 / 30
        for _ in 0..<(30 * 60 * 20) where !climbedBack { // 최대 20분
            brain.tick(dt, using: &rng)
            switch brain.action {
            case .walk:
                switch p.walk(direction: brain.direction, speed: 46, dt: dt, terrain: terrain) {
                case .moved: break
                case .hitWall(let w):
                    brain.handle(.hitWall(window: w.windowID != nil), using: &rng)
                    if brain.action == .climb { wall = w }
                case .reachedEdge:
                    brain.handle(.reachedEdge, using: &rng)
                    if brain.action == .fall { p.prepareFall(terrain: terrain, velocity: CGVector(dx: brain.direction.sign * 110, dy: 420)) }
                case .startFalling:
                    p.prepareFall(terrain: terrain); brain.handle(.startFall, using: &rng)
                case .reachedScreenEdge: XCTFail("single screen")
                }
            case .climb:
                guard let w = wall else { XCTFail("climb without wall"); return }
                switch p.climb(w, speed: 60, dt: dt, terrain: terrain, limitY: .infinity) {
                case .climbing: break
                case .reachedTop: brain.handle(.climbedUp, using: &rng); wall = nil
                    if sawFloor, ScreenFloor.isDock(p.standingOn) { climbedBack = true }
                case .letGo: brain.handle(.letGo, using: &rng); p.prepareFall(terrain: terrain)
                case .overStep: XCTFail("single screen")
                }
            case .fall:
                if p.fall(dt: dt, terrain: terrain) { brain.handle(.landed, using: &rng) }
            default: break
            }
            if p.standingOn == nil, brain.action != .climb, brain.action != .fall, p.origin.y == 0 {
                sawFloor = true
                // 바닥에 있을 땐 절대 Dock 뒤(Dock 가로 범위 안)에 있으면 안 된다
                XCTAssertTrue(p.origin.x + pet.width <= dock.frame.minX + 0.5 || p.origin.x >= dock.frame.maxX - 0.5,
                              "behind dock at x=\(p.origin.x)")
            }
        }
        XCTAssertTrue(sawFloor, "seed \(seed): Dock에서 바닥으로 내려간 적이 없음")
        XCTAssertTrue(climbedBack, "seed \(seed): 바닥에서 Dock 위로 다시 올라온 적이 없음")
    }
}

final class DockFullscreenGateTests: XCTestCase {
    func testBriefFullscreenDropoutKeepsDockHidden() {
        var gate = DockFullscreenGate()
        XCTAssertFalse(gate.update(fullscreen: false, spaceChanged: false))   // 평소: Dock 보임
        XCTAssertTrue(gate.update(fullscreen: true, spaceChanged: false))     // 전체 화면
        XCTAssertTrue(gate.update(fullscreen: false, spaceChanged: false))    // 한순간 판정 풀림 → 그래도 숨김
        XCTAssertTrue(gate.update(fullscreen: true, spaceChanged: false))     // 다시 전체 화면 (카운트 초기화)
        XCTAssertTrue(gate.update(fullscreen: false, spaceChanged: false))
        XCTAssertTrue(gate.update(fullscreen: false, spaceChanged: false))
    }

    func testDockReturnsAfterSeveralClearChecks() {
        var gate = DockFullscreenGate()
        _ = gate.update(fullscreen: true, spaceChanged: false)
        for _ in 1..<DockFullscreenGate.clearChecksNeeded {
            XCTAssertTrue(gate.update(fullscreen: false, spaceChanged: false))
        }
        XCTAssertFalse(gate.update(fullscreen: false, spaceChanged: false))
    }

    func testSpaceChangeShowsDockRightAway() {
        var gate = DockFullscreenGate()
        _ = gate.update(fullscreen: true, spaceChanged: false)
        XCTAssertFalse(gate.update(fullscreen: false, spaceChanged: true))    // 전체 화면 앱에서 바탕화면으로 전환
    }
}
