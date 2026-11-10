import XCTest
@testable import TermPet

/// 창 위 산책: 지형(선반·벽) 계산 + 물리(걷기·오르기·뛰어내리기·던지기)
final class TerrainTests: XCTestCase {
    private let pet = CGSize(width: 80, height: 80)
    private let screen = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 1600, height: 1000)])

    private func terrain(_ windows: [WindowBox]) -> Terrain {
        Terrain(screens: screen, windows: windows, petSize: pet)
    }

    // MARK: - 선반

    func testWindowTopIsLedge() {
        let t = terrain([WindowBox(id: 1, frame: CGRect(x: 200, y: 0, width: 600, height: 400))])
        XCTAssertEqual(t.ledges, [Terrain.Ledge(minX: 200, maxX: 800, y: 400, windowID: 1)])
    }

    func testFrontWindowHidesPartOfLedge() {
        // 2번(뒤) 창 윗변의 가운데를 1번(앞) 창이 덮는다 → 양쪽 두 구간만 남음
        let t = terrain([
            WindowBox(id: 1, frame: CGRect(x: 400, y: 100, width: 200, height: 500)),
            WindowBox(id: 2, frame: CGRect(x: 200, y: 0, width: 600, height: 400)),
        ])
        let back = t.ledges.filter { $0.windowID == 2 }
        XCTAssertEqual(back.map(\.minX), [200, 600])
        XCTAssertEqual(back.map(\.maxX), [400, 800])
    }

    func testNoLedgeWithoutHeadroom() {
        // 꽉 찬(최대화) 창: 윗변이 메뉴바 바로 아래라 올라설 수 없음
        let t = terrain([WindowBox(id: 1, frame: CGRect(x: 0, y: 0, width: 1600, height: 990))])
        XCTAssertTrue(t.ledges.isEmpty)
    }

    func testNarrowLedgeIgnored() {
        let t = terrain([
            WindowBox(id: 1, frame: CGRect(x: 230, y: 100, width: 600, height: 500)),
            WindowBox(id: 2, frame: CGRect(x: 200, y: 0, width: 600, height: 400)), // 남는 폭 30pt
        ])
        XCTAssertTrue(t.ledges.filter { $0.windowID == 2 }.isEmpty)
    }

    func testLandsOnWindowTopBeforeFloor() {
        let t = terrain([WindowBox(id: 7, frame: CGRect(x: 200, y: 0, width: 600, height: 400))])
        XCTAssertEqual(t.landing(centerX: 500, fromY: 410, toY: 390), Terrain.Floor(y: 400, windowID: 7))
        XCTAssertNil(t.landing(centerX: 500, fromY: 600, toY: 500))           // 아직 공중
        XCTAssertEqual(t.landing(centerX: 1000, fromY: 10, toY: -5), Terrain.Floor(y: 0, windowID: nil))
    }

    // MARK: - 벽

    func testWalkingIntoWindowSideHitsWall() {
        let t = terrain([WindowBox(id: 3, frame: CGRect(x: 500, y: 0, width: 400, height: 300))])
        var p = PetPhysics(origin: CGPoint(x: 410, y: 0), size: pet)
        let r = p.walk(direction: .right, speed: 100, dt: 0.2, terrain: t)
        XCTAssertEqual(r, .hitWall(Terrain.Wall(x: 500, top: 300, windowID: 3, side: .right)))
        XCTAssertEqual(p.origin.x, 420) // 벽에 딱 붙음
    }

    func testWindowAbovePetIsNotWall() {
        // 창 아래쪽이 펫 머리보다 위 → 그 밑을 지나간다
        let t = terrain([WindowBox(id: 3, frame: CGRect(x: 500, y: 200, width: 400, height: 300))])
        var p = PetPhysics(origin: CGPoint(x: 410, y: 0), size: pet)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.2, terrain: t), .moved)
    }

    func testAlreadyInFrontOfWindowIsNotWall() {
        let t = terrain([WindowBox(id: 3, frame: CGRect(x: 300, y: 0, width: 400, height: 300))])
        var p = PetPhysics(origin: CGPoint(x: 400, y: 0), size: pet)
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.2, terrain: t), .moved)
    }

    func testLowStepIsClimbedAutomatically() {
        // 높이 150 창 → 벽
        let tall = terrain([WindowBox(id: 4, frame: CGRect(x: 500, y: 0, width: 400, height: 150))])
        var p = PetPhysics(origin: CGPoint(x: 410, y: 0), size: pet)
        if case .hitWall = p.walk(direction: .right, speed: 100, dt: 0.2, terrain: tall) {} else { XCTFail("wall expected") }

        // 높이 10 창(키의 22% 미만 턱) → 그냥 올라선다
        let low = terrain([WindowBox(id: 5, frame: CGRect(x: 500, y: 0, width: 400, height: 10))])
        var q = PetPhysics(origin: CGPoint(x: 410, y: 0), size: pet)
        XCTAssertEqual(q.walk(direction: .right, speed: 100, dt: 0.2, terrain: low), .moved)
        XCTAssertEqual(q.origin.y, 10)
        XCTAssertEqual(q.standingOn, 5)
    }

    // MARK: - 창 위 걷기

    func testWalkingOnWindowStopsAtEdge() {
        let t = terrain([WindowBox(id: 1, frame: CGRect(x: 200, y: 0, width: 600, height: 400))])
        var p = PetPhysics(origin: CGPoint(x: 700, y: 400), size: pet)
        p.standingOn = 1
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.1, terrain: t), .moved)
        // 몸 중심이 오른쪽 끝(800)을 넘으려 하면 멈추고 알린다
        var result = PetPhysics.WalkResult.moved
        for _ in 0..<20 where result == .moved {
            result = p.walk(direction: .right, speed: 100, dt: 0.1, terrain: t)
        }
        XCTAssertEqual(result, .reachedEdge)
        XCTAssertLessThanOrEqual(p.centerX, 800)
    }

    func testStandingWindowGoneStartsFalling() {
        let t = terrain([])
        var p = PetPhysics(origin: CGPoint(x: 300, y: 400), size: pet)
        p.standingOn = 1
        XCTAssertEqual(p.walk(direction: .right, speed: 100, dt: 0.1, terrain: t), .startFalling)
    }

    // MARK: - 오르기

    func testClimbsWallAndStepsOntoWindowTop() {
        let t = terrain([WindowBox(id: 3, frame: CGRect(x: 500, y: 0, width: 400, height: 300))])
        let wall = Terrain.Wall(x: 500, top: 300, windowID: 3, side: .right)
        var p = PetPhysics(origin: CGPoint(x: 420, y: 0), size: pet)
        var result = PetPhysics.ClimbResult.climbing
        var steps = 0
        while result == .climbing && steps < 1000 {
            result = p.climb(wall, speed: 60, dt: 0.1, terrain: t, limitY: .infinity)
            steps += 1
        }
        XCTAssertEqual(result, .reachedTop(windowID: 3))
        XCTAssertEqual(p.origin.y, 300)
        XCTAssertGreaterThanOrEqual(p.origin.x, 500) // 창 위로 올라섬
        XCTAssertEqual(p.standingOn, 3)
    }

    func testClimbWithoutTopLetsGoAtLimit() {
        let t = terrain([])
        let wall = Terrain.Wall(x: 1600, top: 1000, windowID: nil, side: .right) // 화면 끝
        var p = PetPhysics(origin: CGPoint(x: 1520, y: 0), size: pet)
        var result = PetPhysics.ClimbResult.climbing
        for _ in 0..<1000 where result == .climbing {
            result = p.climb(wall, speed: 60, dt: 0.1, terrain: t, limitY: 200)
        }
        XCTAssertEqual(result, .letGo)
        XCTAssertEqual(p.origin.y, 200)
    }

    // MARK: - 던지기 / 창 따라가기

    func testThrownPetBouncesOffScreenEdgeAndLands() {
        let t = terrain([])
        var p = PetPhysics(origin: CGPoint(x: 1400, y: 500), size: pet)
        p.prepareFall(terrain: t, velocity: CGVector(dx: 1500, dy: 300))
        var landed = false
        for _ in 0..<2000 where !landed { landed = p.fall(dt: 1.0 / 60, terrain: t) }
        XCTAssertTrue(landed)
        XCTAssertEqual(p.origin.y, 0)
        XCTAssertLessThanOrEqual(p.origin.x + pet.width, 1600)
    }

    func testRidesMovingWindow() {
        var p = PetPhysics(origin: CGPoint(x: 300, y: 400), size: pet)
        p.ride(from: CGRect(x: 200, y: 0, width: 600, height: 400), to: CGRect(x: 250, y: 30, width: 600, height: 400))
        XCTAssertEqual(p.origin, CGPoint(x: 350, y: 430))
    }

    func testThrowVelocityFromDragTrail() {
        let slow = PetController.throwVelocity([(0, .zero), (0.1, CGPoint(x: 5, y: 0))])
        XCTAssertEqual(slow, .zero)
        let fast = PetController.throwVelocity([(0, .zero), (0.05, CGPoint(x: 400, y: 0))])
        XCTAssertEqual(fast.dx, 1800, accuracy: 0.1) // 8000pt/s → 상한 1800
    }

    // MARK: - 창 목록 읽기

    func testWindowScannerConvertsAndFilters() {
        let infos: [[String: Any]] = [
            ["kCGWindowLayer": 0, "kCGWindowOwnerPID": Int32(10), "kCGWindowNumber": 1, "kCGWindowAlpha": 1.0,
             "kCGWindowBounds": ["X": 100, "Y": 50, "Width": 400, "Height": 300] as NSDictionary],
            ["kCGWindowLayer": 25, "kCGWindowOwnerPID": Int32(10), "kCGWindowNumber": 2,         // 메뉴바 등 다른 층
             "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 400, "Height": 300] as NSDictionary],
            ["kCGWindowLayer": 0, "kCGWindowOwnerPID": Int32(99), "kCGWindowNumber": 3,           // 내 앱
             "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 400, "Height": 300] as NSDictionary],
            ["kCGWindowLayer": 0, "kCGWindowOwnerPID": Int32(10), "kCGWindowNumber": 4,           // 너무 작음
             "kCGWindowBounds": ["X": 0, "Y": 0, "Width": 40, "Height": 30] as NSDictionary],
        ]
        let boxes = WindowScanner.boxes(from: infos, ownPID: 99, primaryHeight: 1000)
        XCTAssertEqual(boxes, [WindowBox(id: 1, frame: CGRect(x: 100, y: 650, width: 400, height: 300), owner: 10)])
    }
}

/// 두뇌: 벽·끝에서의 선택, 포즈 변형
final class PetBrainClimbTests: XCTestCase {
    private func walkingBrain(_ config: PetBrain.Config) -> PetBrain {
        var c = config
        c.idleDuration = 0.1...0.1
        var b = PetBrain(config: c)
        var rng = SeededGenerator(seed: 1)
        b.tick(0.2, using: &rng)
        XCTAssertEqual(b.action, .walk)
        return b
    }

    func testAlwaysClimbsWindowWhenChanceIsOne() {
        var c = PetBrain.Config(); c.climbWindowChance = 1
        var b = walkingBrain(c)
        var rng = SeededGenerator(seed: 2)
        b.handle(.hitWall(window: true), using: &rng)
        XCTAssertEqual(b.action, .climb)
        // 오르는 중엔 이벤트 반응으로 끊기지 않는다
        b.handle(.react(.happy), using: &rng)
        XCTAssertEqual(b.action, .climb)
        b.handle(.climbedUp, using: &rng)
        XCTAssertEqual(b.action, .walk)
    }

    func testTurnsAroundWhenNotClimbing() {
        var c = PetBrain.Config(); c.climbScreenChance = 0
        var b = walkingBrain(c)
        let dir = b.direction
        var rng = SeededGenerator(seed: 3)
        b.handle(.hitWall(window: false), using: &rng)
        XCTAssertEqual(b.action, .walk)
        XCTAssertEqual(b.direction, dir.flipped)
    }

    func testLetGoJumpsAwayFromWall() {
        var c = PetBrain.Config(); c.climbWindowChance = 1
        var b = walkingBrain(c)
        var rng = SeededGenerator(seed: 4)
        b.handle(.hitWall(window: true), using: &rng)
        let dir = b.direction
        b.handle(.letGo, using: &rng)
        XCTAssertEqual(b.action, .fall)
        XCTAssertEqual(b.direction, dir.flipped)
        b.handle(.landed, using: &rng)
        XCTAssertEqual(b.action, .idle)
    }

    func testEdgeJumpOrTurn() {
        var c = PetBrain.Config(); c.edgeJumpChance = 1
        var b = walkingBrain(c)
        var rng = SeededGenerator(seed: 5)
        b.handle(.reachedEdge, using: &rng)
        XCTAssertEqual(b.action, .fall)

        c.edgeJumpChance = 0
        var d = walkingBrain(c)
        let dir = d.direction
        d.handle(.reachedEdge, using: &rng)
        XCTAssertEqual(d.action, .walk)
        XCTAssertEqual(d.direction, dir.flipped)
    }

    func testVariantChangesOnNewState() {
        var b = PetBrain()
        var rng = SeededGenerator(seed: 6)
        var seen = Set<Int>()
        for _ in 0..<20 {
            b.handle(.react(.happy), using: &rng); seen.insert(b.variant)
            b.handle(.react(.angry), using: &rng); seen.insert(b.variant)
        }
        XCTAssertGreaterThan(seen.count, 5)
    }
}

/// 그림 팩: 포즈 변형(idle.2), 동작별 방향, 친구 팩 목록
final class FriendPackTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("termpet-friends-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testParseStateKey() {
        XCTAssertEqual(CharacterPack.parseStateKey("idle")?.0, .idle)
        XCTAssertEqual(CharacterPack.parseStateKey("walk.2")?.1, 2)
        XCTAssertNil(CharacterPack.parseStateKey("walk.x"))
        XCTAssertNil(CharacterPack.parseStateKey("dance"))
    }

    private func makeFriend(_ id: String, order: Int) -> URL {
        let folder = root.appendingPathComponent("Friends/\(id)")
        SpriteCharacterTests.makePack(in: folder, json: """
        {"id":"\(id)","name":"\(id)","order":\(order),"frameWidth":16,"frameHeight":16,"facing":"front",
         "states":{"idle":{"file":"idle.png"},"walk":{"file":"walk.png","facing":"left"},"walk.2":{"file":"idle.png"},
                   "dragged":{"file":"walk.png"}}}
        """)
        return folder
    }

    func testVariantsFacingAndClimbFallback() throws {
        let sprite = try SpriteCharacter(folder: makeFriend("usagi", order: 1))
        XCTAssertEqual(sprite.variantCount(for: .walk), 2)
        XCTAssertEqual(sprite.animation(for: .walk, variant: 0)?.facing, "left")
        XCTAssertEqual(sprite.animation(for: .walk, variant: 1)?.facing, "front")
        XCTAssertEqual(sprite.animation(for: .walk, variant: 1)?.frames.count, 4)
        // 벽 오르기 그림이 없으면 잡힌 그림으로
        XCTAssertEqual(sprite.animation(for: .climb)?.frames.count, 6)
    }

    func testFriendsListedFirstAndSelectedByDefault() {
        _ = makeFriend("momonga", order: 4)
        _ = makeFriend("usagi", order: 1)
        let defaults = UserDefaults(suiteName: "FriendPackTests")!
        defaults.removePersistentDomain(forName: "FriendPackTests")
        defer { defaults.removePersistentDomain(forName: "FriendPackTests") }
        let lib = CharacterLibrary(friendsDirectory: root.appendingPathComponent("Friends"), defaults: defaults)
        // 친구들만 (기본 캐릭터·내 캐릭터는 목록에 없음)
        XCTAssertEqual(lib.entries.map(\.id), ["friend.usagi", "friend.momonga"])
        XCTAssertEqual(lib.selectedId, "friend.usagi")
        XCTAssertEqual(try lib.load(lib.selectedEntry).id, "friend.usagi")
    }
}

