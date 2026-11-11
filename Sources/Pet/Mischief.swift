import CoreGraphics
import Foundation

/// 장난꾸러기 모드: 마우스 포인터를 쫓아와서 → 물고 흔들다가 → 휙 던진다.
/// AppKit 비의존 순수 상태 머신 (PetBrain처럼 reducer). 실제 포인터 이동·펫 걷기는 컨트롤러가 명령(Command)을 받아 한다.
/// React 비유: `useReducer` — 매 프레임 `tick(입력)`을 dispatch하면 할 일(명령)을 돌려준다.
struct Mischief {
    struct Config {
        /// 포인터가 이 거리(pt, 펫 중심 기준) 안에서 움직이면 쫓아올 마음이 생긴다
        var triggerDistance: CGFloat = 380
        /// 쫓기 시작할 확률 (초당). 매번 바로 달려들면 귀찮으니 가끔만
        var startChancePerSecond: Double = 0.4
        /// 이만큼 멀어지면 포기
        var giveUpDistance: CGFloat = 750
        /// 이 시간 안에 못 잡으면 포기
        var chaseTimeout: TimeInterval = 7
        /// 포인터가 이 시간 동안 안 움직이면 흥미를 잃는다 (가만히 있는 포인터는 안 건드림 = 타이핑 중 방해 X)
        var idleCursorTimeout: TimeInterval = 2.5
        /// 물고 흔드는 시간
        var biteDuration: TimeInterval = 1.3
        /// 던진 뒤 / 포기한 뒤 쉬는 시간
        var cooldownAfterThrow: TimeInterval = 20
        var cooldownAfterGiveUp: TimeInterval = 8
    }

    enum Phase: Equatable {
        case ready      // 쉬는 중 / 기회를 엿보는 중
        case chasing
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
    }

    enum Command: Equatable {
        case none
        case chase(Direction)         // 그쪽으로 달린다
        case jump(CGVector)           // 머리 위 포인터를 향해 점프 (초속)
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
    private var lastCursor: CGPoint?
    private var cursorIdle: TimeInterval = 0

    init(config: Config = Config()) {
        self.config = config
        cooldown = 3 // 켜자마자 덮치지 않게
    }

    mutating func tick(_ dt: TimeInterval, _ input: Input, using rng: inout some RandomNumberGenerator) -> Command {
        phaseTime += dt
        if let last = lastCursor, hypot(last.x - input.cursor.x, last.y - input.cursor.y) < 0.5 {
            cursorIdle += dt
        } else {
            cursorIdle = 0
        }
        lastCursor = input.cursor

        let center = CGPoint(x: input.petFrame.midX, y: input.petFrame.midY)
        let distance = hypot(input.cursor.x - center.x, input.cursor.y - center.y)

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
            guard cooldown <= 0, input.grounded, !input.mouseDown,
                  cursorIdle < config.idleCursorTimeout, distance < config.triggerDistance,
                  Double.random(in: 0..<1, using: &rng) < config.startChancePerSecond * dt else { return .none }
            enter(.chasing)
            return Self.chaseDirection(petFrame: input.petFrame, cursorX: input.cursor.x).map(Command.chase) ?? .none

        case .chasing:
            if !input.mouseDown, Self.catches(petFrame: input.petFrame, cursor: input.cursor) {
                enter(.biting)
                return .startBite
            }
            if phaseTime > config.chaseTimeout || distance > config.giveUpDistance
                || cursorIdle > config.idleCursorTimeout {
                rest(config.cooldownAfterGiveUp)
                return .stopChase
            }
            guard input.grounded else { return .none } // 공중·벽에선 잡히는지만 본다
            if let v = Self.jumpVelocity(petFrame: input.petFrame, cursor: input.cursor) { return .jump(v) }
            return Self.chaseDirection(petFrame: input.petFrame, cursorX: input.cursor.x).map(Command.chase) ?? .none

        case .biting:
            if input.mouseDown { // 클릭하면 놓아준다
                rest(config.cooldownAfterGiveUp)
                return .release
            }
            if phaseTime >= config.biteDuration {
                enter(.throwing)
                return .throwPointer
            }
            return .holdPointer(Self.mouthPoint(petFrame: input.petFrame, facing: input.facing, time: phaseTime))

        case .throwing:
            return .none
        }
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
        cooldown = 3
    }

    private mutating func enter(_ p: Phase) {
        phase = p
        phaseTime = 0
    }

    private mutating func rest(_ seconds: TimeInterval) {
        enter(.ready)
        cooldown = seconds
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

    /// 포인터가 머리 위 닿을 만한 높이에 있으면 점프 초속 (중력 1800 기준). 아니면 nil
    static func jumpVelocity(petFrame: CGRect, cursor: CGPoint, gravity: CGFloat = 1800) -> CGVector? {
        let dx = cursor.x - petFrame.midX
        guard abs(dx) < petFrame.width * 0.6 else { return nil }   // 거의 아래까지 와야 뛴다
        let rise = cursor.y - petFrame.maxY + 14                    // 머리(+여유)가 포인터에 닿을 만큼
        guard rise > 0, rise <= max(160, petFrame.height * 2.5) else { return nil }
        return CGVector(dx: max(-150, min(150, dx * 3)), dy: sqrt(2 * gravity * rise))
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

    /// 펫이 바라보는 쪽 앞위로 휙
    static func toss(from start: CGPoint, facing: Direction, screens: [CGRect],
                     using rng: inout some RandomNumberGenerator) -> PointerThrow {
        PointerThrow(start: start,
                     velocity: CGVector(dx: facing.sign * CGFloat.random(in: 750...1050, using: &rng),
                                        dy: CGFloat.random(in: 650...900, using: &rng)),
                     screens: screens)
    }

    func isFinished(at t: TimeInterval) -> Bool { t >= duration }

    func position(at t: TimeInterval) -> CGPoint {
        let t = CGFloat(min(max(t, 0), duration))
        let p = CGPoint(x: start.x + velocity.dx * t, y: start.y + velocity.dy * t - gravity * t * t / 2)
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
