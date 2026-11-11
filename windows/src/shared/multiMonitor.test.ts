// 높이가 다른 모니터 두 대 사이 오가기 (맥 Tests/MultiMonitorTests.swift 대응)
// 배치 예: 노트북 화면 오른쪽, 큰 모니터가 왼쪽에 바닥 764 높이로 붙음 (y 위로 증가 좌표)
import { describe, expect, it } from 'vitest'
import { PetBrain, defaultBrainConfig } from './brain'
import type { Rect } from './geometry'
import { PetPhysics } from './physics'
import { ScreenLayout, Terrain, type WindowBox } from './terrain'

const pet = { width: 80, height: 80 }
const laptop: Rect = { x: 0, y: 0, width: 1800, height: 1130 }
const big: Rect = { x: -1920, y: 764, width: 1920, height: 1080 }
const layout = new ScreenLayout([laptop, big])
const terrain = (windows: WindowBox[] = [], size = pet) => new Terrain(layout, windows, size)

function land(p: PetPhysics, t: Terrain) {
  for (let k = 0; k < 3000 && !p.fall(1 / 60, t); k++);
}

describe('모니터 여러 대', () => {
  it('턱(옆 모니터 바닥이 더 높음)은 기어올라 꼭대기에서 폴짝 넘어간다', () => {
    expect(layout.stepNeighbor(0, 'left', 0, 80)).toBe(1)
    expect(layout.stepNeighbor(0, 'right', 0, 80)).toBeUndefined()
    expect(layout.stepNeighbor(0, 'left', 0, 400)).toBeUndefined() // 매달리면 머리가 잘리는 높이
    const t = terrain()
    const p = new PetPhysics({ x: 10, y: 0 }, pet)
    const r = p.walk('left', 50, 0.5, t)
    expect(r.type).toBe('hitWall')
    if (r.type !== 'hitWall') return
    expect(r.wall.leadsToScreen).toBe(true)
    expect(r.wall.top).toBe(764)
    let c = p.climb(r.wall, 60, 1 / 30, t, Infinity)
    for (let k = 0; k < 2000 && c.type === 'climbing'; k++) c = p.climb(r.wall, 60, 1 / 30, t, Infinity)
    expect(c.type).toBe('overStep')
    p.prepareFall(t, p.screenHop('left'))
    land(p, t)
    expect(p.origin.y).toBe(764)
    expect(p.origin.x + pet.width).toBeLessThanOrEqual(0)
  })

  it('높은 모니터 → 낮은 모니터: 경계에 멈췄다가 폴짝, 몸 전체가 낮은 바닥에 착지', () => {
    const t = terrain()
    const p = new PetPhysics({ x: -100, y: 764 }, pet)
    expect(p.walk('right', 50, 1, t).type).toBe('reachedScreenEdge')
    expect(p.origin.x).toBe(-80)
    p.prepareFall(t, p.screenHop('right'))
    land(p, t)
    expect(p.origin.y).toBe(0)
    expect(p.origin.x).toBeGreaterThanOrEqual(0)
    // 큰 펫도
    const huge = { width: 160, height: 160 }
    const q = new PetPhysics({ x: -160, y: 764 }, huge)
    const th = terrain([], huge)
    q.prepareFall(th, q.screenHop('right'))
    land(q, th)
    expect(q.origin.y).toBe(0)
    expect(q.origin.x).toBeGreaterThanOrEqual(0)
  })

  it('옆 모니터 끝에 붙은 창(최대화 창)이 있어도 경계에서 벽으로 타지 않고 건너뛴다', () => {
    const t = terrain([{ id: 1, frame: { x: 0, y: 70, width: 1800, height: 1060 } }])
    const p = new PetPhysics({ x: -100, y: 764 }, pet)
    expect(p.walk('right', 50, 1, t).type).toBe('reachedScreenEdge')
    expect(t.nearestWallDirection(-100, 764)).not.toBe('right')
    p.prepareFall(t, p.screenHop('right'))
    land(p, t)
    expect(p.origin.y).toBe(0)
    expect(p.walk('right', 50, 0.5, t).type).toBe('moved') // 이미 창 앞에 겹쳐 있으니 벽 아님
  })

  it('낮게 던지면 큰 모니터 아래 빈 공간은 벽 → 순간이동 없이 노트북 쪽에 착지', () => {
    const t = terrain()
    const p = new PetPhysics({ x: 200, y: 300 }, pet)
    p.prepareFall(t, { dx: -1500, dy: 0 })
    let top = p.origin.y
    for (let k = 0; k < 3000 && !p.fall(1 / 60, t); k++) {
      top = Math.max(top, p.origin.y)
      expect(p.origin.x).toBeGreaterThanOrEqual(0)
    }
    expect(p.origin.y).toBe(0)
    expect(top).toBeLessThanOrEqual(300)
  })

  it('두뇌: 경계에서 넘어가거나(70%) 돌아선다', () => {
    const rng = () => 0.5
    const walking = (chance: number) => {
      const b = new PetBrain({ ...defaultBrainConfig, crossScreenChance: chance })
      b.handle({ type: 'chase', direction: 'right' }, rng) // 걷기로
      return b
    }
    const a = walking(1)
    a.handle({ type: 'hitStep' }, rng)
    expect(a.action).toBe('climb')
    const h = walking(1)
    h.handle({ type: 'reachedScreenEdge' }, rng)
    expect(h.action).toBe('fall')
    const n = walking(0)
    n.handle({ type: 'reachedScreenEdge' }, rng)
    expect(n.action).toBe('walk')
    expect(n.direction).toBe('left')
  })
})