final class ClimbCeilingTests: XCTestCase {
    let screens = ScreenLayout(frames: [CGRect(x: 0, y: 0, width: 2000, height: 1200)])
    let pet = CGSize(width: 80, height: 80)

    /// 뒤 창(B) 왼쪽 벽을 오르는데, 그 벽 위쪽을 앞 창(A)이 덮고 있다 → A 아랫변에서 머리가 막힌다
    func testFrontWindowAboveBlocksClimb() {
        let front = WindowBox(id: 1, frame: CGRect(x: 400, y: 500, width: 600, height: 500))
        let back = WindowBox(id: 2, frame: CGRect(x: 500, y: 0, width: 800, height: 900))
        let t = Terrain(screens: screens, windows: [front, back], petSize: pet)
        let wall = Terrain.Wall(x: 500, top: 900, windowID: 2, side: .right)
        XCTAssertEqual(t.climbCeiling(for: wall, feetY: 0), 420)

        var p = PetPhysics(origin: CGPoint(x: 420, y: 0), size: pet)
        var result: PetPhysics.ClimbResult = .climbing
        for _ in 0..<200 where result == .climbing {
            let limit = t.climbCeiling(for: wall, feetY: p.origin.y) ?? .infinity
            result = p.climb(wall, speed: 60, dt: 0.1, terrain: t, limitY: limit)
        }
        XCTAssertEqual(result, .letGo)
        XCTAssertEqual(p.origin.y, 420, accuracy: 0.01)
    }

