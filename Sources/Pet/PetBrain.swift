import Foundation

/// 펫의 "두뇌" = 상태 머신. UI/AppKit에 전혀 의존하지 않는 순수 값 타입이라 단위 테스트가 쉽다.
///
/// React 비유: `useReducer`의 reducer와 같다.
///   - `handle(_:)` ≈ `dispatch(action)` — 입력(클릭, 드래그 등)을 받아 상태를 바꾼다
///   - `tick(_:)`   ≈ 매 프레임 호출되는 타이머 reducer
/// Swift `struct`는 값 타입이라 복사하면 독립된 사본이 생긴다(불변 객체 spread와 비슷).
/// 상태를 바꾸는 메서드에는 `mutating` 키워드가 붙는다.
struct PetBrain {
    struct Config {
        var idleDuration: ClosedRange<TimeInterval> = 2...6
        var walkDuration: ClosedRange<TimeInterval> = 3...8
        /// 이벤트 반응(happy/angry/ask/talk) 기본 유지 시간
        var reactionDuration: TimeInterval = 4
        /// 펫을 클릭했을 때 짧은 happy 반응 시간
        var clickReactionDuration: TimeInterval = 1.5
        /// 이 시간 동안 아무 일도 없으면 잠든다 (기본 10분)
        var sleepAfter: TimeInterval = 600
        /// 창 옆면에 막혔을 때 기어오를 확률 (나머지는 돌아선다)
        var climbWindowChance: Double = 0.75
        /// 화면 끝 벽을 기어오를 확률 (조금 오르다 뛰어내린다)
        var climbScreenChance: Double = 0.3
        /// 창 위에서 끝에 닿았을 때 뛰어내릴 확률 (나머지는 돌아선다)
        var edgeJumpChance: Double = 0.4
        /// 모니터 경계에서 옆 모니터로 넘어갈 확률 (턱을 기어오르거나 폴짝 건너뛴다. 나머지는 돌아선다)
        var crossScreenChance: Double = 0.7
    }

    /// 외부에서 들어오는 입력. TS의 판별 유니온(`{ type: 'react', action, duration }`)과 같다.
    enum Input: Equatable {
        case clicked
        case dragStarted
        case startFall            // 드롭했거나 발밑에 바닥이 없어짐
        case landed               // 바닥에 닿음
        case hitWall(window: Bool = false) // 벽에 막힘 → 기어오르거나 돌아선다
        case reachedEdge          // 창 위에서 끝에 닿음 → 뛰어내리거나 돌아선다
        case hitStep              // 옆 모니터 바닥이 더 높은 경계(턱) → 기어올라 넘어가거나 돌아선다
        case reachedScreenEdge    // 같은 높이·더 낮은 옆 모니터 경계 → 폴짝 건너뛰거나 돌아선다
        case climbedUp            // 벽을 다 올라 창 위에 올라섬 → 계속 걷기
        case letGo                // 벽에서 손을 놓음 → 반대쪽으로 뛰어내림
        case climbOutOfDock       // Dock 뒤에 가려졌음 → 그 자리에서 Dock 위로 기어 올라온다
        case chase(Direction)     // 장난꾸러기 모드: 포인터 쪽으로 달린다 (매 프레임 들어오면 계속, 끊기면 1초 뒤 멈춤)
        case climbNow             // 장난꾸러기 모드: 확률 없이 바로 벽 타기 (포인터가 위에 있음)
        case face(Direction)      // 바라보는 방향만 바꾸기 (포인터 쪽으로 몸을 날릴 때)
        case react(PetAction, duration: TimeInterval? = nil)
        case sleep
        case wake
    }

    let config: Config
    // `private(set)` = 밖에서는 읽기만 가능 (TS의 `readonly` getter + 내부 setter)
    private(set) var action: PetAction = .idle
    private(set) var direction: Direction = .right
    /// 현재 상태에 들어온 뒤 지난 시간
    private(set) var elapsed: TimeInterval = 0
    /// 현재 상태를 유지할 시간 (.infinity = 외부 입력이 있을 때까지)
    private(set) var duration: TimeInterval
    /// 마지막 활동(이벤트/클릭/드래그) 이후 지난 시간
    private(set) var inactivity: TimeInterval = 0
    /// 상태에 들어올 때마다 새로 뽑는 난수 → 같은 동작이라도 그림(포즈)을 골라 쓴다 (캐릭터 팩의 idle.2 등)
    private(set) var variant: Int = 0
    /// 잠든 상태. 들어서 옮기거나 떨어지는 동안(action은 dragged/fall)에도 유지되고, 착지하면 다시 sleep.
    /// 깨는 건 `.wake`(재우기/깨우기 토글)뿐. 클릭·드래그로는 안 깬다.
    private(set) var isAsleep = false
    /// 사용자가 '재우기'로 재웠음 → 알림(이벤트)이 와도 안 깬다. 오래 쉬어서 저절로 잠든 거면 알림에 깬다.
    private(set) var sleptByUser = false

    init(config: Config = Config()) {
        self.config = config
        self.duration = config.idleDuration.lowerBound
    }

