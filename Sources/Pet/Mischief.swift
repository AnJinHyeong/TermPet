import CoreGraphics
import Foundation

/// 장난꾸러기 모드: 켜져 있는 동안 마우스 포인터를 계속 쫓아다니다가 → 잡으면 물고 흔들다가 → 휙 던진다.
/// AppKit 비의존 순수 상태 머신 (PetBrain처럼 reducer). 실제 포인터 이동·펫 걷기는 컨트롤러가 명령(Command)을 받아 한다.
/// React 비유: `useReducer` — 매 프레임 `tick(입력)`을 dispatch하면 할 일(명령)을 돌려준다.
struct Mischief {
    struct Config {
        /// 모드를 켠 뒤 쫓기 시작할 때까지
        var startDelay: TimeInterval = 1
        /// 물고 흔드는 시간
        var biteDuration: TimeInterval = 1.3
        /// 던진 뒤 숨 고르는 시간 (그다음 다시 쫓아온다)
        var cooldownAfterThrow: TimeInterval = 4
        /// 벽에 막혀 돌아섰거나 클릭으로 놓아줬을 때 잠깐 쉬는 시간
        var cooldownAfterGiveUp: TimeInterval = 2.5
    }

    enum Phase: Equatable {
        case ready      // 잠깐 쉬는 중 (쉬는 시간이 끝나면 바로 쫓기 시작)
        case chasing    // 포인터를 쫓는 중 (멀어도, 멈춰 있어도 계속)
        case biting
        case throwing   // 포인터가 날아가는 중 (끝나면 컨트롤러가 finishThrow)
    }

    /// 한 프레임 입력 (AppKit 좌표: 좌하단 원점, y 위로)
    struct Input {
        var petFrame: CGRect
        var cursor: CGPoint
        var facing: Direction
        /// 놀 수 있는 상태 (모드 켜짐, 보임, 안 잠, 안 잡힘, 말풍선 없음)
        var canPlay: Bool
        /// 마우스 버튼을 누르고 있음 (드래그·선택 중이면 절대 안 문다 / 물고 있을 때 누르면 놓아준다)
        var mouseDown: Bool
        /// 바닥·창 위에 서 있음 (떨어지거나 벽 타는 중이 아님) → 걷기·점프 명령 가능
        var grounded: Bool
        /// 벽을 타는 중이면 벽이 있는 쪽 (벽에서 포인터 쪽으로 몸을 날린다)
        var climbingSide: Direction? = nil
        /// 포인터에 가장 가까운 기어오를 벽 쪽 (포인터가 너무 높을 때 거기로 달려가 타고 오른다). 없으면 nil
        var wallDirection: Direction? = nil
        /// 몸 위쪽 여유 (화면 천장까지, pt). 높은 데서 몸을 날릴 때 천장에 머리를 박지 않게 낮게 날아간다
        var headroom: CGFloat = .infinity
    }

    enum Command: Equatable {
        case none
        case chase(Direction)         // 그쪽으로 달린다
        case jump(CGVector)           // 포인터를 향해 점프 (바닥에서 / 벽에서 몸을 날려) — 초속
        case stopChase
        case startBite
        case holdPointer(CGPoint)     // 포인터를 입 위치(+흔들기)로
        case throwPointer             // 던지기 시작 (경로는 PointerThrow)
        case release                  // 놓아줌 (던지지 않고)
    }

    let config: Config
    private(set) var phase: Phase = .ready
    /// 지금 단계에 들어온 뒤 지난 시간
    private(set) var phaseTime: TimeInterval = 0
    private var cooldown: TimeInterval
    /// 던지기까지 남은 시간 (물고 있는 동안)
    private var biteLeft: TimeInterval = 0
    /// 바닥에 내려선 뒤 지난 시간 (점프 사이에 잠깐 웅크리는 박자)
    private var groundedTime: TimeInterval = 0
    /// 포인터가 너무 높아서 벽을 찾아 달려가는 방향 (벽에 붙으면 끝)
    private(set) var seekDirection: Direction?

    /// 바닥에서 한 번에 뛰어오를 수 있는 높이(pt)
    static let maxRise: CGFloat = 320
    /// 몸을 날려 닿을 수 있는 거리(pt, 몸 중심 → 포인터)
    static let leapRange: CGFloat = 380
    /// 벽에 매달려 포인터 높이까지 올라왔을 때 벽을 차고 날아갈 수 있는 거리 (발판이 있어 훨씬 멀리)
    static let wallLeapRange: CGFloat = 1000