    func testNoCeilingWhenNothingInFront() {
        let back = WindowBox(id: 2, frame: CGRect(x: 500, y: 0, width: 800, height: 900))
        let behind = WindowBox(id: 3, frame: CGRect(x: 400, y: 500, width: 600, height: 500)) // 뒤에 있는 창은 무관
        let t = Terrain(screens: screens, windows: [back, behind], petSize: pet)
        XCTAssertNil(t.climbCeiling(for: Terrain.Wall(x: 500, top: 900, windowID: 2, side: .right), feetY: 0))
        XCTAssertNil(t.climbCeiling(for: Terrain.Wall(x: 0, top: 1200, windowID: nil, side: .left), feetY: 0))
    }

    func testCeilingLowerThanFeetLetsGoWithoutTeleport() {
        let front = WindowBox(id: 1, frame: CGRect(x: 400, y: 30, width: 600, height: 500))
        let back = WindowBox(id: 2, frame: CGRect(x: 500, y: 0, width: 800, height: 900))
        let t = Terrain(screens: screens, windows: [front, back], petSize: pet)
        let wall = Terrain.Wall(x: 500, top: 900, windowID: 2, side: .right)
        var p = PetPhysics(origin: CGPoint(x: 420, y: 10), size: pet)
        let r = p.climb(wall, speed: 60, dt: 0.1, terrain: t, limitY: t.climbCeiling(for: wall, feetY: 10) ?? .infinity)
        XCTAssertEqual(r, .letGo)
        XCTAssertEqual(p.origin.y, 10, accuracy: 0.01)
    }
}
