import { describe, expect, it } from 'vitest'
import { stepWalker, type WalkerState } from './walker'

const bounds = { minX: 0, maxX: 1000 }
const fixed = (v: number) => () => v

describe('walker', () => {
  it('걸으면 속도만큼 이동', () => {
    const s: WalkerState = { action: 'walk', x: 500, direction: 'right', remaining: 5, variant: 0 }
    expect(stepWalker(s, 0.5, 40, bounds, fixed(0.3)).x).toBe(520)
    expect(stepWalker({ ...s, direction: 'left' }, 0.5, 40, bounds, fixed(0.3)).x).toBe(480)
  })

  it('화면 끝에서 멈추고 돌아선다', () => {
    const s: WalkerState = { action: 'walk', x: 995, direction: 'right', remaining: 5, variant: 0 }
    const n = stepWalker(s, 1, 40, bounds, fixed(0.3))
    expect(n.x).toBe(1000)
    expect(n.direction).toBe('left')
  })

  it('시간이 다 되면 걷기 ↔ 가만히', () => {
    const walking: WalkerState = { action: 'walk', x: 500, direction: 'right', remaining: 0.1, variant: 0 }
    const idle = stepWalker(walking, 0.2, 40, bounds, fixed(0.3))
    expect(idle.action).toBe('idle')
    expect(idle.remaining).toBeGreaterThanOrEqual(2)
    const again = stepWalker({ ...idle, remaining: 0.1 }, 0.2, 40, bounds, fixed(0.7))
    expect(again.action).toBe('walk')
    expect(again.direction).toBe('right')
  })

  it('가만히 있을 땐 움직이지 않는다', () => {
    const s: WalkerState = { action: 'idle', x: 300, direction: 'right', remaining: 5, variant: 0 }
    expect(stepWalker(s, 1, 40, bounds, fixed(0.5)).x).toBe(300)
  })
})
