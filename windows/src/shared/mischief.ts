// 장난꾸러기 모드: 켜져 있는 동안 마우스 포인터를 계속 쫓아다니다가 → 잡으면 물고 흔들다가 → 휙 던진다.
// 맥 앱 Sources/Pet/Mischief.swift 를 그대로 옮김 (y 위로 증가 좌표, geometry.ts 참고).
// React 비유: useReducer — 매 프레임 tick(입력)을 dispatch 하면 할 일(명령)을 돌려준다. 실제 포인터 이동·걷기는 pet.ts 가 한다.
import { flipped, maxY, midX, sign, type Direction, type Point, type Rect, type Vector } from './geometry'
import type { Random } from './brain'

export interface MischiefConfig {
  /** 모드를 켠 뒤 쫓기 시작할 때까지 */
  startDelay: number
  /** 물고 흔드는 시간 */
  biteDuration: number
  /** 던진 뒤 숨 고르는 시간 (그다음 다시 쫓아온다) */
  cooldownAfterThrow: number
  /** 벽에 막혀 돌아섰거나 클릭으로 놓아줬을 때 잠깐 쉬는 시간 */
  cooldownAfterGiveUp: number
}

export const defaultMischiefConfig: MischiefConfig = { startDelay: 1, biteDuration: 1.3, cooldownAfterThrow: 4, cooldownAfterGiveUp: 2.5 }

export type MischiefPhase = 'ready' | 'chasing' | 'biting' | 'throwing'

/** 한 프레임 입력 */
export interface MischiefInput {
  petFrame: Rect
  cursor: Point
  facing: Direction
  /** 놀 수 있는 상태 (모드 켜짐, 보임, 안 잠, 안 잡힘, 말풍선 없음) */
  canPlay: boolean
  /** 마우스 버튼을 누르고 있음 (드래그·선택 중이면 절대 안 문다 / 물고 있을 때 누르면 놓아준다) */
  mouseDown: boolean
  /** 바닥·창 위에 서 있음 (떨어지거나 벽 타는 중이 아님) */
  grounded: boolean
  /** 벽을 타는 중이면 벽이 있는 쪽 */
  climbingSide?: Direction
  /** 포인터에 가장 가까운 기어오를 벽 쪽 */
  wallDirection?: Direction
  /** 몸 위쪽 여유 (화면 천장까지). 높은 데서 몸을 날릴 때 천장에 머리를 박지 않게 */
  headroom?: number
}

export type MischiefCommand =
  | { type: 'none' }
  | { type: 'chase'; direction: Direction }
  | { type: 'jump'; velocity: Vector }
  | { type: 'stopChase' }
  | { type: 'startBite' }
  | { type: 'holdPointer'; point: Point }
  | { type: 'throwPointer' }
  | { type: 'release' }

const NONE: MischiefCommand = { type: 'none' }
const midY = (r: Rect) => r.y + r.height / 2

export class Mischief {
  /** 바닥에서 한 번에 뛰어오를 수 있는 높이 */
  static readonly maxRise = 320
  /** 몸을 날려 닿을 수 있는 거리 (몸 중심 → 포인터) */
  static readonly leapRange = 380
  /** 벽에 매달려 포인터 높이까지 올라왔을 때 벽을 차고 날아갈 수 있는 거리 */
  static readonly wallLeapRange = 1000

  phase: MischiefPhase = 'ready'
  /** 지금 단계에 들어온 뒤 지난 시간 */
  phaseTime = 0
  /** 포인터가 너무 높아서 벽을 찾아 달려가는 방향 (벽에 붙으면 끝) */
  seekDirection?: Direction
  private cooldown: number
  private biteLeft = 0
  /** 바닥에 내려선 뒤 지난 시간 (점프 사이에 잠깐 웅크리는 박자) */
  private groundedTime = 0

  constructor(readonly config: MischiefConfig = defaultMischiefConfig) {
    this.cooldown = config.startDelay
  }

