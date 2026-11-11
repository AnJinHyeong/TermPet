import CoreGraphics

/// 화면에 떠 있는 앱 창 하나 (AppKit 좌표: 좌하단 원점, y 위로 증가)
struct WindowBox: Equatable {
    var id: Int
    var frame: CGRect
    /// 창 주인 앱의 프로세스 id (0 = 모름). 한 앱이 여러 장으로 나눠 그린 전체 화면을 합쳐 보기 위해
    var owner: Int32 = 0
}

/// 펫이 다니는 "지형" = 화면 바닥 + 앱 창 윗면(선반) + 창 옆면(벽). AppKit 비의존 순수 로직.
///
/// React 비유: 화면 상태(창 목록)에서 파생된 `useMemo` 값. 창 목록이 바뀌면 새로 만든다.
/// - 선반(Ledge): 창 윗변 중 **앞 창에 가리지 않고** 위에 펫이 설 공간(메뉴바 아래)이 있는 구간
/// - 벽(Wall): 걷다가 부딪히는 창 옆변. 기어 올라가면 그 창 윗면에 올라선다.
struct Terrain {
    struct Ledge: Equatable {
        var minX: CGFloat
        var maxX: CGFloat
        var y: CGFloat
        var windowID: Int

        func contains(x: CGFloat) -> Bool { x >= minX && x <= maxX }
    }

    struct Wall: Equatable {
        /// 벽면 x (펫 몸이 닿는 선)
        var x: CGFloat
        /// 벽 꼭대기 y (창 윗면). 화면 끝 벽이면 화면 위쪽 끝
        var top: CGFloat
        /// 창 벽이면 창 id, 화면 끝이면 nil
        var windowID: Int?
        /// 벽이 펫의 어느 쪽에 있는지 (= 부딪힐 때 걷던 방향)
        var side: Direction
        /// 옆 모니터로 이어지는 "턱"(옆 모니터 바닥이 더 높음). 꼭대기(`top`)까지 오르면 옆 모니터로 폴짝 넘어간다
        var leadsToScreen = false
    }

    /// 착지 지점: 화면 바닥이면 windowID nil
    struct Floor: Equatable {
        var y: CGFloat
        var windowID: Int?
    }

    var screens: ScreenLayout
    /// 앞(위에 그려진 창) → 뒤 순서
    private(set) var windows: [WindowBox]
    private(set) var ledges: [Ledge] = []
    let petSize: CGSize

    /// 이보다 좁은 선반 구간은 버린다 (펫 몸 폭 비율)
    static let minLedgeRatio: CGFloat = 0.6

    init(screens: ScreenLayout, windows: [WindowBox] = [], petSize: CGSize = CGSize(width: 80, height: 80)) {
        self.screens = screens
        self.windows = windows
        self.petSize = petSize
        self.ledges = windows.indices.flatMap { computeLedges(of: $0) }
    }

    func window(id: Int) -> WindowBox? { windows.first { $0.id == id } }

    // MARK: - 선반

    private func computeLedges(of i: Int) -> [Ledge] {
        let f = windows[i].frame
        let y = f.maxY
        // 1) 윗변이 들어가는 화면에서, 머리 위 공간(펫 키의 80%)이 남는 부분만
        var spans: [ClosedRange<CGFloat>] = screens.frames.compactMap { s in
            guard y >= s.minY, y + petSize.height * 0.8 <= s.maxY else { return nil }
            let lo = max(f.minX, s.minX), hi = min(f.maxX, s.maxX)
            return lo < hi ? lo...hi : nil
        }
        // 2) 앞 창이 윗변 선을 덮는 부분은 뺀다 (가려진 곳엔 못 선다)
        for j in 0..<i {
            let g = windows[j].frame
            guard g.minY <= y + 1, g.maxY > y + 1 else { continue }
            spans = spans.flatMap { subtract($0, g.minX...g.maxX) }
        }
        let minWidth = petSize.width * Self.minLedgeRatio
        return spans.filter { $0.upperBound - $0.lowerBound >= minWidth }
            .map { Ledge(minX: $0.lowerBound, maxX: $0.upperBound, y: y, windowID: windows[i].id) }
    }

    private func subtract(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        guard b.lowerBound < a.upperBound, b.upperBound > a.lowerBound else { return [a] }
        var out: [ClosedRange<CGFloat>] = []
        if b.lowerBound > a.lowerBound { out.append(a.lowerBound...b.lowerBound) }
        if b.upperBound < a.upperBound { out.append(b.upperBound...a.upperBound) }
        return out
    }

    /// 펫 발(가로 중심 x, 높이 y)이 올라서 있는 창 선반
    func ledge(atX x: CGFloat, y: CGFloat, windowID: Int? = nil) -> Ledge? {
        ledges.first { abs($0.y - y) < 1.5 && $0.contains(x: x) && (windowID == nil || $0.windowID == windowID) }
    }

    // MARK: - 착지

    /// `fromY`에서 `toY`까지 떨어지는 동안 처음 닿는 바닥 (선반 또는 화면 바닥).
    /// 닿는 게 없으면 nil (계속 떨어짐).
    func landing(centerX x: CGFloat, fromY: CGFloat, toY: CGFloat) -> Floor? {
        var best: Floor?
        for l in ledges where l.contains(x: x) && l.y <= fromY + 0.5 && l.y >= toY {
            if best == nil || l.y > best!.y { best = Floor(y: l.y, windowID: l.windowID) }
        }
        if let floorY = screens.landingFloor(centerX: x, fromY: fromY), floorY >= toY || floorY > fromY {
            if best == nil || floorY > best!.y { best = Floor(y: floorY, windowID: nil) }
        }
        return best
    }

