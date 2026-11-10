// 펫 창 위치 계산(걷기 / 낙하·던지기 / 벽 오르기 / 창 타고 다니기). 맥 앱 PetPhysics.swift 이식.
// origin = 펫 창의 왼쪽 아래(= 발 위치), y 위로 증가 좌표 (geometry.ts).
// 맥의 Dock 발판은 윈도우에 없다 (작업표시줄은 보통 화면 폭 전체라 workArea 바닥이 곧 발판).
import { maxX, maxY, minX, minY, sign, type Direction, type Point, type Rect, type Size, type Vector } from './geometry'
import { ScreenLayout, Terrain, type Wall } from './terrain'

export type WalkResult = { type: 'moved' } | { type: 'hitWall'; wall: Wall } | { type: 'reachedEdge' } | { type: 'startFalling' }
export type ClimbResult = { type: 'climbing' } | { type: 'reachedTop'; windowID: number } | { type: 'letGo' }

export class PetPhysics {
  velocity: Vector = { dx: 0, dy: 0 }
  gravity = 1800
  /** 최대 낙하 속도 — 높은 데서 떨어져도 캐릭터가 보이게 */
  maxFallSpeed = 700
  /** 지금 서 있는 창 (null = 화면 바닥이거나 공중) */
  standingOn: number | null = null

  constructor(
    public origin: Point,
    public size: Size,
  ) {}

  get centerX() {
    return this.origin.x + this.size.width / 2
  }

  // MARK: 걷기

  walk(direction: Direction, speed: number, dt: number, terrain: Terrain): WalkResult {
    const newX = this.origin.x + sign(direction) * speed * dt

    // 1) 창 옆면에 부딪힘
    const wall = terrain.windowWall(this.origin.x, newX, this.origin.y, direction)
    if (wall) {
      this.origin.x = direction === 'right' ? wall.x - this.size.width : wall.x
      // 발목 높이의 낮은 턱은 그냥 올라선다
      const ledge = wall.top - this.origin.y < this.size.height * 0.22 ? terrain.ledgeAfterClimbing(wall) : undefined
      if (ledge) {
        this.origin.y = ledge.y
        this.origin.x = wall.x + sign(direction) - (direction === 'right' ? 0 : this.size.width)
        this.standingOn = ledge.windowID
        return { type: 'moved' }
      }
      return { type: 'hitWall', wall }
    }

    // 2) 창 위에서 걷는 중: 선반 끝이면 멈춘다
    if (this.standingOn !== null) {
      const id = this.standingOn
      if (!terrain.ledge(this.centerX, this.origin.y, id)) {
        this.standingOn = null
        return { type: 'startFalling' }
      }
      if (!terrain.ledge(newX + this.size.width / 2, this.origin.y, id)) return { type: 'reachedEdge' }
      this.origin.x = newX
      return { type: 'moved' }
    }

    // 3) 화면 바닥
    return this.walkOnScreenFloor(direction, newX, terrain.screens)
  }

  private walkOnScreenFloor(direction: Direction, newX: number, layout: ScreenLayout): WalkResult {
    const current = layout.indexContaining(this.centerX, this.origin.y)
    if (current === undefined) return { type: 'startFalling' }
    const f = layout.frames[current]
    const exceedsRight = direction === 'right' && newX + this.size.width > maxX(f)
    const exceedsLeft = direction === 'left' && newX < minX(f)
    if ((exceedsRight || exceedsLeft) && layout.neighbor(current, direction, this.origin.y) === undefined) {
      this.origin.x = exceedsRight ? maxX(f) - this.size.width : minX(f)
      return { type: 'hitWall', wall: { x: exceedsRight ? maxX(f) : minX(f), top: maxY(f), windowID: null, side: direction } }
    }
    this.origin.x = newX
    const now = layout.indexContaining(this.centerX, this.origin.y)
    if (now === undefined) return { type: 'startFalling' }
    return this.origin.y > minY(layout.frames[now]) + 0.5 ? { type: 'startFalling' } : { type: 'moved' }
  }

  // MARK: 낙하 / 던지기 / 점프

  prepareFall(terrain: Terrain, v: Vector = { dx: 0, dy: 0 }) {
    this.velocity = { ...v }
    this.standingOn = null
    this.clampHorizontally(terrain.screens)
  }