    init(config: Config = Config()) {
        self.config = config
        cooldown = config.startDelay
    }

    mutating func tick(_ dt: TimeInterval, _ input: Input) -> Command {
        phaseTime += dt
        groundedTime = input.grounded ? groundedTime + dt : 0
        if !input.canPlay {
            switch phase {
            case .chasing: rest(config.cooldownAfterGiveUp); return .stopChase
            case .biting: rest(config.cooldownAfterGiveUp); return .release
            case .ready, .throwing: return .none
            }
        }

        switch phase {
        case .ready:
            cooldown -= dt
            guard cooldown <= 0, input.grounded, !input.mouseDown else { return .none }
            enter(.chasing)
            return chase(input)

        case .chasing:
            if !input.mouseDown, Self.catches(petFrame: input.petFrame, cursor: input.cursor) {
                enter(.biting)
                biteLeft = config.biteDuration
                return .startBite
            }
            return chase(input)

        case .biting:
            if input.mouseDown { // 클릭하면 놓아준다
                rest(config.cooldownAfterGiveUp)
                return .release
            }
            biteLeft -= dt
            // 공중에서 물었으면 문 채로 땅에 떨어진 뒤에 던진다 (너무 오래 걸리면 그냥 던짐)
            if biteLeft <= 0, input.grounded || phaseTime > 5 {
                enter(.throwing)
                return .throwPointer
            }
            return .holdPointer(Self.mouthPoint(petFrame: input.petFrame, facing: input.facing, time: phaseTime))

        case .throwing:
            return .none
        }
    }

    /// 쫓는 중: 걷기 / 점프 / 벽 찾아 달리기 / 벽에서 몸 날리기
    private mutating func chase(_ input: Input) -> Command {
        let frame = input.petFrame, cursor = input.cursor
        let leap = Self.leapVelocity(petFrame: frame, cursor: cursor, headroom: input.headroom)

        // 벽 타는 중: 포인터가 벽 반대쪽(트인 쪽)에 있고 닿을 거리면 벽을 차고 몸을 날린다.
        // 멀리 있으면 포인터 높이까지 올라온 뒤에 (컨트롤러가 오르는 높이를 포인터에 맞춘다) 멀리 날아간다
        if let side = input.climbingSide {
            let behindWall = (cursor.x - frame.midX) * side.sign > frame.width * 0.5
            guard !behindWall else { return .none }
            if let leap { return .jump(leap) }
            if cursor.y - frame.midY <= 40, let far = Self.wallLeap(petFrame: frame, cursor: cursor, headroom: input.headroom) {
                return .jump(far)
            }
            return .none
        }
        guard input.grounded else { return .none } // 공중에선 잡히는지만 본다

        let above = cursor.y > frame.maxY - 4
        guard above else {
            seekDirection = nil
            return Self.chaseDirection(petFrame: frame, cursorX: cursor.x).map(Command.chase) ?? .none
        }
        // 머리 위 닿는 거리 → 웅크렸다 점프해서 낚아채기
        if let leap {
            seekDirection = nil
            return groundedTime >= 0.25 ? .jump(leap) : .none
        }
        // 너무 높다 → 포인터에 가장 가까운 벽으로 달려가 타고 오른다 (방향은 벽에 닿을 때까지 유지)
        let dx = cursor.x - frame.midX
        if seekDirection == nil { seekDirection = input.wallDirection }
        if let dir = seekDirection { return .chase(dir) }
        // 탈 벽이 없고(창 위 등) 아직 멀면 일단 그쪽으로
        if abs(dx) > Self.leapRange * 0.7 {
            return Self.chaseDirection(petFrame: frame, cursorX: cursor.x).map(Command.chase) ?? .none
        }
        // 탈 벽도 없으면 제자리에서 힘껏 뛰어 본다 (안 닿아도 귀엽게)
        return groundedTime >= 0.9 ? .jump(CGVector(dx: max(-120, min(120, dx * 2)), dy: sqrt(2 * 1800 * Self.maxRise))) : .none
    }

    /// 벽을 타기 시작했다 (벽 찾기 끝)
    mutating func didStartClimbing() {
        seekDirection = nil
    }

    /// 포인터가 다 날아갔다
    mutating func finishThrow() {
        guard phase == .throwing else { return }
        rest(config.cooldownAfterThrow)
    }

