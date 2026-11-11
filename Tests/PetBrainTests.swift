import XCTest
@testable import TermPet

final class PetBrainTests: XCTestCase {
    private var rng = SeededGenerator(seed: 42)

    private func makeBrain(sleepAfter: TimeInterval = 600) -> PetBrain {
        var config = PetBrain.Config()
        config.idleDuration = 2...2
        config.walkDuration = 3...3
        config.reactionDuration = 4
        config.clickReactionDuration = 1.5
        config.sleepAfter = sleepAfter
        return PetBrain(config: config)
    }

    /// dt 간격으로 total 초만큼 진행
    private func run(_ brain: inout PetBrain, for total: TimeInterval, dt: TimeInterval = 0.1) {
        var t: TimeInterval = 0
        while t < total - 1e-9 {
            brain.tick(dt, using: &rng)
            t += dt
        }
    }

    func testStartsIdle() {
        XCTAssertEqual(makeBrain().action, .idle)
    }

    func testIdleTransitionsToWalkThenBackToIdle() {
        var brain = makeBrain()
        run(&brain, for: 2.05)
        XCTAssertEqual(brain.action, .walk)
        run(&brain, for: 3.05)
        XCTAssertEqual(brain.action, .idle)
    }

    func testHitWallFlipsDirection() {
        var brain = makeBrain()
        let before = brain.direction
        brain.handle(.hitWall(), using: &rng)
        XCTAssertEqual(brain.direction, before.flipped)
    }

    func testFallsAsleepAfterInactivity() {
        var brain = makeBrain(sleepAfter: 10)
        run(&brain, for: 9.9)
        XCTAssertNotEqual(brain.action, .sleep)
        run(&brain, for: 0.2)
        XCTAssertEqual(brain.action, .sleep)
        // 잠든 뒤엔 시간이 지나도 계속 잔다
        run(&brain, for: 30)
        XCTAssertEqual(brain.action, .sleep)
    }

    func testClickWhileSleepingDoesNotWake() {
        var brain = makeBrain()
        brain.handle(.sleep, using: &rng)
        brain.handle(.clicked, using: &rng)
        XCTAssertEqual(brain.action, .sleep)
        XCTAssertTrue(brain.isAsleep)
        brain.handle(.wake, using: &rng) // 깨우기 토글로만 깬다
        XCTAssertEqual(brain.action, .idle)
        XCTAssertFalse(brain.isAsleep)
    }

    func testCarryingSleepingPetKeepsItAsleep() {
        var brain = makeBrain()
        brain.handle(.sleep, using: &rng)
        brain.handle(.dragStarted, using: &rng)
        XCTAssertEqual(brain.action, .dragged)  // 물리상으론 들린 상태
        XCTAssertTrue(brain.isAsleep)           // 하지만 계속 자는 중
        run(&brain, for: 5)
        brain.handle(.startFall, using: &rng)
        brain.handle(.landed, using: &rng)
        XCTAssertEqual(brain.action, .sleep)
        run(&brain, for: 60)
        XCTAssertEqual(brain.action, .sleep)
    }

    func testSleepingPetClimbingOutOfDockStaysAsleep() {
        var brain = makeBrain()
        brain.handle(.sleep, using: &rng)
        brain.handle(.climbOutOfDock, using: &rng)
        brain.handle(.climbedUp, using: &rng)
        XCTAssertEqual(brain.action, .sleep)
    }

    func testEventsDoNotWakeUserPutToSleepButWakeAutoSleep() {
        var put = makeBrain()
        put.handle(.sleep, using: &rng)
        put.handle(.react(.happy), using: &rng)
        XCTAssertEqual(put.action, .sleep)

        var auto = makeBrain(sleepAfter: 10)
        run(&auto, for: 11)
        XCTAssertEqual(auto.action, .sleep)
        auto.handle(.clicked, using: &rng)
        XCTAssertEqual(auto.action, .sleep, "클릭으론 안 깬다")
        auto.handle(.react(.happy), using: &rng)
        XCTAssertEqual(auto.action, .happy, "저절로 잠든 건 알림에 깬다")
        XCTAssertFalse(auto.isAsleep)
    }

    func testClickTriggersShortHappy() {
        var brain = makeBrain()
        brain.handle(.clicked, using: &rng)
        XCTAssertEqual(brain.action, .happy)
        run(&brain, for: 1.6)
        XCTAssertEqual(brain.action, .idle)
    }

