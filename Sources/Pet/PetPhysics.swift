import CoreGraphics
import Foundation

/// 펫 창의 위치 계산(걷기 / 낙하·던지기 / 벽 오르기 / 창 타고 다니기). AppKit 비의존 순수 로직.
/// `origin`은 펫 창의 좌하단 좌표(AppKit 화면 좌표, y 위로 증가) = 발 위치.
struct PetPhysics {
    var origin: CGPoint
    var size: CGSize
    /// 공중에 있을 때 속도 (pt/s). y는 위가 +
    var velocity: CGVector = .zero
    /// 중력 가속도 (pt/s²)
    var gravity: CGFloat = 1800
    /// 최대 낙하 속도 (pt/s). 높은 데서 떨어져도 캐릭터가 보이게 이 이상은 빨라지지 않는다 (낙하산처럼)
    var maxFallSpeed: CGFloat = 700
    /// 지금 서 있는 창 (nil = 화면 바닥이거나 공중)
    var standingOn: Int?

    var centerX: CGFloat { origin.x + size.width / 2 }

    /// 하위 호환: 예전 코드/테스트가 쓰던 세로 속도
    var velocityY: CGFloat {
        get { velocity.dy }
        set { velocity.dy = newValue }
    }

    enum WalkResult: Equatable {
        case moved
        case hitWall(Terrain.Wall)   // 창 옆면 또는 화면 끝 → 기어오르거나 돌아선다
        case reachedEdge             // 창 위에서 끝에 닿음 → 뛰어내리거나 돌아선다
        case startFalling            // 발밑에 바닥이 없음
        /// 화면 바닥에서 같은 높이이거나 더 낮은 옆 모니터와의 경계에 닿음 → 폴짝 건너뛰거나 돌아선다.
        /// (걸어서 천천히 넘으면 몸이 두 모니터에 걸친 동안 macOS가 한쪽에만 그려서 반쯤 잘려 보인다)
        case reachedScreenEdge
    }

    // MARK: - 걷기

    mutating func walk(direction: Direction, speed: CGFloat, dt: TimeInterval, terrain: Terrain) -> WalkResult {
        let dx = direction.sign * speed * CGFloat(dt)
        let newX = origin.x + dx

        // 1) 창 옆면에 부딪힘
        if let wall = terrain.windowWall(fromX: origin.x, toX: newX, feetY: origin.y, direction: direction,
                                         onScreenFloor: standingOn == nil) {
            origin.x = direction == .right ? wall.x - size.width : wall.x
            // 발목 높이 정도의 낮은 턱은 그냥 올라선다
            if wall.top - origin.y < size.height * 0.22, let ledge = terrain.ledgeAfterClimbing(wall) {
                origin.y = ledge.y
                origin.x = wall.x + direction.sign * 1 - (direction == .right ? 0 : size.width)
                standingOn = ledge.windowID
                return .moved
            }
            return .hitWall(wall)
        }

        // 2) 창 위에서 걷는 중: 선반 끝이면 멈춘다
        if let id = standingOn {
            guard terrain.ledge(atX: centerX, y: origin.y, windowID: id) != nil else {
                standingOn = nil
                return .startFalling // 서 있던 곳이 사라짐 (창이 가려짐 등)
            }
            let newCenter = newX + size.width / 2
            if terrain.ledge(atX: newCenter, y: origin.y, windowID: id) == nil {
                return .reachedEdge
            }
            origin.x = newX
            return .moved
        }

        // 3) 화면 바닥: 모니터 사이 이동 / 화면 끝 벽
        return walkOnScreenFloor(direction: direction, newX: newX, layout: terrain.screens)
    }

    /// 모니터 경계를 폴짝 건너뛰는 초속. 몸 전체가 경계를 넘은 뒤에 원래 높이로 내려오도록
    /// (공중 약 0.39초 동안 몸 폭의 1.1배 이상 이동) 크기에 맞춰 키운다.
    func screenHop(_ direction: Direction) -> CGVector {
        CGVector(dx: direction.sign * max(200, size.width * 3.3), dy: 350)
    }

    /// 하위 호환: 창 없이 화면만 있는 지형
    mutating func walk(direction: Direction, speed: CGFloat, dt: TimeInterval, layout: ScreenLayout) -> WalkResult {
        walk(direction: direction, speed: speed, dt: dt, terrain: Terrain(screens: layout, petSize: size))
    }