    /// 매 프레임 호출. `dt` = 지난 프레임 이후 경과 시간(초).
    /// `inout some RandomNumberGenerator`: 테스트에서는 시드 고정 난수기를 넣어 결과를 재현 가능하게 한다.
    mutating func tick(_ dt: TimeInterval, using rng: inout some RandomNumberGenerator) {
        elapsed += dt

        switch action {
        case .idle, .walk:
            inactivity += dt
            if inactivity >= config.sleepAfter {
                fallAsleep(byUser: false, using: &rng)
                return
            }
            guard elapsed >= duration else { return }
            if action == .idle {
                direction = Bool.random(using: &rng) ? .left : .right
                enter(.walk, for: .random(in: config.walkDuration, using: &rng), using: &rng)
            } else {
                enterIdle(using: &rng)
            }

        case .talk, .happy, .angry, .ask:
            if elapsed >= duration { enterIdle(using: &rng) }

        case .sleep, .dragged, .fall, .climb, .bite: // bite는 그림 전용 (두뇌는 물기 상태로 들어가지 않음)
            break // 외부 입력(깨우기/드롭/착지/다 오름)으로만 바뀜
        }
    }

    mutating func handle(_ input: Input, using rng: inout some RandomNumberGenerator) {
        switch input {
        case .clicked:
            guard !isAsleep else { return }               // 자고 있으면 클릭해도 안 깬다 (토글로만)
            inactivity = 0
            switch action {
            case .dragged, .fall, .climb, .sleep: break
            default: enter(.happy, for: config.clickReactionDuration, using: &rng)
            }

        case .dragStarted:
            inactivity = 0
            enter(.dragged, for: .infinity, using: &rng)

        case .startFall:
            enter(.fall, for: .infinity, using: &rng)

        case .landed:
            guard action == .fall else { return }
            if isAsleep { enter(.sleep, for: .infinity, using: &rng) } else { enterIdle(using: &rng) } // 옮겨져도 계속 잔다

        case let .hitWall(window):
            guard action == .walk else { direction = direction.flipped; return }
            let chance = window ? config.climbWindowChance : config.climbScreenChance
            if Double.random(in: 0..<1, using: &rng) < chance {
                enter(.climb, for: .infinity, using: &rng)
            } else {
                direction = direction.flipped
            }

        case .reachedEdge:
            if Double.random(in: 0..<1, using: &rng) < config.edgeJumpChance {
                enter(.fall, for: .infinity, using: &rng) // 뛰어내리기
            } else {
                direction = direction.flipped
            }

        case .hitStep:
            if action == .walk, Double.random(in: 0..<1, using: &rng) < config.crossScreenChance {
                enter(.climb, for: .infinity, using: &rng)
            } else {
                direction = direction.flipped
            }

        case .reachedScreenEdge:
            if action == .walk, Double.random(in: 0..<1, using: &rng) < config.crossScreenChance {
                enter(.fall, for: .infinity, using: &rng) // 폴짝 (초속은 컨트롤러가 screenHop으로)
            } else {
                direction = direction.flipped
            }

        case let .chase(dir):
            inactivity = 0
            switch action {
            case .walk:
                direction = dir
                duration = max(duration, elapsed + 1) // 계속 쫓는 동안은 걷기가 끝나지 않게
            case .idle, .talk, .happy, .ask:
                direction = dir
                enter(.walk, for: 1, using: &rng)
            default:
                break // 자는 중·화남(물기)·떨어지는 중·벽 타기는 그대로
            }

        case .climbNow:
            guard action == .walk else { return }
            enter(.climb, for: .infinity, using: &rng)

        case let .face(dir):
            guard action != .dragged else { return }
            direction = dir

        case .climbOutOfDock:
            guard action != .dragged, action != .fall else { return }
            enter(.climb, for: .infinity, using: &rng)

        case .climbedUp:
            guard action == .climb else { return }
            if isAsleep { enter(.sleep, for: .infinity, using: &rng); return } // Dock 위로 올라온 뒤에도 계속 잔다
            enter(.walk, for: .random(in: config.walkDuration, using: &rng), using: &rng)

        case .letGo:
            guard action == .climb else { return }
            direction = direction.flipped // 벽 반대쪽으로 뛴다
            enter(.fall, for: .infinity, using: &rng)

        case let .react(reaction, customDuration):
            if isAsleep {
                guard !sleptByUser else { return }        // 재워 둔 거면 알림에도 계속 잔다
                isAsleep = false                          // 저절로 잠든 거면 알림에 깬다
            }
            inactivity = 0
            guard !action.isPhysicsControlled else { return }
            enter(reaction, for: customDuration ?? config.reactionDuration, using: &rng)

        case .sleep:
            guard !action.isPhysicsControlled else { return }
            fallAsleep(byUser: true, using: &rng)

        case .wake:
            inactivity = 0
            isAsleep = false
            sleptByUser = false
            if action == .sleep { enterIdle(using: &rng) }
        }
    }

    private mutating func fallAsleep(byUser: Bool, using rng: inout some RandomNumberGenerator) {
        isAsleep = true
        sleptByUser = byUser
        enter(.sleep, for: .infinity, using: &rng)
    }

    // MARK: - private

    private mutating func enter(_ newAction: PetAction, for newDuration: TimeInterval,
                                using rng: inout some RandomNumberGenerator) {
        if newAction != action { variant = Int.random(in: 0..<1000, using: &rng) }
        action = newAction
        duration = newDuration
        elapsed = 0
    }

    private mutating func enterIdle(using rng: inout some RandomNumberGenerator) {
        enter(.idle, for: .random(in: config.idleDuration, using: &rng), using: &rng)
    }
}
