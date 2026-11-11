// 펫의 "두뇌" = 상태 머신. 맥 앱 Sources/Pet/PetBrain.swift 를 그대로 옮김.
// React 비유: useReducer 의 reducer. tick() ≈ 매 프레임 타이머 reducer, handle() ≈ dispatch(action).
// 클래스지만 UI·Electron 비의존이라 Vitest로 테스트한다. rng 를 주입해 결과를 재현할 수 있다.
import type { PetAction } from './characterPack'
import { flipped, type Direction } from './geometry'

export type Random = () => number // 0 ≤ r < 1

export interface BrainConfig {
  idleDuration: [number, number]
  walkDuration: [number, number]
  /** 이벤트 반응(happy/angry/ask/talk) 기본 유지 시간 */
  reactionDuration: number
  /** 펫을 클릭했을 때 짧은 happy 반응 시간 */
  clickReactionDuration: number
  /** 이 시간 동안 아무 일도 없으면 잠든다 (기본 10분) */
  sleepAfter: number
  /** 창 옆면에 막혔을 때 기어오를 확률 */
  climbWindowChance: number
  /** 화면 끝 벽을 기어오를 확률 */
  climbScreenChance: number
  /** 창 위에서 끝에 닿았을 때 뛰어내릴 확률 */
  edgeJumpChance: number
  /** 모니터 경계에서 옆 모니터로 넘어갈 확률 (턱을 기어오르거나 폴짝 건너뛴다. 나머지는 돌아선다) */
  crossScreenChance: number
}

export const defaultBrainConfig: BrainConfig = {
  idleDuration: [2, 6],
  walkDuration: [3, 8],
  reactionDuration: 4,
  clickReactionDuration: 1.5,
  sleepAfter: 600,
  climbWindowChance: 0.75,
  climbScreenChance: 0.3,
  edgeJumpChance: 0.4,
  crossScreenChance: 0.7,
}

/** 외부 입력 (TS 판별 유니온) */
export type BrainInput =
  | { type: 'clicked' }
  | { type: 'dragStarted' }
  | { type: 'startFall' }
  | { type: 'landed' }
  | { type: 'hitWall'; window: boolean }
  | { type: 'reachedEdge' }
  /** 옆 모니터 바닥이 더 높은 경계(턱) → 기어올라 넘어가거나 돌아선다 */
  | { type: 'hitStep' }
  /** 같은 높이·더 낮은 옆 모니터 경계 → 폴짝 건너뛰거나 돌아선다 */
  | { type: 'reachedScreenEdge' }
  | { type: 'climbedUp' }
  | { type: 'letGo' }
  | { type: 'react'; action: PetAction; duration?: number }
  | { type: 'sleep' }
  | { type: 'wake' }
  /** 장난꾸러기 모드: 포인터 쪽으로 달린다 */
  | { type: 'chase'; direction: Direction }
  /** 장난꾸러기 모드: 쫓다가 벽에 막힘 → 확률 없이 바로 타고 오른다 */
  | { type: 'climbNow' }
  /** 그쪽을 바라본다 (점프·던지기 방향) */
  | { type: 'face'; direction: Direction }

const isReaction = (a: PetAction) => a === 'talk' || a === 'happy' || a === 'angry' || a === 'ask'
/** 사용자가 잡고 있거나 떨어지는 중 → 다른 입력으로 끊으면 안 되는 상태 */
export const isPhysicsControlled = (a: PetAction) => a === 'dragged' || a === 'fall' || a === 'climb'

const between = (rng: Random, [a, b]: [number, number]) => a + (b - a) * rng()

export class PetBrain {
  action: PetAction = 'idle'
  direction: Direction = 'right'
  /** 현재 상태에 들어온 뒤 지난 시간 */
  elapsed = 0
  /** 현재 상태 유지 시간 (Infinity = 외부 입력까지) */
  duration: number
  /** 마지막 활동 이후 지난 시간 */
  inactivity = 0
  /** 상태 진입 때마다 뽑는 난수 → 포즈(idle.2 등) 고르기 */
  variant = 0
  /** 잠든 상태. 들어서 옮기거나 떨어지는 동안(action 은 dragged/fall)에도 유지되고, 착지하면 다시 sleep. 깨는 건 'wake'(재우기/깨우기 토글)뿐 */
  isAsleep = false
  /** 사용자가 '재우기'로 재웠음 → 알림이 와도 안 깬다. 오래 쉬어서 저절로 잠든 거면 알림에 깬다 */
  sleptByUser = false

  constructor(readonly config: BrainConfig = defaultBrainConfig) {
    this.duration = config.idleDuration[0]
  }

