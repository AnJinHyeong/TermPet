// 두뇌·물리·지형 테스트 (맥 PetBrainTests / PetPhysicsTests / TerrainTests 대응)
import { describe, expect, it } from 'vitest'
import { PetBrain } from './brain'
import { petOriginY, petScreenTop, toModelRect } from './geometry'
import { PetPhysics, throwVelocity } from './physics'
import { hasFullscreenWindow, ScreenLayout, Terrain } from './terrain'

/** 시드 고정 난수 (테스트 재현용) */
function seeded(seed = 1) {
  let s = seed
  return () => {
    s = (s * 16807) % 2147483647
    return (s - 1) / 2147483646
  }
}
const always = (v: number) => () => v

describe('PetBrain', () => {
  it('idle 시간이 지나면 걷기, 걷기 시간이 지나면 다시 idle', () => {
    const b = new PetBrain()
    const rng = seeded()
    b.tick(7, rng)
    expect(b.action).toBe('walk')
    b.tick(9, rng)
    expect(b.action).toBe('idle')
  })

  it('오래 아무 일 없으면 잠든다, 클릭하면 깬다', () => {
    const b = new PetBrain()
    const rng = seeded()
    for (let i = 0; i < 700; i++) b.tick(1, rng)
    expect(b.action).toBe('sleep')
    b.handle({ type: 'clicked' }, rng)
    expect(b.action).toBe('idle')
  })

  it('반응은 시간이 지나면 idle 로, 잡혀 있을 땐 반응 무시', () => {
    const b = new PetBrain()
    b.handle({ type: 'react', action: 'happy', duration: 2 }, seeded())
    expect(b.action).toBe('happy')
    b.tick(2.1, seeded())
    expect(b.action).toBe('idle')
    b.handle({ type: 'dragStarted' }, seeded())
    b.handle({ type: 'react', action: 'angry' }, seeded())
    expect(b.action).toBe('dragged')
  })

  it('벽에 막히면 확률대로 기어오르거나 돌아선다', () => {
    const climb = new PetBrain()
    climb.tick(7, seeded())
    climb.handle({ type: 'hitWall', window: true }, always(0.1))
    expect(climb.action).toBe('climb')

    const turn = new PetBrain()
    turn.tick(7, seeded())
    const dir = turn.direction
    turn.handle({ type: 'hitWall', window: true }, always(0.9))
    expect(turn.action).toBe('walk')
    expect(turn.direction).not.toBe(dir)
  })

  it('벽에서 손을 놓으면 반대 방향으로 떨어진다', () => {
    const b = new PetBrain()
    b.tick(7, seeded())
    b.handle({ type: 'hitWall', window: false }, always(0))
    const dir = b.direction
    b.handle({ type: 'letGo' }, seeded())
    expect(b.action).toBe('fall')
    expect(b.direction).not.toBe(dir)
  })
})

// 화면 하나: 1000x800, 바닥 y=0 (모델 좌표, y 위로)
const layout = new ScreenLayout([{ x: 0, y: 0, width: 1000, height: 800 }])
const size = { width: 80, height: 80 }

describe('좌표 변환', () => {
  it('Electron 화면 좌표 ↔ 모델 좌표', () => {
    expect(toModelRect({ x: 10, y: 100, width: 50, height: 20 })).toEqual({ x: 10, y: -120, width: 50, height: 20 })
    const top = 1000 - 80
    expect(petScreenTop(petOriginY(top, 80), 80)).toBe(top)
  })
})

describe('PetPhysics 걷기', () => {
  it('화면 끝에서 벽에 막힌다', () => {
    const p = new PetPhysics({ x: 915, y: 0 }, size)
    const r = p.walk('right', 100, 0.1, new Terrain(layout, [], size))
    expect(r.type).toBe('hitWall')
    expect(p.origin.x).toBe(920)
  })

  it('옆 화면이 같은 높이로 붙어 있으면 넘어간다', () => {
    const two = new ScreenLayout([
      { x: 0, y: 0, width: 1000, height: 800 },
      { x: 1000, y: 0, width: 1000, height: 800 },
    ])
    const p = new PetPhysics({ x: 915, y: 0 }, size)
    expect(p.walk('right', 100, 0.1, new Terrain(two, [], size)).type).toBe('moved')
    expect(p.origin.x).toBeCloseTo(925)
  })

  it('창 옆면에 부딪히면 벽, 낮은 턱은 그냥 올라선다', () => {
    const tall = new Terrain(layout, [{ id: 1, frame: { x: 300, y: 0, width: 300, height: 400 } }], size)
    const p = new PetPhysics({ x: 215, y: 0 }, size)
    const r = p.walk('right', 100, 0.1, tall)
    expect(r.type).toBe('hitWall')
    if (r.type === 'hitWall') expect(r.wall.windowID).toBe(1)

    const low = new Terrain(layout, [{ id: 2, frame: { x: 300, y: 0, width: 300, height: 10 } }], size)
    const q = new PetPhysics({ x: 215, y: 0 }, size)
    expect(q.walk('right', 100, 0.1, low).type).toBe('moved')
    expect(q.standingOn).toBe(2)
    expect(q.origin.y).toBe(10)
  })

  it('창 위에서 끝에 닿으면 reachedEdge', () => {
    const t = new Terrain(layout, [{ id: 1, frame: { x: 300, y: 100, width: 300, height: 200 } }], size)
    const p = new PetPhysics({ x: 555, y: 300 }, size)
    p.standingOn = 1
    expect(p.walk('right', 100, 0.1, t).type).toBe('reachedEdge')
  })
})