  tick(dt: number, input: MischiefInput): MischiefCommand {
    this.phaseTime += dt
    this.groundedTime = input.grounded ? this.groundedTime + dt : 0
    if (!input.canPlay) {
      if (this.phase === 'chasing') {
        this.rest(this.config.cooldownAfterGiveUp)
        return { type: 'stopChase' }
      }
      if (this.phase === 'biting') {
        this.rest(this.config.cooldownAfterGiveUp)
        return { type: 'release' }
      }
      return NONE
    }

    switch (this.phase) {
      case 'ready':
        this.cooldown -= dt
        if (this.cooldown > 0 || !input.grounded || input.mouseDown) return NONE
        this.enter('chasing')
        return this.chase(input)
      case 'chasing':
        if (!input.mouseDown && Mischief.catches(input.petFrame, input.cursor)) {
          this.enter('biting')
          this.biteLeft = this.config.biteDuration
          return { type: 'startBite' }
        }
        return this.chase(input)
      case 'biting':
        if (input.mouseDown) {
          // 클릭하면 놓아준다
          this.rest(this.config.cooldownAfterGiveUp)
          return { type: 'release' }
        }
        this.biteLeft -= dt
        // 공중에서 물었으면 문 채로 땅에 떨어진 뒤에 던진다 (너무 오래 걸리면 그냥 던짐)
        if (this.biteLeft <= 0 && (input.grounded || this.phaseTime > 5)) {
          this.enter('throwing')
          return { type: 'throwPointer' }
        }
        return { type: 'holdPointer', point: Mischief.mouthPoint(input.petFrame, input.facing, this.phaseTime) }
      case 'throwing':
        return NONE
    }
  }

  /** 쫓는 중: 걷기 / 점프 / 벽 찾아 달리기 / 벽에서 몸 날리기 */
  private chase(input: MischiefInput): MischiefCommand {
    const frame = input.petFrame
    const cursor = input.cursor
    const headroom = input.headroom ?? Infinity
    const leap = Mischief.leapVelocity(frame, cursor, headroom)

    // 벽 타는 중: 포인터가 벽 반대쪽(트인 쪽)에 있고 닿을 거리면 벽을 차고 몸을 날린다.
    // 멀리 있으면 포인터 높이까지 올라온 뒤에 (pet.ts 가 오르는 높이를 포인터에 맞춘다) 멀리 날아간다
    if (input.climbingSide) {
      const behindWall = (cursor.x - midX(frame)) * sign(input.climbingSide) > frame.width * 0.5
      if (behindWall) return NONE
      if (leap) return { type: 'jump', velocity: leap }
      const far = cursor.y - midY(frame) <= 40 ? Mischief.wallLeap(frame, cursor, headroom) : undefined
      return far ? { type: 'jump', velocity: far } : NONE
    }
    if (!input.grounded) return NONE // 공중에선 잡히는지만 본다

    const chaseToward = (): MischiefCommand => {
      const d = Mischief.chaseDirection(frame, cursor.x)
      return d ? { type: 'chase', direction: d } : NONE
    }
    if (cursor.y <= maxY(frame) - 4) {
      this.seekDirection = undefined
      return chaseToward()
    }
    // 머리 위 닿는 거리 → 웅크렸다 점프해서 낚아채기
    if (leap) {
      this.seekDirection = undefined
      return this.groundedTime >= 0.25 ? { type: 'jump', velocity: leap } : NONE
    }
    // 너무 높다 → 포인터에 가장 가까운 벽으로 달려가 타고 오른다 (방향은 벽에 닿을 때까지 유지)
    const dx = cursor.x - midX(frame)
    this.seekDirection ??= input.wallDirection
    if (this.seekDirection) return { type: 'chase', direction: this.seekDirection }
    // 탈 벽이 없고(창 위 등) 아직 멀면 일단 그쪽으로
    if (Math.abs(dx) > Mischief.leapRange * 0.7) return chaseToward()
    // 탈 벽도 없으면 제자리에서 힘껏 뛰어 본다 (안 닿아도 귀엽게)
    return this.groundedTime >= 0.9
      ? { type: 'jump', velocity: { dx: Math.max(-120, Math.min(120, dx * 2)), dy: Math.sqrt(2 * 1800 * Mischief.maxRise) } }
      : NONE
  }

  /** 벽을 타기 시작했다 (벽 찾기 끝) */
  didStartClimbing() {
    this.seekDirection = undefined
  }

  /** 포인터가 다 날아갔다 */
  finishThrow() {
    if (this.phase === 'throwing') this.rest(this.config.cooldownAfterThrow)
  }

  /** 쫓다가 벽에 막히는 등 컨트롤러 사정으로 포기 */
  giveUp() {
    if (this.phase === 'chasing') this.rest(this.config.cooldownAfterGiveUp)
  }