    private mutating func walkOnScreenFloor(direction: Direction, newX: CGFloat, layout: ScreenLayout) -> WalkResult {
        guard let current = layout.index(containingX: centerX, y: origin.y) else {
            return .startFalling
        }
        let f = layout.frames[current]
        let exceedsRight = direction == .right && newX + size.width > f.maxX
        let exceedsLeft = direction == .left && newX < f.minX
        if exceedsRight || exceedsLeft {
            let edgeX = exceedsRight ? f.maxX : f.minX
            let stopX = exceedsRight ? f.maxX - size.width : f.minX
            // 이미 몸이 경계를 넘어가 있으면(예전 상태 등) 되돌리지 않고 그대로 걸어 넘어간다
            let alreadyOver = exceedsRight ? origin.x > stopX + 0.5 : origin.x < stopX - 0.5
            if layout.neighbor(of: current, side: direction, atY: origin.y) != nil {
                // 같은 높이이거나 더 낮은 옆 모니터: 경계에 멈춰 서서 건너뛸지 정한다
                if !alreadyOver {
                    origin.x = stopX
                    return .reachedScreenEdge
                }
            } else {
                origin.x = stopX
                // 옆 모니터 바닥이 더 높으면 그 높이까지만 벽(턱) → 기어올라 넘어간다
                if let j = layout.stepNeighbor(of: current, side: direction, aboveY: origin.y, petHeight: size.height) {
                    return .hitWall(Terrain.Wall(x: edgeX, top: layout.frames[j].minY, windowID: nil,
                                                 side: direction, leadsToScreen: true))
                }
                return .hitWall(Terrain.Wall(x: edgeX, top: f.maxY, windowID: nil, side: direction))
            }
        }
        origin.x = newX
        // 이동 후 발밑 확인 (이웃 화면 바닥이 더 낮으면 떨어진다)
        guard let now = layout.index(containingX: centerX, y: origin.y) else {
            return .startFalling
        }
        return origin.y > layout.frames[now].minY + 0.5 ? .startFalling : .moved
    }

    // MARK: - 낙하 / 던지기 / 점프

    /// 낙하 시작. `velocity`로 던지기·점프 초속을 줄 수 있다.
    mutating func prepareFall(terrain: Terrain, velocity v: CGVector = .zero) {
        velocity = v
        standingOn = nil
        clampHorizontally(layout: terrain.screens)
    }

    mutating func prepareFall(layout: ScreenLayout) {
        prepareFall(terrain: Terrain(screens: layout, petSize: size))
    }

    /// 한 프레임 낙하. 착지하면 true (standingOn 갱신).
    mutating func fall(dt: TimeInterval, terrain: Terrain) -> Bool {
        let t = CGFloat(dt)
        velocity.dy = max(velocity.dy - gravity * t, -maxFallSpeed)
        // 공기 저항 살짝 (던진 뒤 끝없이 날아가지 않게)
        velocity.dx *= pow(0.6, t)
        let nextY = origin.y + velocity.dy * t
        origin.x += velocity.dx * t
        if bounceOffScreenEdges(layout: terrain.screens) { velocity.dx = -velocity.dx * 0.45 }

        if velocity.dy <= 0, let floor = terrain.landing(centerX: centerX, fromY: origin.y, toY: nextY) {
            origin.y = floor.y
            velocity = .zero
            standingOn = floor.windowID
            clampHorizontally(layout: terrain.screens)
            if standingOn == nil { stepOutOfDock(terrain: terrain) }
            return true
        }
        if terrain.screens.frames.isEmpty { return true } // 화면이 하나도 없는 비정상 상황: 그냥 멈춤
        origin.y = nextY
        // 위로 던졌을 때 화면 위로 사라지지 않게 천장에서 튕김
        if let top = terrain.ceiling(atX: centerX), origin.y + size.height > top, velocity.dy > 0 {
            origin.y = top - size.height
            velocity.dy = -velocity.dy * 0.3
        }
        return false
    }

    mutating func fall(dt: TimeInterval, layout: ScreenLayout) -> Bool {
        fall(dt: dt, terrain: Terrain(screens: layout, petSize: size))
    }

