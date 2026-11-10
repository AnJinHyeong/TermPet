// Phase 1용 간단한 걷기 두뇌: 가만히 있다가 → 좌우로 걷다가 → 화면 끝에서 돌아서기.
// (맥 앱의 PetBrain·PetPhysics 전체 이식은 Phase 2. 지금은 바닥 한 줄만 걷는다)
// 순수 함수: 상태 + 시간 → 새 상태. React의 reducer처럼 생각하면 된다.

export type Direction = 'left' | 'right'

export interface WalkerState {
  action: 'idle' | 'walk'
  x: number // 펫 창 왼쪽 x (px)
  direction: Direction
  /** 지금 동작을 얼마나 더 할지 (초) */
  remaining: number
  /** 동작에 들어갈 때 뽑은 난수 → 포즈가 여러 개면 그중 하나 */
  variant: number
}

export interface Bounds {
  minX: number
  maxX: number // 펫 창 왼쪽 x가 갈 수 있는 최댓값 (화면 오른쪽 끝 - 펫 폭)
}

export type Random = () => number // 0 ≤ r < 1

const between = (rng: Random, a: number, b: number) => a + (b - a) * rng()

export function initialWalker(x: number, rng: Random): WalkerState {
  return { action: 'idle', x, direction: rng() < 0.5 ? 'left' : 'right', remaining: between(rng, 1, 3), variant: Math.floor(rng() * 1000) }
}

export function stepWalker(s: WalkerState, dt: number, speed: number, bounds: Bounds, rng: Random): WalkerState {
  let next = { ...s, remaining: s.remaining - dt }
  if (next.action === 'walk') {
    const dx = (next.direction === 'right' ? 1 : -1) * speed * dt
    next.x = Math.min(bounds.maxX, Math.max(bounds.minX, next.x + dx))
    // 화면 끝에 닿으면 돌아서기
    if (next.x <= bounds.minX) next.direction = 'right'
    else if (next.x >= bounds.maxX) next.direction = 'left'
  }
  if (next.remaining <= 0) {
    next =
      next.action === 'walk'
        ? { ...next, action: 'idle', remaining: between(rng, 2, 6), variant: Math.floor(rng() * 1000) }
        : {
            ...next,
            action: 'walk',
            direction: rng() < 0.5 ? 'left' : 'right',
            remaining: between(rng, 2, 6),
            variant: Math.floor(rng() * 1000),
          }
  }
  return next
}
