import XCTest
@testable import TermPet

/// 장난꾸러기 모드: 쫓기 → 물기 → 던지기 상태 머신
final class MischiefTests: XCTestCase {
    private let pet = CGRect(x: 500, y: 0, width: 80, height: 80)
    private let dt = 1.0 / 30

    private func input(cursor: CGPoint, frame: CGRect? = nil, canPlay: Bool = true,
                       mouseDown: Bool = false, grounded: Bool = true) -> Mischief.Input {
        Mischief.Input(petFrame: frame ?? pet, cursor: cursor, facing: .right,
                       canPlay: canPlay, mouseDown: mouseDown, grounded: grounded)
    }

    /// 쉬는 시간 없고 바로 쫓는 장난꾸러기
    private func eager() -> Mischief {
        var c = Mischief.Config(); c.startChancePerSecond = 1000
        var m = Mischief(config: c)
        var rng = SeededGenerator(seed: 1)
        // 켜자마자 3초는 쉼 → 지나가게 (포인터는 멀리서 계속 움직임)
        for k in 0..<120 { _ = m.tick(dt, input(cursor: CGPoint(x: 2000 + CGFloat(k), y: 900)), using: &rng) }
        return m
    }

    func testChasesMovingPointerNearby() {
        var m = eager()
        var rng = SeededGenerator(seed: 2)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 800, y: 40)), using: &rng), .chase(.right))
        XCTAssertEqual(m.phase, .chasing)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 300, y: 40)), using: &rng), .chase(.left))
    }

    func testIgnoresFarOrStillPointerAndPressedButton() {
        var rng = SeededGenerator(seed: 3)
        var far = eager()
        XCTAssertEqual(far.tick(dt, input(cursor: CGPoint(x: 1500, y: 40)), using: &rng), .none)

        // 포인터가 멈추면(타이핑 중 등) 흥미를 잃는다
        var still = eager()
        XCTAssertEqual(still.tick(dt, input(cursor: CGPoint(x: 700, y: 40)), using: &rng), .chase(.right))
        var last = Mischief.Command.none
        for _ in 0..<90 where still.phase == .chasing { last = still.tick(dt, input(cursor: CGPoint(x: 700, y: 40)), using: &rng) }
        XCTAssertEqual(last, .stopChase)
        XCTAssertEqual(still.phase, .ready)

        // 드래그 중이면 쫓지도 않는다
        var pressed = eager()
        XCTAssertEqual(pressed.tick(dt, input(cursor: CGPoint(x: 700, y: 40), mouseDown: true), using: &rng), .none)
        XCTAssertEqual(pressed.phase, .ready)
    }

    func testCatchBiteThenThrow() {
        var m = eager()
        var rng = SeededGenerator(seed: 4)
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)), using: &rng)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 560, y: 40)), using: &rng), .startBite)
        // 흔드는 동안 포인터를 입에 문다 (입은 바라보는 쪽 앞)
        guard case .holdPointer(let p) = m.tick(dt, input(cursor: CGPoint(x: 560, y: 41)), using: &rng) else {
            return XCTFail("hold expected")
        }
        XCTAssertTrue(pet.insetBy(dx: -10, dy: -10).contains(p))
        XCTAssertGreaterThan(p.x, pet.midX)
        var cmd = Mischief.Command.none
        for _ in 0..<60 where cmd != .throwPointer { cmd = m.tick(dt, input(cursor: CGPoint(x: 560, y: 42)), using: &rng) }
        XCTAssertEqual(cmd, .throwPointer)
        XCTAssertEqual(m.phase, .throwing)
        m.finishThrow()
        XCTAssertEqual(m.phase, .ready)
        // 던진 뒤엔 한동안 쉰다
        for k in 0..<(30 * 10) {
            XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 600 + CGFloat(k % 50), y: 40)), using: &rng), .none)
        }
    }

    func testClickWhileBittenReleases() {
        var m = eager()
        var rng = SeededGenerator(seed: 5)
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)), using: &rng)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 540, y: 40)), using: &rng), .startBite)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 540, y: 40), mouseDown: true), using: &rng), .release)
        XCTAssertEqual(m.phase, .ready)
    }

    func testStopsWhenCannotPlay() {
        var m = eager()
        var rng = SeededGenerator(seed: 6)
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)), using: &rng)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 710, y: 40), canPlay: false), using: &rng), .stopChase)
    }

    func testGivesUpWhenPointerRunsAway() {
        var m = eager()
        var rng = SeededGenerator(seed: 7)
        _ = m.tick(dt, input(cursor: CGPoint(x: 700, y: 40)), using: &rng)
        XCTAssertEqual(m.tick(dt, input(cursor: CGPoint(x: 1600, y: 40)), using: &rng), .stopChase)
        XCTAssertEqual(m.phase, .ready)
    }

    func testJumpsAtPointerAboveHead() {
        // 거의 바로 위 120pt → 점프, 너무 높으면 안 뛴다
        let v = Mischief.jumpVelocity(petFrame: pet, cursor: CGPoint(x: 545, y: 200))
        XCTAssertNotNil(v)
        // 그 초속이면 머리가 포인터 높이까지 닿는다
        let rise = v!.dy * v!.dy / (2 * 1800)
        XCTAssertGreaterThanOrEqual(pet.maxY + rise, 200)
        XCTAssertNil(Mischief.jumpVelocity(petFrame: pet, cursor: CGPoint(x: 545, y: 900)))
        XCTAssertNil(Mischief.jumpVelocity(petFrame: pet, cursor: CGPoint(x: 800, y: 200)))
        XCTAssertNil(Mischief.jumpVelocity(petFrame: pet, cursor: CGPoint(x: 545, y: 50)), "닿는 높이면 점프 안 함")
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