  tick(dt: number, rng: Random) {
    this.elapsed += dt
    switch (this.action) {
      case 'idle':
      case 'walk':
        this.inactivity += dt
        if (this.inactivity >= this.config.sleepAfter) {
          this.fallAsleep(false, rng)
          return
        }
        if (this.elapsed < this.duration) return
        if (this.action === 'idle') {
          this.direction = rng() < 0.5 ? 'left' : 'right'
          this.enter('walk', between(rng, this.config.walkDuration), rng)
        } else {
          this.enterIdle(rng)
        }
        return
      default:
        if (isReaction(this.action) && this.elapsed >= this.duration) this.enterIdle(rng)
      // sleep/dragged/fall/climb 은 외부 입력으로만 바뀜
    }
  }

  handle(input: BrainInput, rng: Random) {
    switch (input.type) {
      case 'clicked':
        if (this.isAsleep) return // 자고 있으면 클릭해도 안 깬다 (토글로만)
        this.inactivity = 0
        if (!isPhysicsControlled(this.action) && this.action !== 'sleep') this.enter('happy', this.config.clickReactionDuration, rng)
        return
      case 'dragStarted':
        this.inactivity = 0
        this.enter('dragged', Infinity, rng)
        return
      case 'startFall':
        this.enter('fall', Infinity, rng)
        return
      case 'landed':
        if (this.action !== 'fall') return
        if (this.isAsleep) this.enter('sleep', Infinity, rng) // 옮겨져도 계속 잔다
        else this.enterIdle(rng)
        return
      case 'hitWall': {
        if (this.action !== 'walk') {
          this.direction = flipped(this.direction)
          return
        }
        const chance = input.window ? this.config.climbWindowChance : this.config.climbScreenChance
        if (rng() < chance) this.enter('climb', Infinity, rng)
        else this.direction = flipped(this.direction)
        return
      }
      case 'reachedEdge':
        if (rng() < this.config.edgeJumpChance) this.enter('fall', Infinity, rng)
        else this.direction = flipped(this.direction)
        return
      case 'hitStep':
        if (this.action === 'walk' && rng() < this.config.crossScreenChance) this.enter('climb', Infinity, rng)
        else this.direction = flipped(this.direction)
        return
      case 'reachedScreenEdge':
        // 폴짝 (초속은 pet.ts 가 screenHop 으로)
        if (this.action === 'walk' && rng() < this.config.crossScreenChance) this.enter('fall', Infinity, rng)
        else this.direction = flipped(this.direction)
        return
      case 'climbedUp':
        if (this.action !== 'climb') return
        if (this.isAsleep) this.enter('sleep', Infinity, rng)
        else this.enter('walk', between(rng, this.config.walkDuration), rng)
        return
      case 'letGo':
        if (this.action !== 'climb') return
        this.direction = flipped(this.direction) // 벽 반대쪽으로 뛴다
        this.enter('fall', Infinity, rng)
        return
      case 'react':
        if (this.isAsleep) {
          if (this.sleptByUser) return // 재워 둔 거면 알림에도 계속 잔다
          this.isAsleep = false // 저절로 잠든 거면 알림에 깬다
        }
        this.inactivity = 0
        if (isPhysicsControlled(this.action)) return
        this.enter(input.action, input.duration ?? this.config.reactionDuration, rng)
        return
      case 'sleep':
        if (!isPhysicsControlled(this.action)) this.fallAsleep(true, rng)
        return
      case 'wake':
        this.inactivity = 0
        this.isAsleep = false
        this.sleptByUser = false
        if (this.action === 'sleep') this.enterIdle(rng)
        return
      case 'chase':
        this.inactivity = 0
        if (this.action === 'walk') {
          this.direction = input.direction
          this.duration = Math.max(this.duration, this.elapsed + 1) // 계속 쫓는 동안은 걷기가 끝나지 않게
        } else if (this.action === 'idle' || this.action === 'talk' || this.action === 'happy' || this.action === 'ask') {
          this.direction = input.direction
          this.enter('walk', 1, rng)
        } // 자는 중·떨어지는 중·벽 타기는 그대로
        return
      case 'climbNow':
        if (this.action === 'walk') this.enter('climb', Infinity, rng)
        return
      case 'face':
        if (this.action !== 'dragged') this.direction = input.direction
        return
    }
  }

  private fallAsleep(byUser: boolean, rng: Random) {
    this.isAsleep = true
    this.sleptByUser = byUser
    this.enter('sleep', Infinity, rng)
  }

  private enter(action: PetAction, duration: number, rng: Random) {
    if (action !== this.action) this.variant = Math.floor(rng() * 1000)
    this.action = action
    this.duration = duration
    this.elapsed = 0
  }

  private enterIdle(rng: Random) {
    this.enter('idle', between(rng, this.config.idleDuration), rng)
  }
}
