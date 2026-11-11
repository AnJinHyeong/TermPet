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
        _ = PointerThrow.toss(from: p, screens: [], using: &rng)
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

    /// 몸을 날린 포물선을 실제 물리처럼 따라가며 몸 중심이 포인터에 가장 가까웠던 거리와 가장 높이 오른 몸 윗면
    private func fly(_ v: CGVector, from frame: CGRect, to target: CGPoint) -> (closest: CGFloat, top: CGFloat) {
        var p = PetPhysics(origin: frame.origin, size: frame.size)
        p.velocity = v
        var closest = CGFloat.infinity, top = frame.maxY
        for _ in 0..<90 {
            p.velocity.dy -= 1800 / 60
            p.velocity.dx *= pow(0.6, 1.0 / 60)
            p.origin.x += p.velocity.dx / 60
            p.origin.y += p.velocity.dy / 60
            let f = CGRect(origin: p.origin, size: frame.size)
            closest = min(closest, hypot(f.midX - target.x, f.midY - target.y))
            top = max(top, f.maxY)
        }
        return (closest, top)
    }

    /// 벽에 매달려 포인터 높이까지 올라오면 멀리(최대 1000pt) 날아가 닿는다. 천장 근처면 낮고 빠르게.
    func testWallLeapReachesFarPointer() {
        let onWall = CGRect(x: 0, y: 700, width: 80, height: 80)
        for target in [CGPoint(x: 900, y: 740), CGPoint(x: 600, y: 600), CGPoint(x: 1000, y: 800)] {
            guard let v = Mischief.wallLeap(petFrame: onWall, cursor: target) else { return XCTFail("\(target)") }
            XCTAssertLessThan(fly(v, from: onWall, to: target).closest, 30, "\(target)")
        }
        // 천장까지 40pt 남음 → 머리를 박지 않고 (꼭대기가 천장 아래) 그래도 닿는다
        let target = CGPoint(x: 700, y: 740)
        guard let v = Mischief.wallLeap(petFrame: onWall, cursor: target, headroom: 40) else { return XCTFail() }
        let flight = fly(v, from: onWall, to: target)
        XCTAssertLessThan(flight.closest, 30)
        XCTAssertLessThanOrEqual(flight.top, onWall.maxY + 41)
        XCTAssertNil(Mischief.wallLeap(petFrame: onWall, cursor: CGPoint(x: 1300, y: 740)), "너무 멂")
    }

    /// 벽 타는 중: 포인터가 멀면 포인터 높이까지 올라온 뒤에 멀리 몸을 날린다
    func testClimbsToPointerHeightThenLeapsFar() {
        var m = eager()
        _ = m.tick(dt, input(cursor: CGPoint(x: 800, y: 700), wallDirection: .left))
        m.didStartClimbing()
        let far = CGPoint(x: 800, y: 700)
        let low = CGRect(x: 0, y: 200, width: 80, height: 80)
        XCTAssertEqual(m.tick(dt, input(cursor: far, frame: low, grounded: false, climbingSide: .left)), .none, "아직 아래")
        let level = CGRect(x: 0, y: 650, width: 80, height: 80)
        guard case .jump(let v) = m.tick(dt, input(cursor: far, frame: level, grounded: false, climbingSide: .left)) else {
            return XCTFail("far leap expected")
        }
        XCTAssertGreaterThan(v.dx, 0)
    }

    /// 포인터가 너무 높으면 포인터 밑으로 가지 않고 포인터에 가장 가까운 벽으로 곧장 간다
    func testWallNearestToPointer() {
        let screens = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1600, height: 1000)])
        let t = Terrain(screens: screens)
        XCTAssertEqual(t.nearestWallDirection(originX: 300, feetY: 0, targetX: 1400), .right, "펫은 왼쪽 끝이 가깝지만 포인터는 오른쪽 끝")
        XCTAssertEqual(t.nearestWallDirection(originX: 300, feetY: 0), .left)
        var m = eager()
        let pet = CGRect(x: 300, y: 0, width: 80, height: 80)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 1400, y: 900), frame: pet, wallDirection: .right)), .chase(.right))
    }

    /// 공중에서 물면 문 채로 떨어지고, 땅에 닿은 뒤에 던진다
    func testBiteInAirThrowsAfterLanding() {
        var m = eager()
        let cursor = CGPoint(x: 540, y: 40)
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)))
        XCTAssertEqual(m.tick(dt, input(cursor: cursor, grounded: false)), .startBite)
        for _ in 0..<90 { // 3초 동안 떨어지는 중 (원래는 1.3초에 던짐)
            guard case .holdPointer = m.tick(dt, input(cursor: cursor, grounded: false)) else { return XCTFail("물고 떨어지는 중") }
        }
        XCTAssertEqual(m.tick(dt, input(cursor: cursor)), .throwPointer, "착지하자마자 던진다")
    }

    /// 던질 쪽 공간이 모자라면 반대쪽으로, 옆 모니터로 이어지면 그쪽 공간도 센다
    func testThrowPicksSideWithRoom() {
        var rng = SystemRandomNumberGenerator()
        let one = [CGRect(x: 0, y: 0, width: 1800, height: 1169)]
        var directions = Set<Direction>(), durations = Set<Double>(), speeds = Set<CGFloat>()
        for _ in 0..<40 {
            XCTAssertEqual(PointerThrow.toss(from: CGPoint(x: 1750, y: 300), screens: one, using: &rng).direction, .left)
            XCTAssertEqual(PointerThrow.toss(from: CGPoint(x: 50, y: 300), screens: one, using: &rng).direction, .right)
            let mid = PointerThrow.toss(from: CGPoint(x: 900, y: 300), screens: one, using: &rng)
            directions.insert(mid.direction); durations.insert(mid.duration); speeds.insert(abs(mid.velocity.dx))
        }
        // 공간이 넉넉하면 방향·세기·시간이 매번 랜덤
        XCTAssertEqual(directions.count, 2)
        XCTAssertGreaterThan(durations.count, 10)
        XCTAssertGreaterThan(speeds.count, 10)
        // 높이도 랜덤: 위쪽 공간이 넉넉하면 높이 솟구치기도 하고, 천장은 넘지 않는다
        var apexes: [CGFloat] = []
        for _ in 0..<60 {
            let path = PointerThrow.toss(from: CGPoint(x: 900, y: 100), screens: one, using: &rng)
            let apex = path.velocity.dy * path.velocity.dy / (2 * path.gravity)
            XCTAssertLessThanOrEqual(apex, 1069 * 0.9 + 1)
            XCTAssertGreaterThan(path.duration, Double(path.velocity.dy / path.gravity), "꼭대기까지는 날아간다")
            apexes.append(apex)
        }
        XCTAssertGreaterThan(apexes.max()!, 600)
        XCTAssertLessThan(apexes.min()!, 300)
        // 천장 바로 아래면 낮게
        let low = PointerThrow.toss(from: CGPoint(x: 900, y: 1100), screens: one, using: &rng)
        XCTAssertLessThanOrEqual(low.velocity.dy * low.velocity.dy / (2 * low.gravity), 61)
        // 맥북 왼쪽 끝이어도 LG가 같은 높이로 이어져 있으면 왼쪽으로 던질 수 있다
        let two = one + [CGRect(x: -1920, y: 764, width: 1920, height: 1080)]
        XCTAssertEqual(PointerThrow.room(from: CGPoint(x: 50, y: 900), toward: .left, screens: two), 1970)
        XCTAssertEqual(PointerThrow.room(from: CGPoint(x: 50, y: 300), toward: .left, screens: two), 50)
        XCTAssertEqual(PointerThrow.toss(from: CGPoint(x: 1750, y: 900), screens: two, using: &rng).direction, .left)
        // 양쪽 다 좁으면 남은 공간 안에 떨어지게 살살
        let narrow = [CGRect(x: 0, y: 0, width: 600, height: 1000)]
        let soft = PointerThrow.toss(from: CGPoint(x: 300, y: 500), screens: narrow, using: &rng)
        XCTAssertLessThanOrEqual(abs(soft.velocity.dx) * CGFloat(soft.duration), 300)
    }

    /// 던지는 중에 마우스를 움직이면 그만큼 옮겨진 길로 날아간다
    func testThrowFollowsUserMove() {
        var path = PointerThrow(start: CGPoint(x: 500, y: 500), velocity: CGVector(dx: 100, dy: 0), gravity: 0,
                                screens: [CGRect(x: 0, y: 0, width: 2000, height: 1000)])
        path.offset = CGVector(dx: -200, dy: 50)
        XCTAssertEqual(path.position(at: 0.5), CGPoint(x: 350, y: 550))
        XCTAssertEqual(PointerControl.userMove(since: CGPoint(x: 10, y: 10), now: CGPoint(x: 10.4, y: 10)), .zero)
        XCTAssertEqual(PointerControl.userMove(since: CGPoint(x: 10, y: 10), now: CGPoint(x: 30, y: 5)), CGVector(dx: 20, dy: -5))
        XCTAssertEqual(PointerControl.userMove(since: nil, now: CGPoint(x: 30, y: 5)), .zero)
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

    func testBitePoseFallsBackToAngry() {
        XCTAssertEqual(SpriteCharacter.fallbacks(for: .bite), [.bite, .angry, .idle])
        XCTAssertEqual(SpriteCharacter.fallbacks(for: .toss), [.toss, .happy, .idle])
        XCTAssertEqual(CharacterPack.parseStateKey("throw")?.0, .toss)
        XCTAssertEqual(CharacterPack.parseStateKey("bite")?.0, .bite)
        XCTAssertEqual(CharacterPack.parseStateKey("bite.2")?.1, 2)
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
        let path = PointerThrow.toss(from: start, screens: screens, using: &rng)
        XCTAssertEqual(path.position(at: 0), start)
        XCTAssertGreaterThan(path.position(at: 0.2).y, start.y, "위로 솟았다가")
        for k in 0...30 {
            let p = path.position(at: Double(k) / 30)
            XCTAssertTrue(screens.contains { $0.contains(p) }, "\(p) off screen")
        }
        XCTAssertTrue(path.isFinished(at: path.duration))
        // 오른쪽 끝이라 공간이 없으니 왼쪽으로 던진다
        XCTAssertEqual(path.direction, .left)
        XCTAssertLessThan(path.position(at: path.duration).x, start.x)
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
