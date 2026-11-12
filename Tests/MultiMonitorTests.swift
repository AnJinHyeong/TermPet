import XCTest
@testable import TermPet

/// 높이가 다른 모니터 두 대 사이 오가기 (실제 배치: 맥북 화면 오른쪽, LG 모니터가 왼쪽에 바닥 764pt 높이로 붙음)
final class MultiMonitorTests: XCTestCase {
    private let pet = CGSize(width: 80, height: 80)
    private let builtIn = CGRect(x: 0, y: 0, width: 1800, height: 1130)
    private let lg = CGRect(x: -1920, y: 764, width: 1920, height: 1080)
    private var layout: ScreenLayout { ScreenLayout(frames: [builtIn, lg]) }
    private var terrain: Terrain { Terrain(screens: layout, petSize: pet) }

    private func land(_ p: inout PetPhysics, velocity: CGVector) {
        p.prepareFall(terrain: terrain, velocity: velocity)
        for _ in 0..<3000 where !p.fall(dt: 1.0 / 60, terrain: terrain) {}
    }

    /// 같은 높이로 나란한 모니터 경계 위에 떨어지면(던져짐·포인터 쫓아 점프) 한쪽 모니터 안으로 완전히 들어간다
    /// (걸친 채 서 있으면 넘어간 부분이 반투명하게 보인다)
    func testLandingOnBoundaryMovesFullyOntoOneScreen() {
        let side = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)])
        let flat = Terrain(screens: side, petSize: pet)
        for (startX, expected) in [(950.0, 920.0), (970.0, 1000.0)] as [(CGFloat, CGFloat)] { // 가운데가 왼쪽 / 오른쪽 모니터
            var p = PetPhysics(origin: CGPoint(x: startX, y: 300), size: pet)
            p.prepareFall(terrain: flat)
            for _ in 0..<3000 where !p.fall(dt: 1.0 / 60, terrain: flat) {}
            XCTAssertEqual(p.origin.y, 0)
            XCTAssertEqual(p.origin.x, expected, "x=\(startX)")
        }
    }

    func testStepNeighborNeedsRoomAtTop() {
        XCTAssertEqual(layout.stepNeighbor(of: 0, side: .left, aboveY: 0, petHeight: 80), 1)
        XCTAssertNil(layout.stepNeighbor(of: 0, side: .right, aboveY: 0, petHeight: 80))
        // 턱 꼭대기에 매달리면 머리가 화면 위로 잘리는 높이면 턱이 아니다
        XCTAssertNil(layout.stepNeighbor(of: 0, side: .left, aboveY: 0, petHeight: 400))
    }

    /// 맥북 바닥 → 왼쪽 벽을 턱(764)까지 기어올라 LG로 폴짝 넘어간다
    func testClimbsUpToHigherMonitorAndHopsOver() {
        var p = PetPhysics(origin: CGPoint(x: 10, y: 0), size: pet)
        guard case .hitWall(let wall) = p.walk(direction: .left, speed: 50, dt: 0.5, terrain: terrain) else {
            return XCTFail("wall expected")
        }
        XCTAssertTrue(wall.leadsToScreen)
        XCTAssertEqual(wall.top, 764)
        XCTAssertEqual(p.origin.x, 0)

        var result = PetPhysics.ClimbResult.climbing
        for _ in 0..<2000 where result == .climbing {
            result = p.climb(wall, speed: 60, dt: 1.0 / 30, terrain: terrain, limitY: .infinity)
            XCTAssertEqual(p.origin.x, 0, "벽에 붙어서 오른다 (두 화면에 걸치지 않음)")
        }
        XCTAssertEqual(result, .overStep)
        XCTAssertEqual(p.origin.y, 764)

        land(&p, velocity: p.screenHop(.left))
        XCTAssertEqual(p.origin.y, 764)
        XCTAssertLessThanOrEqual(p.origin.x + pet.width, 0, "몸 전체가 LG 위")
    }

    /// LG → 맥북: 경계에서 멈췄다가 폴짝 뛰어 맥북 바닥에 몸 전체가 착지 (예전엔 반쯤 빈 공간에 걸쳐 착지 후 툭 튐)
    func testHopsDownToLowerMonitorWithoutStraddlingTheGap() {
        var p = PetPhysics(origin: CGPoint(x: -100, y: 764), size: pet)
        XCTAssertEqual(p.walk(direction: .right, speed: 50, dt: 1, terrain: terrain), .reachedScreenEdge)
        XCTAssertEqual(p.origin.x, -80)
        land(&p, velocity: p.screenHop(.right))
        XCTAssertEqual(p.origin.y, 0)
        XCTAssertGreaterThanOrEqual(p.origin.x, 0)
    }

    /// 맥북 왼쪽 끝(x=0)에 붙은 창(최대화 창 등)이 있어도 LG → 맥북 경계에서 그 창 옆면을 벽으로 타지 않고 건너뛴다
    func testWindowAtNeighborEdgeIsNotAWallAcrossTheBoundary() {
        let t = Terrain(screens: layout, windows: [WindowBox(id: 1, frame: CGRect(x: 0, y: 70, width: 1800, height: 1060))],
                        petSize: pet)
        var p = PetPhysics(origin: CGPoint(x: -100, y: 764), size: pet)
        XCTAssertEqual(p.walk(direction: .right, speed: 50, dt: 1, terrain: t), .reachedScreenEdge)
        XCTAssertNil(t.nearestWallDirection(originX: -100, feetY: 764).flatMap { $0 == .right ? $0 : nil })
        p.prepareFall(terrain: t, velocity: p.screenHop(.right))
        for _ in 0..<3000 where !p.fall(dt: 1.0 / 60, terrain: t) {}
        XCTAssertEqual(p.origin.y, 0)
        XCTAssertGreaterThanOrEqual(p.origin.x, 0)
        // 맥북 쪽에서 그 창 앞을 지나 걷는 건 그대로 (이미 겹쳐 있으니 벽 아님)
        XCTAssertEqual(p.walk(direction: .right, speed: 50, dt: 0.5, terrain: t), .moved)
    }

    func testBigPetHopClearsTheBoundaryToo() {
        let big = CGSize(width: 160, height: 160)
        var p = PetPhysics(origin: CGPoint(x: -160, y: 764), size: big)
        let t = Terrain(screens: layout, petSize: big)
        p.prepareFall(terrain: t, velocity: p.screenHop(.right))
        for _ in 0..<3000 where !p.fall(dt: 1.0 / 60, terrain: t) {}
        XCTAssertEqual(p.origin.y, 0)
        XCTAssertGreaterThanOrEqual(p.origin.x, 0)
    }

    /// 낮게 던지면 LG 아래 빈 공간은 벽 → 맥북 쪽에 착지 (예전엔 LG 바닥 764로 순간이동)
    func testLowThrowTowardGapBouncesInsteadOfTeleporting() {
        var p = PetPhysics(origin: CGPoint(x: 200, y: 300), size: pet)
        p.prepareFall(terrain: terrain, velocity: CGVector(dx: -1500, dy: 0))
        var maxY = p.origin.y
        for _ in 0..<3000 where !p.fall(dt: 1.0 / 60, terrain: terrain) {
            maxY = max(maxY, p.origin.y)
            XCTAssertGreaterThanOrEqual(p.origin.x, 0)
        }
        XCTAssertEqual(p.origin.y, 0)
        XCTAssertLessThanOrEqual(maxY, 300)
    }

    func testBrainCrossesOrTurnsAtScreenBoundary() {
        var rng = SeededGenerator(seed: 1)
        var always = PetBrain.Config(); always.crossScreenChance = 1
        var never = PetBrain.Config(); never.crossScreenChance = 0

        var a = walkingBrain(always, &rng); a.handle(.hitStep, using: &rng)
        XCTAssertEqual(a.action, .climb)
        var b = walkingBrain(always, &rng); b.handle(.reachedScreenEdge, using: &rng)
        XCTAssertEqual(b.action, .fall)
        var c = walkingBrain(never, &rng); let dir = c.direction
        c.handle(.reachedScreenEdge, using: &rng)
        XCTAssertEqual(c.action, .walk)
        XCTAssertEqual(c.direction, dir.flipped)
    }

    /// 두뇌 + 물리를 컨트롤러처럼 60분 돌려 본다:
    /// 프레임마다 순간이동(30pt 넘게 튐)이 없고, 바닥에 설 땐 몸이 한 화면 안에 다 들어가 있고, 두 모니터를 오간다.
    func testLongRunNoJumpsNoStraddlingAndVisitsBothMonitors() {
        for seed in UInt64(1)...6 {
            var rng = SeededGenerator(seed: seed)
            var config = PetBrain.Config(); config.sleepAfter = .infinity // 잠들면 안 움직이니 끈다
            var brain = PetBrain(config: config)
            var p = PetPhysics(origin: CGPoint(x: 600, y: 0), size: pet)
            var wall: Terrain.Wall?
            var climbLimit = CGFloat.infinity
            var last = p.origin
            var visitedLG = false, cameBack = false
            let dt = 1.0 / 30
            for _ in 0..<(30 * 60 * 60) {
                brain.tick(dt, using: &rng)
                switch brain.action {
                case .walk:
                    switch p.walk(direction: brain.direction, speed: 46, dt: dt, terrain: terrain) {
                    case .moved: break
                    case .hitWall(let w):
                        brain.handle(w.leadsToScreen ? .hitStep : .hitWall(window: w.windowID != nil), using: &rng)
                        if brain.action == .climb {
                            wall = w
                            // 컨트롤러(startClimbing)와 같은 방식: 턱이면 끝까지, 아니면 천장 아래 절반쯤에서 손을 놓는다
                            let top = min(w.top, terrain.ceiling(atX: p.centerX) ?? w.top) - pet.height
                            climbLimit = w.leadsToScreen ? .infinity : p.origin.y + max(0, top - p.origin.y) * 0.5
                        }
                    case .reachedEdge:
                        brain.handle(.reachedEdge, using: &rng)
                    case .reachedScreenEdge:
                        brain.handle(.reachedScreenEdge, using: &rng)
                        if brain.action == .fall { p.prepareFall(terrain: terrain, velocity: p.screenHop(brain.direction)) }
                    case .startFalling:
                        p.prepareFall(terrain: terrain); brain.handle(.startFall, using: &rng)
                    }
                case .climb:
                    guard let w = wall else { return XCTFail("climb without wall") }
                    switch p.climb(w, speed: 60, dt: dt, terrain: terrain, limitY: climbLimit) {
                    case .climbing: break
                    case .reachedTop: brain.handle(.climbedUp, using: &rng)
                    case .letGo:
                        brain.handle(.letGo, using: &rng)
                        p.prepareFall(terrain: terrain, velocity: CGVector(dx: -w.side.sign * 180, dy: 380))
                    case .overStep:
                        p.prepareFall(terrain: terrain, velocity: p.screenHop(w.side)); brain.handle(.startFall, using: &rng)
                    }
                case .fall:
                    if p.fall(dt: dt, terrain: terrain) { brain.handle(.landed, using: &rng) }
                default: break
                }
                XCTAssertLessThan(hypot(p.origin.x - last.x, p.origin.y - last.y), 30, "seed \(seed) jump \(last)→\(p.origin)")
                last = p.origin
                if brain.action == .idle || brain.action == .walk {
                    let screen = p.origin.y >= 764 ? lg : builtIn
                    XCTAssertTrue(p.origin.x >= screen.minX - 0.5 && p.origin.x + pet.width <= screen.maxX + 0.5,
                                  "seed \(seed) straddling at \(p.origin)")
                    if p.origin.y == 764 { visitedLG = true }
                    if visitedLG, p.origin.y == 0 { cameBack = true }
                }
            }
            XCTAssertTrue(visitedLG && cameBack, "seed \(seed): visitedLG \(visitedLG) cameBack \(cameBack)")
        }
    }

    private func walkingBrain(_ config: PetBrain.Config, _ rng: inout SeededGenerator) -> PetBrain {
        var b = PetBrain(config: config)
        b.tick(10, using: &rng) // idle → walk
        return b
    }
}