describe('PetPhysics 낙하', () => {
  it('창 위로 떨어지면 그 창에 선다', () => {
    const t = new Terrain(layout, [{ id: 7, frame: { x: 200, y: 100, width: 400, height: 200 } }], size)
    const p = new PetPhysics({ x: 300, y: 600 }, size)
    p.prepareFall(t)
    let landed = false
    for (let i = 0; i < 200 && !landed; i++) landed = p.fall(1 / 60, t)
    expect(landed).toBe(true)
    expect(p.standingOn).toBe(7)
    expect(p.origin.y).toBe(300)
  })

  it('창 밖이면 화면 바닥까지', () => {
    const t = new Terrain(layout, [], size)
    const p = new PetPhysics({ x: 300, y: 500 }, size)
    p.prepareFall(t)
    let landed = false
    for (let i = 0; i < 300 && !landed; i++) landed = p.fall(1 / 60, t)
    expect(landed).toBe(true)
    expect(p.standingOn).toBeNull()
    expect(p.origin.y).toBe(0)
  })

  it('최대 낙하 속도를 넘지 않는다', () => {
    const t = new Terrain(new ScreenLayout([{ x: 0, y: -100000, width: 1000, height: 200000 }]), [], size)
    const p = new PetPhysics({ x: 300, y: 50000 }, size)
    for (let i = 0; i < 120; i++) p.fall(1 / 60, t)
    expect(p.velocity.dy).toBe(-700)
  })
})

describe('PetPhysics 벽 오르기', () => {
  it('창 벽을 다 오르면 창 위에 올라선다', () => {
    const t = new Terrain(layout, [{ id: 3, frame: { x: 300, y: 0, width: 300, height: 200 } }], size)
    const wall = t.windowWall(215, 225, 0, 'right')!
    const p = new PetPhysics({ x: 220, y: 0 }, size)
    let r = p.climb(wall, 100, 0.1, t, Infinity)
    for (let i = 0; i < 50 && r.type === 'climbing'; i++) r = p.climb(wall, 100, 0.1, t, Infinity)
    expect(r).toEqual({ type: 'reachedTop', windowID: 3 })
    expect(p.origin.y).toBe(200)
    expect(p.standingOn).toBe(3)
  })
})

describe('Terrain', () => {
  it('앞 창이 덮은 부분은 선반이 아니다', () => {
    const t = new Terrain(
      layout,
      [
        { id: 1, frame: { x: 400, y: 100, width: 200, height: 300 } }, // 앞
        { id: 2, frame: { x: 100, y: 100, width: 700, height: 200 } }, // 뒤 (윗변 y=300 을 앞 창이 가로지름)
      ],
      size,
    )
    const back = t.ledges.filter((l) => l.windowID === 2)
    expect(back.map((l) => [l.minX, l.maxX])).toEqual([
      [100, 400],
      [600, 800],
    ])
  })

  it('머리 위 공간이 없는 창(최대화)은 선반이 없다', () => {
    const t = new Terrain(layout, [{ id: 1, frame: { x: 0, y: 0, width: 1000, height: 790 } }], size)
    expect(t.ledges).toEqual([])
  })

  it('전체 화면 창 판정', () => {
    const screen = { x: 0, y: -1080, width: 1920, height: 1080 }
    expect(hasFullscreenWindow([{ id: 1, frame: { ...screen } }], screen)).toBe(true)
    expect(hasFullscreenWindow([{ id: 1, frame: { x: 0, y: -1032, width: 1920, height: 1032 } }], screen)).toBe(false) // 최대화
  })
})

describe('throwVelocity', () => {
  it('살살 놓으면 0, 세게 던지면 최대 1800', () => {
    expect(throwVelocity([[0, { x: 0, y: 0 }], [0.1, { x: 5, y: 0 }]])).toEqual({ dx: 0, dy: 0 })
    const v = throwVelocity([[0, { x: 0, y: 0 }], [0.05, { x: 500, y: 0 }]])
    expect(Math.hypot(v.dx, v.dy)).toBeCloseTo(1800)
  })
})
