import XCTest
@testable import TermPet

/// 장난꾸러기 모드: 쫓기 → 물기 → 던지기 상태 머신
final class MischiefTests: XCTestCase {
    private let pet = CGRect(x: 500, y: 0, width: 80, height: 80)
    private let dt = 1.0 / 30

    private func input(cursor: CGPoint, frame: CGRect? = nil, canPlay: Bool = true,
                       mouseDown: Bool = false, grounded: Bool = true,
                       climbingSide: Direction? = nil, wallDirection: Direction? = nil) -> Mischief.Input {
        Mischief.Input(petFrame: frame ?? pet, cursor: cursor, facing: .right,
                       canPlay: canPlay, mouseDown: mouseDown, grounded: grounded,
                       climbingSide: climbingSide, wallDirection: wallDirection)
    }

    /// 켜자마자 바로 쫓는 장난꾸러기
    private func eager() -> Mischief {
        var c = Mischief.Config(); c.startDelay = 0
        return Mischief(config: c)
    }

    func testChasesPointerWhereverItIs() {
        var m = eager()
        // 멀리 있어도, 멈춰 있어도 계속 쫓는다
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 1700, y: 900))), .chase(.right))
        XCTAssertEqual(m.phase, .chasing)
        for _ in 0..<(30 * 20) {
            XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 1700, y: 900))), .chase(.right))
        }
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 100, y: 40))), .chase(.left))
        // 바로 위 너무 높은데 탈 벽도 없으면 제자리에서 힘껏 뛰어 본다
        guard case .jump(let v) = m.tick(dt, input(cursor: CGPoint(x: 545, y: 900))) else { return XCTFail("jump expected") }
        XCTAssertGreaterThan(v.dy, 1000)
    }

    func testWaitsAfterTurningOnAndWhileButtonPressed() {
        var m = Mischief()
        XCTAssertEqual(m.tick(0.5, input(cursor: CGPoint(x: 900, y: 40))), .none, "켜자마자는 잠깐 기다림")
        XCTAssertEqual(m.tick(0.6, input(cursor: CGPoint(x: 900, y: 40))), .chase(.right))

        // 드래그 중이면 쫓기 시작하지 않는다
        var pressed = eager()
        XCTAssertEqual(pressed.tick(dt, input(cursor: CGPoint(x: 700, y: 40), mouseDown: true)), .none)
        XCTAssertEqual(pressed.phase, .ready)
        // 쫓는 중에 버튼을 누르고 있으면 닿아도 안 문다
        _ = pressed.tick(dt, input(cursor: CGPoint(x: 700, y: 40)))
        XCTAssertNotEqual(pressed.tick(dt, input(cursor: CGPoint(x: 540, y: 40), mouseDown: true)), .startBite)
    }

    func testCatchBiteThenThrowThenChaseAgain() {
        var m = eager()
        var rng = SeededGenerator(seed: 4)
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)))
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 560, y: 40))), .startBite)
        // 흔드는 동안 포인터를 입에 문다 (입은 바라보는 쪽 앞)
        guard case .holdPointer(let p) = m.tick(dt, input(cursor: CGPoint(x: 560, y: 41))) else {
            return XCTFail("hold expected")
        }
        XCTAssertTrue(pet.insetBy(dx: -10, dy: -10).contains(p))
        XCTAssertGreaterThan(p.x, pet.midX)
        var cmd = Mischief.Command.none
        for _ in 0..<60 where cmd != .throwPointer { cmd = m.tick(dt, input(cursor: CGPoint(x: 560, y: 42))) }
        XCTAssertEqual(cmd, .throwPointer)
        XCTAssertEqual(m.phase, .throwing)
        _ = PointerThrow.toss(from: p, facing: .right, screens: [], using: &rng)
        m.finishThrow()
        XCTAssertEqual(m.phase, .ready)
        // 던진 뒤 잠깐 숨 고르고 다시 쫓아온다
        for _ in 0..<(30 * 3) { XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 1200, y: 40))), .none) }
        var again = Mischief.Command.none
        for _ in 0..<60 where again == .none { again = m.tick(dt, input(cursor: CGPoint(x: 1200, y: 40))) }
        XCTAssertEqual(again, .chase(.right))
    }

    func testClickWhileBittenReleases() {
        var m = eager()
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)))
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 540, y: 40))), .startBite)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 540, y: 40), mouseDown: true)), .release)
        XCTAssertEqual(m.phase, .ready)
    }

    func testStopsWhenCannotPlay() {
        var m = eager()
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)))
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 710, y: 40), canPlay: false)), .stopChase)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 710, y: 40), canPlay: false)), .none)
    }

    func testBlockedChaseRetriesAfterShortRest() {
        var m = eager()
        _ = m.tick(dt, input(cursor: CGPoint(x: 1700, y: 40)))
        m.giveUp() // 벽에 막혀 돌아섬
        XCTAssertEqual(m.phase, .ready)
        var cmd = Mischief.Command.none
        var ticks = 0
        while cmd == .none, ticks < 300 { cmd = m.tick(dt, input(cursor: CGPoint(x: 1700, y: 40))); ticks += 1 }
        XCTAssertEqual(cmd, .chase(.right))
        XCTAssertEqual(Double(ticks) * dt, 2.5, accuracy: 0.1)
    }

    func testLeapReachesPointerAboveHead() {
        // 머리 위·옆 대각선도 몸을 날려 닿는다: 포물선을 따라가면 몸 중심이 포인터를 지난다
        for target in [CGPoint(x: 545, y: 260), CGPoint(x: 780, y: 300), CGPoint(x: 330, y: 150)] {
            guard let v = Mischief.leapVelocity(petFrame: pet, cursor: target) else { return XCTFail("\(target)") }
            var p = PetPhysics(origin: pet.origin, size: pet.size)
            p.velocity = v
            var closest = CGFloat.infinity
            for _ in 0..<60 { // 1초
                p.velocity.dy -= 1800 / 60
                p.velocity.dx *= pow(0.6, 1.0 / 60)
                p.origin.x += p.velocity.dx / 60
                p.origin.y += p.velocity.dy / 60
                let frame = CGRect(origin: p.origin, size: pet.size)
                closest = min(closest, hypot(frame.midX - target.x, frame.midY - target.y))
            }
            XCTAssertLessThan(closest, 30, "\(target)")
        }
        XCTAssertNil(Mischief.leapVelocity(petFrame: pet, cursor: CGPoint(x: 545, y: 900)), "너무 높음")
        XCTAssertNil(Mischief.leapVelocity(petFrame: pet, cursor: CGPoint(x: 1200, y: 100)), "너무 멂")
    }

    func testJumpsAfterShortCrouch() {
        var m = eager()
        let cursor = CGPoint(x: 545, y: 250)
        var first = Mischief.Command.none
        var ticks = 0
        while first == .none, ticks < 30 { first = m.tick(dt, input(cursor: cursor)); ticks += 1 }
        guard case .jump = first else { return XCTFail("\(first)") }
        XCTAssertGreaterThan(Double(ticks) * dt, 0.2, "바로 튀어 오르지 않고 잠깐 웅크린다")
    }

    func testRunsToWallWhenPointerTooHighThenLeapsOffWall() {
        var m = eager()
        let high = CGPoint(x: 560, y: 600)
        // 거의 아래인데 못 닿음 → 가까운 벽 쪽으로 달린다, 포인터 쪽에서 멀어져도 그 방향 유지
        XCTAssertEqual(m.tick(dt, input(cursor: high, wallDirection: .left)), .chase(.left))
        let away = pet.offsetBy(dx: -400, dy: 0)
        XCTAssertEqual(m.tick(dt, input(cursor: high, frame: away, wallDirection: .right)), .chase(.left))
        // 벽 타기 시작 → 오르다가 포인터가 닿는 거리면 벽을 차고 포인터 쪽으로
        m.didStartClimbing()
        XCTAssertNil(m.seekDirection)
        let low = CGRect(x: 100, y: 100, width: 80, height: 80)
        XCTAssertEqual(m.tick(dt, input(cursor: high, frame: low, grounded: false, climbingSide: .left)), .none, "아직 멂")
        let up = CGRect(x: 300, y: 420, width: 80, height: 80)
        guard case .jump(let v) = m.tick(dt, input(cursor: high, frame: up, grounded: false, climbingSide: .left)) else {
            return XCTFail("leap expected")
        }
        XCTAssertGreaterThan(v.dx, 0, "벽 반대쪽(포인터 쪽)으로")
        // 포인터가 벽 너머에 있으면 계속 오른다
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: -100, y: 600), frame: up, grounded: false, climbingSide: .left)), .none)
    }

    func testNearestWallDirection() {
        let screens = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1600, height: 1000)])
        let t = Terrain(screens: screens, windows: [WindowBox(id: 1, frame: CGRect(x: 900, y: 0, width: 300, height: 500))])
        XCTAssertEqual(t.nearestWallDirection(originX: 700, feetY: 0), .right, "창 옆면이 더 가깝다")
        XCTAssertEqual(t.nearestWallDirection(originX: 200, feetY: 0), .left, "화면 끝이 더 가깝다")
        // 같은 높이로 이어지는 옆 모니터 쪽 끝은 벽이 아니다
        let two = Terrain(screens: ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1000, height: 800),
                                                         CGRect(x: 1000, y: 0, width: 1000, height: 800)]))
        XCTAssertEqual(two.nearestWallDirection(originX: 900, feetY: 0), .left)
    }

    func testBrainClimbNowAndFace() {
        var rng = SeededGenerator(seed: 10)
        var b = PetBrain()
        b.handle(.chase(.right), using: &rng)
        b.handle(.climbNow, using: &rng)
        XCTAssertEqual(b.action, .climb)
        b.handle(.face(.left), using: &rng)
        XCTAssertEqual(b.direction, .left)
        var idle = PetBrain()
        idle.handle(.climbNow, using: &rng)
        XCTAssertEqual(idle.action, .idle, "걷는 중일 때만")
    }

    func testThrownPointerFliesForwardAndStaysOnScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1800, height: 1169), CGRect(x: -1920, y: 764, width: 1920, height: 1080)]
        var rng = SeededGenerator(seed: 8)
        let start = CGPoint(x: 1700, y: 60)
        let path = PointerThrow.toss(from: start, facing: .right, screens: screens, using: &rng)
        XCTAssertEqual(path.position(at: 0), start)
        XCTAssertGreaterThan(path.position(at: 0.2).y, start.y, "위로 솟았다가")
        for k in 0...30 {
            let p = path.position(at: Double(k) / 30)
            XCTAssertTrue(screens.contains { $0.contains(p) }, "\(p) off screen")
        }
        XCTAssertTrue(path.isFinished(at: path.duration))
        // 화면 오른쪽 끝에 막혀 붙는다
        XCTAssertEqual(path.position(at: path.duration).x, 1799)

        let left = PointerThrow.toss(from: CGPoint(x: 900, y: 300), facing: .left, screens: screens, using: &rng)
        XCTAssertLessThan(left.position(at: left.duration).x, 900)
    }

    func testBrainChaseKeepsWalkingTowardPointer() {
        var rng = SeededGenerator(seed: 9)
        var b = PetBrain()
        b.handle(.chase(.left), using: &rng)
        XCTAssertEqual(b.action, .walk)
        XCTAssertEqual(b.direction, .left)
        for _ in 0..<300 { b.tick(dt, using: &rng); b.handle(.chase(.right), using: &rng) }
        XCTAssertEqual(b.action, .walk, "쫓는 동안은 걷기가 안 끝난다")
        XCTAssertEqual(b.direction, .right)
        // 자는 중엔 안 깬다
        var s = PetBrain(); s.handle(.sleep, using: &rng); s.handle(.chase(.left), using: &rng)
        XCTAssertEqual(s.action, .sleep)
    }
}
