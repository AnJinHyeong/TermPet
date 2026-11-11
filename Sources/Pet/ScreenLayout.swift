import CoreGraphics

/// 모니터 배치 정보 (순수 데이터 → 테스트 가능).
///
/// 좌표계 주의: AppKit 화면 좌표는 **좌하단이 원점이고 y가 위로 증가**한다.
/// (웹/CSS는 좌상단 원점, y 아래로 증가 — 반대!)
/// `frames`에는 각 화면의 `NSScreen.visibleFrame`(메뉴바·Dock 제외 영역)이 들어간다.
/// 따라서 `frame.minY` = Dock 바로 위 = 펫이 서는 바닥.
struct ScreenLayout: Equatable {
    var frames: [CGRect]

    /// 인접 화면으로 판단할 경계 오차(pt)
    static let adjacencyTolerance: CGFloat = 2

    /// 펫 발 위치(x, y)를 포함하는 화면. y는 바닥 바로 아래 1pt까지 허용.
    func index(containingX x: CGFloat, y: CGFloat) -> Int? {
        frames.firstIndex { f in
            x >= f.minX && x < f.maxX && y >= f.minY - 1 && y < f.maxY
        }
    }

    /// x가 가로 범위에 들어가는 화면들 (세로 위치 무관)
    func indices(inColumnX x: CGFloat) -> [Int] {
        frames.indices.filter { frames[$0].minX <= x && x < frames[$0].maxX }
    }

    /// x에 가장 가까운 화면 (어느 화면에도 없을 때 복귀용)
    func nearestIndex(toX x: CGFloat) -> Int? {
        frames.indices.min { a, b in
            horizontalDistance(x, frames[a]) < horizontalDistance(x, frames[b])
        }
    }

    /// i번 화면의 `side` 쪽에 붙어 있는 화면.
    /// `y`를 주면 그 높이(펫의 발)가 이웃 화면 안에 있어야 한다 → 이웃 바닥이 더 높으면 벽 취급.
    /// `y`가 nil이면 세로 범위가 조금이라도 겹치면 이웃으로 본다.
    func neighbor(of i: Int, side: Direction, atY y: CGFloat? = nil) -> Int? {
        let f = frames[i]
        return frames.indices.first { j in
            guard j != i else { return false }
            let g = frames[j]
            let touching = side == .right
                ? abs(g.minX - f.maxX) < Self.adjacencyTolerance
                : abs(g.maxX - f.minX) < Self.adjacencyTolerance
            guard touching else { return false }
            if let y { return y >= g.minY - 1 && y < g.maxY }
            return g.minY < f.maxY && f.minY < g.maxY
        }
    }

    /// i번 화면 `side` 쪽에 붙은, 바닥이 `y`보다 높은 이웃 화면 = 기어올라 넘어갈 수 있는 "턱".
    /// 턱 꼭대기(이웃 바닥 높이)에 매달렸을 때 몸이 지금 화면 안에 다 보여야 하고(위가 메뉴바·화면 끝에 안 잘림),
    /// 이웃 화면에도 서 있을 공간이 있어야 한다. 여럿이면 가장 낮은 턱.
    func stepNeighbor(of i: Int, side: Direction, aboveY y: CGFloat, petHeight: CGFloat) -> Int? {
        let f = frames[i]
        return frames.indices.filter { j in
            guard j != i else { return false }
            let g = frames[j]
            let touching = side == .right
                ? abs(g.minX - f.maxX) < Self.adjacencyTolerance
                : abs(g.maxX - f.minX) < Self.adjacencyTolerance
            return touching && g.minY > y + 1 && g.minY + petHeight <= f.maxY && g.minY + petHeight <= g.maxY
        }.min { frames[$0].minY < frames[$1].minY }
    }

    /// x 위치에서 `fromY` 높이부터 떨어질 때 착지할 바닥 y.
    /// - 아래쪽에 바닥이 있으면 그중 가장 높은 것
    /// - 이미 바닥보다 아래(Dock 위에 놓은 경우 등)면 가장 가까운 위쪽 바닥으로 끌어올림
    func landingFloor(centerX x: CGFloat, fromY: CGFloat) -> CGFloat? {
        let column = indices(inColumnX: x).map { frames[$0].minY }
        if let below = column.filter({ $0 <= fromY + 1 }).max() { return below }
        if let above = column.min() { return above }
        return nearestIndex(toX: x).map { frames[$0].minY }
    }

    private func horizontalDistance(_ x: CGFloat, _ f: CGRect) -> CGFloat {
        if x < f.minX { return f.minX - x }
        if x >= f.maxX { return x - f.maxX }
        return 0
    }
}