    /// 쫓다가 벽에 막히는 등 컨트롤러 사정으로 포기
    mutating func giveUp() {
        guard phase == .chasing else { return }
        rest(config.cooldownAfterGiveUp)
    }

    /// 모드를 끄면 바로 원래대로 (쉬는 시간 포함)
    mutating func reset() {
        phase = .ready
        phaseTime = 0
        cooldown = config.startDelay
    }

    private mutating func enter(_ p: Phase) {
        phase = p
        phaseTime = 0
    }

    private mutating func rest(_ seconds: TimeInterval) {
        enter(.ready)
        cooldown = seconds
        seekDirection = nil
    }

    // MARK: - 계산 (테스트용 static)

    /// 포인터가 몸에 닿으면 잡힌다 (테두리 6pt 여유)
    static func catches(petFrame: CGRect, cursor: CGPoint) -> Bool {
        petFrame.insetBy(dx: -6, dy: -6).contains(cursor)
    }

    /// 포인터 쪽 방향. 거의 바로 위·아래면 nil (제자리)
    static func chaseDirection(petFrame: CGRect, cursorX: CGFloat) -> Direction? {
        let dx = cursorX - petFrame.midX
        guard abs(dx) > petFrame.width * 0.2 else { return nil }
        return dx > 0 ? .right : .left
    }

    /// 몸 중심이 포인터를 지나가도록 던지는 포물선 초속 (중력 1800 기준). 너무 멀거나 높으면 nil.
    /// 날아가는 시간 T를 거리에 맞춰 정하고 x = vx·T, y = vy·T − g·T²/2 를 풀었다.
    static func leapVelocity(petFrame: CGRect, cursor: CGPoint, headroom: CGFloat = .infinity,
                             gravity: CGFloat = 1800) -> CGVector? {
        let dx = cursor.x - petFrame.midX, dy = cursor.y - petFrame.midY
        let distance = hypot(dx, dy)
        guard distance <= leapRange, dy <= maxRise, dy > -petFrame.height else { return nil }
        return parabola(dx: dx, dy: dy, time: min(0.5, max(0.22, distance / 750)), headroom: headroom, gravity: gravity)
    }

    /// 벽에서 포인터 높이쯤까지 올라와 멀리 날아가기 (바닥 점프보다 멀리, 빠르고 낮게). 너무 멀면 nil.
    static func wallLeap(petFrame: CGRect, cursor: CGPoint, headroom: CGFloat = .infinity,
                         gravity: CGFloat = 1800) -> CGVector? {
        let dx = cursor.x - petFrame.midX, dy = cursor.y - petFrame.midY
        guard abs(dx) <= wallLeapRange, dy <= maxRise, dy > -wallLeapRange else { return nil }
        return parabola(dx: dx, dy: dy, time: min(0.6, max(0.22, hypot(dx, dy) / 1400)), headroom: headroom, gravity: gravity)
    }

    /// 시간 T 동안 (dx, dy)만큼 가는 초속. 꼭대기가 `headroom`보다 높아지면 T를 줄여 더 낮고 빠르게.
    /// 가로는 물리의 공기 저항(초당 0.6배)만큼 덜 가니 그만큼 키운다: x(T) = vx·(1 − 0.6^T) / ln(1/0.6)
    private static func parabola(dx: CGFloat, dy: CGFloat, time: CGFloat, headroom: CGFloat, gravity: CGFloat) -> CGVector {
        func vy(_ t: CGFloat) -> CGFloat { dy / t + gravity * t / 2 }
        var t = time
        while t > 0.16, max(0, vy(t)) * vy(t) / (2 * gravity) > max(0, headroom) { t -= 0.02 }
        let drag = log(1 / 0.6)
        return CGVector(dx: dx * drag / (1 - pow(0.6, t)), dy: vy(t))
    }

    /// 입 위치 + 개가 장난감 물고 흔들듯 좌우로 휙휙
    static func mouthPoint(petFrame: CGRect, facing: Direction, time: TimeInterval) -> CGPoint {
        let x = petFrame.minX + petFrame.width * (facing == .right ? 0.78 : 0.22)
        let y = petFrame.minY + petFrame.height * 0.42
        return CGPoint(x: x + CGFloat(sin(time * 38)) * 7, y: y + CGFloat(sin(time * 29)) * 4)
    }
}