  /** 모드를 끄면 바로 원래대로 */
  reset() {
    this.phase = 'ready'
    this.phaseTime = 0
    this.cooldown = this.config.startDelay
  }

  private enter(p: MischiefPhase) {
    this.phase = p
    this.phaseTime = 0
  }

  private rest(seconds: number) {
    this.enter('ready')
    this.cooldown = seconds
    this.seekDirection = undefined
  }

  // MARK: 계산 (테스트용 static)

  /** 포인터가 몸에 닿으면 잡힌다 (테두리 6 여유) */
  static catches(petFrame: Rect, cursor: Point): boolean {
    return cursor.x >= petFrame.x - 6 && cursor.x <= petFrame.x + petFrame.width + 6 && cursor.y >= petFrame.y - 6 && cursor.y <= maxY(petFrame) + 6
  }

  /** 포인터 쪽 방향. 거의 바로 위·아래면 undefined (제자리) */
  static chaseDirection(petFrame: Rect, cursorX: number): Direction | undefined {
    const dx = cursorX - midX(petFrame)
    if (Math.abs(dx) <= petFrame.width * 0.2) return undefined
    return dx > 0 ? 'right' : 'left'
  }

  /** 몸 중심이 포인터를 지나가도록 던지는 포물선 초속 (중력 1800). 너무 멀거나 높으면 undefined */
  static leapVelocity(petFrame: Rect, cursor: Point, headroom = Infinity, gravity = 1800): Vector | undefined {
    const dx = cursor.x - midX(petFrame)
    const dy = cursor.y - midY(petFrame)
    const distance = Math.hypot(dx, dy)
    if (distance > Mischief.leapRange || dy > Mischief.maxRise || dy <= -petFrame.height) return undefined
    return parabola(dx, dy, Math.min(0.5, Math.max(0.22, distance / 750)), headroom, gravity)
  }

  /** 벽에서 포인터 높이쯤까지 올라와 멀리 날아가기 (바닥 점프보다 멀리, 빠르고 낮게) */
  static wallLeap(petFrame: Rect, cursor: Point, headroom = Infinity, gravity = 1800): Vector | undefined {
    const dx = cursor.x - midX(petFrame)
    const dy = cursor.y - midY(petFrame)
    if (Math.abs(dx) > Mischief.wallLeapRange || dy > Mischief.maxRise || dy <= -Mischief.wallLeapRange) return undefined
    return parabola(dx, dy, Math.min(0.6, Math.max(0.22, Math.hypot(dx, dy) / 1400)), headroom, gravity)
  }

  /** 입 위치 + 개가 장난감 물고 흔들듯 좌우로 휙휙 */
  static mouthPoint(petFrame: Rect, facing: Direction, time: number): Point {
    const x = petFrame.x + petFrame.width * (facing === 'right' ? 0.78 : 0.22)
    const y = petFrame.y + petFrame.height * 0.42
    return { x: x + Math.sin(time * 38) * 7, y: y + Math.sin(time * 29) * 4 }
  }
}

/**
 * 시간 T 동안 (dx, dy)만큼 가는 초속. 꼭대기가 headroom 보다 높아지면 T를 줄여 더 낮고 빠르게.
 * 가로는 물리의 공기 저항(초당 0.6배)만큼 덜 가니 그만큼 키운다: x(T) = vx·(1 − 0.6^T) / ln(1/0.6)
 */
function parabola(dx: number, dy: number, time: number, headroom: number, gravity: number): Vector {
  const vy = (t: number) => dy / t + (gravity * t) / 2
  let t = time
  while (t > 0.16 && (Math.max(0, vy(t)) * vy(t)) / (2 * gravity) > Math.max(0, headroom)) t -= 0.02
  return { dx: (dx * Math.log(1 / 0.6)) / (1 - Math.pow(0.6, t)), dy: vy(t) }
}

/** 던져진 포인터가 날아가는 길 (포물선). 화면 밖으로는 안 나가게 가장 가까운 화면 안으로 붙인다 */
export class PointerThrow {
  gravity = 2400
  /** 날아가는 동안 사용자가 마우스를 움직인 만큼 (길 전체가 옮겨진다) */
  offset: Vector = { dx: 0, dy: 0 }

  constructor(
    readonly start: Point,
    public velocity: Vector,
    /** 포인터가 갈 수 있는 화면들 (모델 좌표) */
    readonly screens: Rect[],
    public duration = 0.75,
  ) {}