  /** 한 프레임 낙하. 착지하면 true */
  fall(dt: number, terrain: Terrain): boolean {
    this.velocity.dy = Math.max(this.velocity.dy - this.gravity * dt, -this.maxFallSpeed)
    this.velocity.dx *= Math.pow(0.6, dt) // 공기 저항
    const nextY = this.origin.y + this.velocity.dy * dt
    this.origin.x += this.velocity.dx * dt
    if (this.bounceOffScreenEdges(terrain.screens)) this.velocity.dx = -this.velocity.dx * 0.45

    if (this.velocity.dy <= 0) {
      const floor = terrain.landing(this.centerX, this.origin.y, nextY)
      if (floor) {
        this.origin.y = floor.y
        this.velocity = { dx: 0, dy: 0 }
        this.standingOn = floor.windowID
        this.clampHorizontally(terrain.screens)
        return true
      }
    }
    if (terrain.screens.frames.length === 0) return true
    this.origin.y = nextY
    // 위로 던졌을 때 화면 위로 사라지지 않게 천장에서 튕김
    const top = terrain.ceiling(this.centerX)
    if (top !== undefined && this.origin.y + this.size.height > top && this.velocity.dy > 0) {
      this.origin.y = top - this.size.height
      this.velocity.dy = -this.velocity.dy * 0.3
    }
    return false
  }

  // MARK: 벽 오르기

  /** limitY: 이 높이(발 기준)까지 오르면 손을 놓는다 */
  climb(wall: Wall, speed: number, dt: number, terrain: Terrain, limitY: number): ClimbResult {
    this.standingOn = null
    this.origin.x = wall.side === 'right' ? wall.x - this.size.width : wall.x
    this.origin.y += speed * dt
    const goal = Math.min(limitY, wall.top)
    if (this.origin.y < goal) return { type: 'climbing' }
    const ledge = this.origin.y >= wall.top - 0.5 ? terrain.ledgeAfterClimbing(wall) : undefined
    if (ledge) {
      this.origin.y = ledge.y
      this.origin.x = wall.side === 'right' ? Math.max(wall.x + 1, ledge.minX) : Math.min(wall.x - this.size.width - 1, ledge.maxX - this.size.width)
      this.standingOn = ledge.windowID
      return { type: 'reachedTop', windowID: ledge.windowID }
    }
    this.origin.y = Math.max(goal, this.origin.y - speed * dt)
    return { type: 'letGo' }
  }

  // MARK: 창 따라가기

  /** 서 있던(또는 매달린) 창이 움직이면 같이 움직인다 (창 윗변 좌측 기준) */
  ride(old: Rect, now: Rect) {
    this.origin.x += minX(now) - minX(old)
    this.origin.y += maxY(now) - maxY(old)
  }

  // MARK: 화면 안으로 보정

  clampHorizontally(layout: ScreenLayout) {
    this.bounceOffScreenEdges(layout)
  }

  private bounceOffScreenEdges(layout: ScreenLayout): boolean {
    const i = layout.indicesInColumn(this.centerX)[0] ?? layout.nearestIndex(this.centerX)
    if (i === undefined) return false
    const f = layout.frames[i]
    if (this.origin.x + this.size.width > maxX(f) && layout.neighbor(i, 'right') === undefined) {
      this.origin.x = maxX(f) - this.size.width
      return true
    }
    if (this.origin.x < minX(f) && layout.neighbor(i, 'left') === undefined) {
      this.origin.x = minX(f)
      return true
    }
    return false
  }
}

/** 놓는 순간의 마우스 속도 → 던지기 초속. trail: [초, 모델 좌표] */
export function throwVelocity(trail: [number, Point][]): Vector {
  if (trail.length < 2) return { dx: 0, dy: 0 }
  const [t0, p0] = trail[0]
  const [t1, p1] = trail[trail.length - 1]
  const dt = t1 - t0
  if (dt <= 0.01) return { dx: 0, dy: 0 }
  let v = { dx: (p1.x - p0.x) / dt, dy: (p1.y - p0.y) / dt }
  const speed = Math.hypot(v.dx, v.dy)
  if (speed < 150) return { dx: 0, dy: 0 } // 살살 놓으면 그냥 떨어진다
  const cap = 1800
  if (speed > cap) v = { dx: (v.dx * cap) / speed, dy: (v.dy * cap) / speed }
  return v
}

/** 동작별 루프 fps (가만히 있을 땐 낮춰 CPU 절약) */
export function loopFPS(action: string, maxFPS = 60): number {
  switch (action) {
    case 'fall':
    case 'dragged':
      return maxFPS
    case 'idle':
      return Math.min(maxFPS, 12)
    case 'sleep':
      return Math.min(maxFPS, 6)
    default:
      return Math.min(maxFPS, 30)
  }
}