    // MARK: - 벽 오르기

    enum ClimbResult: Equatable {
        case climbing
        /// 창 꼭대기에 올라섰다 (그 창 위를 걸으면 된다)
        case reachedTop(windowID: Int)
        /// 목표 높이까지 올랐지만 올라설 곳이 없음 → 벽을 차고 뛰어내린다
        case letGo
        /// 옆 모니터 턱 꼭대기에 닿음 → 옆 모니터로 폴짝 넘어간다 (`screenHop`)
        case overStep
    }

    /// `limitY`: 이 높이(발 기준)까지 오르면 손을 놓는다 (화면 벽처럼 꼭대기가 없을 때)
    mutating func climb(_ wall: Terrain.Wall, speed: CGFloat, dt: TimeInterval, terrain: Terrain,
                        limitY: CGFloat) -> ClimbResult {
        standingOn = nil
        // 벽에 몸을 붙인다
        origin.x = wall.side == .right ? wall.x - size.width : wall.x
        origin.y += speed * CGFloat(dt)

        let goal = min(limitY, wall.top)
        guard origin.y >= goal else { return .climbing }
        if wall.leadsToScreen, origin.y >= wall.top - 0.5 {
            origin.y = wall.top
            return .overStep
        }
        if origin.y >= wall.top - 0.5, let ledge = terrain.ledgeAfterClimbing(wall) {
            origin.y = ledge.y
            // 몸이 창 윗면 안쪽으로 완전히 올라가게
            origin.x = wall.side == .right ? max(wall.x + 1, ledge.minX) : min(wall.x - size.width - 1, ledge.maxX - size.width)
            standingOn = ledge.windowID
            return .reachedTop(windowID: ledge.windowID)
        }
        // 이번 프레임에 오른 만큼만 되돌린다 (막힌 높이가 발보다 낮아도 순간이동하지 않게)
        origin.y = max(goal, origin.y - speed * CGFloat(dt))
        return .letGo
    }

    // MARK: - 창 따라가기

    /// 서 있던(또는 매달린) 창이 움직였으면 같이 움직인다 (창 윗변 좌상단 기준 이동량만큼)
    mutating func ride(from old: CGRect, to new: CGRect) {
        origin.x += new.minX - old.minX
        origin.y += new.maxY - old.maxY
    }

    // MARK: - 화면 안으로 보정

    /// 바닥에 내려섰는데 몸이 Dock 자리(Dock 뒤)에 걸쳐 있으면 Dock 위나 옆으로 (Dock 뒤에 숨지 않게)
    mutating func stepOutOfDock(terrain: Terrain) {
        for box in terrain.windows where ScreenFloor.isDock(box.id) {
            guard let fix = ScreenFloor.resolveDockOverlap(origin: origin, size: size, dock: box.frame) else { continue }
            origin = fix.origin
            if fix.onDock { standingOn = box.id }
            return
        }
    }

    /// 펫 몸이 이웃 화면이 없는 쪽 가장자리 밖으로 삐져나가지 않게 x 보정.
    mutating func clampHorizontally(layout: ScreenLayout) {
        _ = bounceOffScreenEdges(layout: layout)
    }

    /// 보정했으면 true (던져서 화면 끝에 부딪힘)
    /// 옆 모니터가 있어도 **지금 발 높이에** 그 모니터가 없으면 벽이다 (높이가 다른 모니터 사이의 빈 공간으로
    /// 몸이 들어가 반쯤 안 보이게 착지하거나, 옆 모니터 바닥으로 순간이동하지 않게).
    private mutating func bounceOffScreenEdges(layout: ScreenLayout) -> Bool {
        guard let i = layout.index(containingX: centerX, y: origin.y)
                ?? layout.indices(inColumnX: centerX).first
                ?? layout.nearestIndex(toX: centerX) else { return false }
        let f = layout.frames[i]
        if origin.x + size.width > f.maxX, layout.neighbor(of: i, side: .right, atY: origin.y) == nil {
            origin.x = f.maxX - size.width
            return true
        }
        if origin.x < f.minX, layout.neighbor(of: i, side: .left, atY: origin.y) == nil {
            origin.x = f.minX
            return true
        }
        return false
    }
}
