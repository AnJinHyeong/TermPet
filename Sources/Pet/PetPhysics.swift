import CoreGraphics
import Foundation

/// 펫 창의 위치 계산(걷기 / 중력 낙하). AppKit 비의존 순수 로직.
/// `origin`은 펫 창의 좌하단 좌표(AppKit 화면 좌표, y 위로 증가).
struct PetPhysics {
    var origin: CGPoint
    var size: CGSize
    var velocityY: CGFloat = 0
    /// 중력 가속도 (pt/s²)
    var gravity: CGFloat = 2600

    var centerX: CGFloat { origin.x + size.width / 2 }

    enum WalkResult: Equatable {
        case moved
        case hitWall        // 화면 끝(이웃 화면 없음) → 방향 전환 필요
        case startFalling   // 발밑에 바닥이 없음 (더 낮은 이웃 화면으로 넘어감 등)
    }

    mutating func walk(direction: Direction, speed: CGFloat, dt: TimeInterval,
                       layout: ScreenLayout) -> WalkResult {
        guard let current = layout.index(containingX: centerX, y: origin.y) else {
            return .startFalling
        }
        let f = layout.frames[current]
        let newX = origin.x + direction.sign * speed * CGFloat(dt)

        // 화면 끝을 넘으려 할 때: 같은 높이로 이어지는 이웃 화면이 없으면 벽
        let exceedsRight = direction == .right && newX + size.width > f.maxX
        let exceedsLeft = direction == .left && newX < f.minX
        if exceedsRight || exceedsLeft,
           layout.neighbor(of: current, side: direction, atY: origin.y) == nil {
            origin.x = exceedsRight ? f.maxX - size.width : f.minX
            return .hitWall
        }

        origin.x = newX

        // 이동 후 발밑 확인 (이웃 화면 바닥이 더 낮으면 떨어진다)
        guard let now = layout.index(containingX: centerX, y: origin.y) else {
            return .startFalling
        }
        return origin.y > layout.frames[now].minY + 0.5 ? .startFalling : .moved
    }

    /// 낙하 시작 전 호출: 화면 밖에 있으면 가장 가까운 화면 안으로 x를 맞추고 속도 초기화.
    mutating func prepareFall(layout: ScreenLayout) {
        velocityY = 0
        clampHorizontally(layout: layout)
    }

    /// 한 프레임 낙하. 착지하면 true.
    mutating func fall(dt: TimeInterval, layout: ScreenLayout) -> Bool {
        guard let floor = layout.landingFloor(centerX: centerX, fromY: origin.y) else {
            return true // 화면이 하나도 없는 비정상 상황: 그냥 멈춤
        }
        velocityY -= gravity * CGFloat(dt)
        let nextY = origin.y + velocityY * CGFloat(dt)
        if nextY <= floor {
            origin.y = floor
            velocityY = 0
            clampHorizontally(layout: layout)
            return true
        }
        origin.y = nextY
        return false
    }

    /// 펫 몸이 이웃 화면이 없는 쪽 가장자리 밖으로 삐져나가지 않게 x 보정.
    mutating func clampHorizontally(layout: ScreenLayout) {
        let column = layout.indices(inColumnX: centerX)
        guard let i = column.first ?? layout.nearestIndex(toX: centerX) else { return }
        let f = layout.frames[i]
        if origin.x + size.width > f.maxX, layout.neighbor(of: i, side: .right) == nil {
            origin.x = f.maxX - size.width
        }
        if origin.x < f.minX, layout.neighbor(of: i, side: .left) == nil {
            origin.x = f.minX
        }
    }
}