    func testReactionReturnsToIdleAfterDuration() {
        for reaction in [PetAction.happy, .angry, .ask, .talk] {
            var brain = makeBrain()
            brain.handle(.react(reaction), using: &rng)
            XCTAssertEqual(brain.action, reaction)
            run(&brain, for: 3.9)
            XCTAssertEqual(brain.action, reaction, "\(reaction) ended too early")
            run(&brain, for: 0.2)
            XCTAssertEqual(brain.action, .idle, "\(reaction) did not end")
        }
    }

    func testReactionWithCustomDuration() {
        var brain = makeBrain()
        brain.handle(.react(.ask, duration: 1), using: &rng)
        run(&brain, for: 1.1)
        XCTAssertEqual(brain.action, .idle)
    }

    func testReactionResetsInactivity() {
        var brain = makeBrain(sleepAfter: 10)
        run(&brain, for: 8)
        brain.handle(.react(.happy, duration: 0.5), using: &rng)
        XCTAssertEqual(brain.inactivity, 0)
        run(&brain, for: 5)
        XCTAssertNotEqual(brain.action, .sleep)
    }

    func testDragFallLandCycle() {
        var brain = makeBrain()
        brain.handle(.dragStarted, using: &rng)
        XCTAssertEqual(brain.action, .dragged)
        run(&brain, for: 100) // 잡고 있는 동안은 시간이 지나도 그대로
        XCTAssertEqual(brain.action, .dragged)

        brain.handle(.startFall, using: &rng)
        XCTAssertEqual(brain.action, .fall)
        brain.handle(.landed, using: &rng)
        XCTAssertEqual(brain.action, .idle)
    }

    func testReactionsIgnoredWhileDraggedOrFalling() {
        var brain = makeBrain()
        brain.handle(.dragStarted, using: &rng)
        brain.handle(.react(.happy), using: &rng)
        brain.handle(.sleep, using: &rng)
        brain.handle(.clicked, using: &rng)
        XCTAssertEqual(brain.action, .dragged)

        brain.handle(.startFall, using: &rng)
        brain.handle(.react(.angry), using: &rng)
        XCTAssertEqual(brain.action, .fall)
    }

    func testLandedIgnoredWhenNotFalling() {
        var brain = makeBrain()
        brain.handle(.react(.happy), using: &rng)
        brain.handle(.landed, using: &rng)
        XCTAssertEqual(brain.action, .happy)
    }

    func testWakeOnlyAffectsSleep() {
        var brain = makeBrain()
        brain.handle(.react(.angry), using: &rng)
        brain.handle(.wake, using: &rng)
        XCTAssertEqual(brain.action, .angry)

        brain.handle(.sleep, using: &rng)
        XCTAssertEqual(brain.action, .sleep)
        brain.handle(.wake, using: &rng)
        XCTAssertEqual(brain.action, .idle)
    }

    func testWalkDirectionIsRandomized() {
        var directions = Set<String>()
        for _ in 0..<20 {
            var brain = makeBrain()
            run(&brain, for: 2.05)
            directions.insert("\(brain.direction)")
        }
        XCTAssertEqual(directions.count, 2)
    }
}

@MainActor
final class LoopFPSTests: XCTestCase {
    func testFullSpeedOnlyWhileMoving() {
        XCTAssertEqual(PetController.loopFPS(for: .walk, maxFPS: 60), 30)
        for action in [PetAction.fall, .dragged] {
            XCTAssertEqual(PetController.loopFPS(for: action, maxFPS: 60), 60, "\(action)")
        }
        XCTAssertEqual(PetController.loopFPS(for: .idle, maxFPS: 60), 12)
        XCTAssertEqual(PetController.loopFPS(for: .sleep, maxFPS: 60), 6)
        XCTAssertEqual(PetController.loopFPS(for: .happy, maxFPS: 60), 30)
        XCTAssertEqual(PetController.loopFPS(for: .idle, maxFPS: 12), 12) // 설정값보다 높이지 않음
    }
}

final class PetBrainDockRiseTests: XCTestCase {
    func testClimbOutOfDockEntersClimbFromIdleOrWalk() {
        var rng = SeededGenerator(seed: 1)
        var brain = PetBrain()
        brain.handle(.climbOutOfDock, using: &rng)
        XCTAssertEqual(brain.action, .climb)
        brain.handle(.climbedUp, using: &rng)
        XCTAssertEqual(brain.action, .walk)
    }

    func testClimbOutOfDockIgnoredWhileDraggedOrFalling() {
        var rng = SeededGenerator(seed: 1)
        var brain = PetBrain()
        brain.handle(.dragStarted, using: &rng)
        brain.handle(.climbOutOfDock, using: &rng)
        XCTAssertEqual(brain.action, .dragged)
        brain.handle(.startFall, using: &rng)
        brain.handle(.climbOutOfDock, using: &rng)
        XCTAssertEqual(brain.action, .fall)
    }
}