  /** 던지는 쪽 (펫이 그쪽을 보게) */
  get direction(): Direction {
    return this.velocity.dx < 0 ? 'left' : 'right'
  }

  /**
   * 매번 다르게 휙: 방향·거리·높이·날아가는 시간이 랜덤.
   * - 높이: 위쪽 공간 안에서 60~900 (공간이 넉넉하면 하늘 높이 솟구치기도). 시간은 꼭대기까지 오른 뒤 조금 떨어지는 동안(꼭대기 시간의 1.3~2배)
   * - 가로: 고른 쪽 공간이 모자라면 넓은 반대쪽으로, 양쪽 다 좁으면 남은 공간 안에 떨어지게
   */
  static toss(start: Point, screens: Rect[], rng: Random): PointerThrow {
    const between = (a: number, b: number) => a + (b - a) * rng()
    const gravity = 2400
    const up = PointerThrow.roomAbove(start, screens)
    const height = between(60, Math.max(60, Math.min(900, up * 0.9)))
    const vy = Math.sqrt(2 * gravity * height)
    const duration = Math.min(1.6, Math.max(0.45, (vy / gravity) * between(1.3, 2.0)))
    const picked: Direction = rng() < 0.5 ? 'right' : 'left'
    let distance = between(150, 1000)
    const here = PointerThrow.room(start, picked, screens)
    const there = PointerThrow.room(start, flipped(picked), screens)
    const dir = here >= distance || here >= there ? picked : flipped(picked)
    distance = Math.min(distance, Math.max(here, there) * 0.9)
    return new PointerThrow(start, { dx: (sign(dir) * distance) / duration, dy: vy }, screens, duration)
  }

  /** 점 위로 화면 천장까지 남은 높이 */
  static roomAbove(p: Point, screens: Rect[]): number {
    const ups = screens.filter((s) => s.x <= p.x && p.x < s.x + s.width && s.y <= p.y && p.y < maxY(s)).map((s) => maxY(s) - p.y)
    return ups.length ? Math.max(...ups) : 0
  }

  /** 점에서 그쪽 화면 끝까지 가로 공간 (같은 높이로 이어진 옆 모니터까지 포함) */
  static room(p: Point, dir: Direction, screens: Rect[]): number {
    let x = p.x
    for (let k = 0; k < screens.length; k++) {
      const s = screens.find(
        (r) => r.y <= p.y && p.y < maxY(r) && (dir === 'right' ? r.x <= x + 0.5 && x + 0.5 < r.x + r.width : r.x < x - 0.5 && x - 0.5 <= r.x + r.width),
      )
      if (!s) break
      x = dir === 'right' ? s.x + s.width : s.x
    }
    return Math.abs(x - p.x)
  }

  isFinished(t: number) {
    return t >= this.duration
  }

  position(t: number): Point {
    const tt = Math.min(Math.max(t, 0), this.duration)
    const p = {
      x: this.start.x + this.velocity.dx * tt + this.offset.dx,
      y: this.start.y + this.velocity.dy * tt - (this.gravity * tt * tt) / 2 + this.offset.dy,
    }
    return PointerThrow.clamp(p, this.screens)
  }

  /** 어느 화면에도 없으면 가장 가까운 화면 안쪽(1)으로 */
  static clamp(p: Point, screens: Rect[]): Point {
    if (screens.length === 0 || screens.some((s) => p.x >= s.x && p.x < s.x + s.width && p.y >= s.y && p.y < maxY(s))) return p
    let best = p
    let bestD = Infinity
    for (const s of screens) {
      const q = { x: Math.min(Math.max(p.x, s.x + 1), s.x + s.width - 1), y: Math.min(Math.max(p.y, s.y + 1), maxY(s) - 1) }
      const d = Math.hypot(q.x - p.x, q.y - p.y)
      if (d < bestD) {
        bestD = d
        best = q
      }
    }
    return best
  }
}

/** 마지막으로 옮겨 둔 곳에서 사용자가 마우스를 움직인 만큼. 1 미만은 반올림 오차로 보고 무시 */
export function userMove(warped: Point | undefined, now: Point, threshold = 1): Vector {
  if (!warped) return { dx: 0, dy: 0 }
  const d = { dx: now.x - warped.x, dy: now.y - warped.y }
  return Math.hypot(d.dx, d.dy) < threshold ? { dx: 0, dy: 0 } : d
}