    // MARK: - 벽

    /// 몸 왼쪽 x가 `oldX` → `newX`로 움직일 때 부딪히는 첫 창 옆면.
    /// 발 높이에서 펫 키의 60% 안쪽으로 시작해 발보다 4pt 이상 솟은 창만 벽이다
    /// (창 아래를 지나가거나, 이미 창 앞에 겹쳐 있으면 벽 아님).
    /// `onScreenFloor`: 화면 바닥을 걷는 중이면 지금 모니터 끝(경계)이나 그 너머의 창 옆면은 벽이 아니다
    /// → 옆 모니터 왼쪽 끝에 붙은 창 때문에 경계를 못 넘고 그 벽만 타던 문제. 경계는 화면 끝 처리가 맡는다.
    func windowWall(fromX oldX: CGFloat, toX newX: CGFloat, feetY: CGFloat, direction: Direction,
                    onScreenFloor: Bool = false) -> Wall? {
        let w = petSize.width
        var hit: Wall?
        let screen = onScreenFloor ? screens.index(containingX: oldX + w / 2, y: feetY).map { screens.frames[$0] } : nil
        for (i, box) in windows.enumerated() {
            let f = box.frame
            guard f.minY < feetY + petSize.height * 0.6, f.maxY > feetY + 4 else { continue }
            let sideX: CGFloat
            switch direction {
            case .right:
                sideX = f.minX
                guard oldX + w <= sideX + 0.5, newX + w > sideX else { continue }
            case .left:
                sideX = f.maxX
                guard oldX >= sideX - 0.5, newX < sideX else { continue }
            }
            if let screen, direction == .right ? sideX >= screen.maxX - 0.5 : sideX <= screen.minX + 0.5 { continue }
            // 벽 중간이 앞 창에 가려 있으면 안 보이는 벽 → 무시
            let probe = CGPoint(x: sideX, y: min(f.maxY, feetY + petSize.height / 2))
            if isCovered(probe, frontOf: i) { continue }
            let wall = Wall(x: sideX, top: f.maxY, windowID: box.id, side: direction)
            if let h = hit {
                let closer = direction == .right ? sideX < h.x : sideX > h.x
                if closer { hit = wall }
            } else {
                hit = wall
            }
        }
        return hit
    }

    /// i번 창보다 앞에 있는 창이 점을 덮는지
    func isCovered(_ p: CGPoint, frontOf i: Int) -> Bool {
        windows[..<i].contains { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }
    }

    /// 창 벽을 다 오른 뒤 올라설 선반 (벽 바로 안쪽에 몸 절반 이상 걸칠 수 있어야)
    func ledgeAfterClimbing(_ wall: Wall) -> Ledge? {
        guard let id = wall.windowID else { return nil }
        let x = wall.x + wall.side.sign * (petSize.width * 0.5 + 1)
        return ledges.first { $0.windowID == id && abs($0.y - wall.top) < 1.5 && $0.contains(x: x) }
    }

    /// 창 벽을 오를 때 머리가 막히는 높이(발 기준).
    /// 벽 선 위쪽을 **앞 창**이 덮고 있으면 거기서 벽이 끊긴 것 → 그 창 아랫변에 머리가 닿으면 더 못 오른다.
    /// 막는 창이 없으면 nil.
    func climbCeiling(for wall: Wall, feetY: CGFloat) -> CGFloat? {
        guard let id = wall.windowID, let i = windows.firstIndex(where: { $0.id == id }) else { return nil }
        return windows[..<i].compactMap { g -> CGFloat? in
            let f = g.frame
            guard f.minX - 1 <= wall.x, wall.x <= f.maxX + 1,   // 벽 선을 가로로 덮고
                  f.maxY > feetY + 1, f.minY < wall.top,        // 발 위 ~ 벽 꼭대기 사이에 걸쳐 있음
                  f.minY >= feetY - 1 else { return nil }
            return f.minY - petSize.height
        }.min()
    }

    /// 화면 바닥에 서 있을 때 가장 가까운 기어오를 벽 쪽: 창 옆면, 또는 옆 화면으로 안 이어지는 화면 끝.
    /// `targetX`를 주면 그 x(포인터)에 가장 가까운 벽 (장난꾸러기 모드: 포인터가 너무 높으면 거기로 달려가 타고 오른다).
    /// 벽이 없으면 nil.
    func nearestWallDirection(originX x: CGFloat, feetY y: CGFloat, targetX: CGFloat? = nil) -> Direction? {
        guard let i = screens.index(containingX: x + petSize.width / 2, y: y) else { return nil }
        let f = screens.frames[i]
        var best: (dir: Direction, distance: CGFloat)?
        for dir in [Direction.left, .right] {
            let edgeX = dir == .left ? f.minX : f.maxX - petSize.width
            // 벽면 x (벽에 붙었을 때 몸 가운데)
            var wallX: CGFloat? = screens.neighbor(of: i, side: dir, atY: y) == nil ? edgeX + petSize.width / 2 : nil
            if let wall = windowWall(fromX: x, toX: edgeX, feetY: y, direction: dir, onScreenFloor: true) {
                wallX = wall.x - dir.sign * petSize.width / 2
            }
            let distance = wallX.map { abs($0 - (targetX ?? x + petSize.width / 2)) }
            if let distance, distance < (best?.distance ?? .infinity) { best = (dir, distance) }
        }
        return best?.dir
    }

    /// 화면 위쪽 끝 (기어오를 수 있는 최대 높이 계산용)
    func ceiling(atX x: CGFloat) -> CGFloat? {
        screens.indices(inColumnX: x).map { screens.frames[$0].maxY }.max()
    }
}
