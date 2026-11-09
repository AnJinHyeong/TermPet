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
    }

    /// 외부에서 들어오는 입력. TS의 판별 유니온(`{ type: 'react', action, duration }`)과 같다.
    enum Input: Equatable {
        case clicked
        case dragStarted
        case startFall            // 드롭했거나 발밑에 바닥이 없어짐
        case landed               // 바닥에 닿음
        case hitWall              // 화면 끝에 닿음 → 방향 전환
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
                enter(.sleep, for: .infinity)
                return
            }
            guard elapsed >= duration else { return }
            if action == .idle {
                direction = Bool.random(using: &rng) ? .left : .right
                enter(.walk, for: .random(in: config.walkDuration, using: &rng))
            } else {
                enterIdle(using: &rng)
            }

        case .talk, .happy, .angry, .ask:
            if elapsed >= duration { enterIdle(using: &rng) }

        case .sleep, .dragged, .fall:
            break // 외부 입력(깨우기/드롭/착지)으로만 바뀜
        }
    }

    mutating func handle(_ input: Input, using rng: inout some RandomNumberGenerator) {
        switch input {
        case .clicked:
            inactivity = 0
            switch action {
            case .sleep: enterIdle(using: &rng)          // 자고 있으면 깨어나기만
            case .dragged, .fall: break
            default: enter(.happy, for: config.clickReactionDuration)
            }

        case .dragStarted:
            inactivity = 0
            enter(.dragged, for: .infinity)

        case .startFall:
            enter(.fall, for: .infinity)

        case .landed:
            guard action == .fall else { return }
            enterIdle(using: &rng)

        case .hitWall:
            direction = direction.flipped

        case let .react(reaction, customDuration):
            inactivity = 0
            guard !action.isPhysicsControlled else { return }
            enter(reaction, for: customDuration ?? config.reactionDuration)

        case .sleep:
            guard !action.isPhysicsControlled else { return }
            enter(.sleep, for: .infinity)

        case .wake:
            inactivity = 0
            if action == .sleep { enterIdle(using: &rng) }
        }
    }

    // MARK: - private

    private mutating func enter(_ newAction: PetAction, for newDuration: TimeInterval) {
        action = newAction
        duration = newDuration
        elapsed = 0
    }

    private mutating func enterIdle(using rng: inout some RandomNumberGenerator) {
        enter(.idle, for: .random(in: config.idleDuration, using: &rng))
    }
}