/// 던져진 포인터가 날아가는 길 (포물선). 화면 밖으로는 안 나가게 가장 가까운 화면 안으로 붙인다.
struct PointerThrow: Equatable {
    var start: CGPoint
    var velocity: CGVector
    var gravity: CGFloat = 2400
    var duration: TimeInterval = 0.75
    /// 포인터가 갈 수 있는 화면들 (NSScreen.frame, AppKit 좌표)
    var screens: [CGRect]
    /// 날아가는 동안 사용자가 마우스를 움직인 만큼 (길 전체가 그만큼 옮겨진다 → 던지는 중에도 마우스가 먹힌다)
    var offset: CGVector = .zero

    /// 던지는 쪽 (펫이 그쪽을 보게)
    var direction: Direction { velocity.dx < 0 ? .left : .right }

    /// 매번 다르게 휙: 방향·거리·높이·날아가는 시간이 랜덤.
    /// - 높이: 위쪽 공간 안에서 60~900pt (공간이 넉넉하면 하늘 높이 솟구치기도). 날아가는 시간은 꼭대기까지 오른 뒤
    ///   조금 떨어지는 동안(꼭대기 시간의 1.3~2배)
    /// - 가로: 고른 쪽에 공간이 모자라면 넓은 반대쪽으로, 양쪽 다 좁으면 남은 공간 안에 떨어지게
    static func toss(from start: CGPoint, screens: [CGRect],
                     using rng: inout some RandomNumberGenerator) -> PointerThrow {
        var path = PointerThrow(start: start, velocity: .zero, screens: screens)
        let up = roomAbove(start, screens: screens)
        let height = CGFloat.random(in: 60...max(60, min(900, up * 0.9)), using: &rng)
        let vy = sqrt(2 * path.gravity * height)
        let apexTime = Double(vy / path.gravity)
        path.duration = min(1.6, max(0.45, apexTime * Double.random(in: 1.3...2.0, using: &rng)))
        let picked: Direction = Bool.random(using: &rng) ? .right : .left
        var distance = CGFloat.random(in: 150...1000, using: &rng)
        let here = room(from: start, toward: picked, screens: screens)
        let there = room(from: start, toward: picked.flipped, screens: screens)
        let dir = here >= distance || here >= there ? picked : picked.flipped
        distance = min(distance, max(here, there) * 0.9)
        path.velocity = CGVector(dx: dir.sign * distance / CGFloat(path.duration), dy: vy)
        return path
    }

    /// 점 위로 화면 천장까지 남은 높이
    static func roomAbove(_ p: CGPoint, screens: [CGRect]) -> CGFloat {
        screens.filter { $0.minX <= p.x && p.x < $0.maxX && $0.minY <= p.y && p.y < $0.maxY }.map { $0.maxY - p.y }.max() ?? 0
    }

    /// 점에서 그쪽 화면 끝까지 가로 공간 (같은 높이로 이어진 옆 모니터까지 포함)
    static func room(from p: CGPoint, toward dir: Direction, screens: [CGRect]) -> CGFloat {
        var x = p.x
        for _ in 0..<screens.count {
            guard let s = screens.first(where: { $0.minY <= p.y && p.y < $0.maxY
                && (dir == .right ? $0.minX <= x + 0.5 && x + 0.5 < $0.maxX : $0.minX < x - 0.5 && x - 0.5 <= $0.maxX) })
            else { break }
            x = dir == .right ? s.maxX : s.minX
        }
        return abs(x - p.x)
    }

    func isFinished(at t: TimeInterval) -> Bool { t >= duration }

    func position(at t: TimeInterval) -> CGPoint {
        let t = CGFloat(min(max(t, 0), duration))
        let p = CGPoint(x: start.x + velocity.dx * t + offset.dx,
                        y: start.y + velocity.dy * t - gravity * t * t / 2 + offset.dy)
        return Self.clamp(p, into: screens)
    }

    /// 어느 화면에도 없으면 가장 가까운 화면 안쪽(1pt)으로
    static func clamp(_ p: CGPoint, into screens: [CGRect]) -> CGPoint {
        if screens.contains(where: { $0.contains(p) }) || screens.isEmpty { return p }
        let inside = screens.map { s in
            CGPoint(x: min(max(p.x, s.minX + 1), s.maxX - 1), y: min(max(p.y, s.minY + 1), s.maxY - 1))
        }
        return inside.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }!
    }
}
