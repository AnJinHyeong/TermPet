// 장난꾸러기 모드 테스트 (맥 Tests/MischiefTests.swift 대응)
import { describe, expect, it } from 'vitest'
import { PetBrain } from './brain'
import { animationFor, fallbacks, parseStateKey, type Animation } from './characterPack'
import type { Rect, Vector } from './geometry'
import { defaultMischiefConfig, Mischief, PointerThrow, userMove, type MischiefInput } from './mischief'
import { PetPhysics } from './physics'
import { ScreenLayout, Terrain } from './terrain'

const dt = 1 / 30
const pet: Rect = { x: 500, y: 0, width: 80, height: 80 }

function input(cursor: { x: number; y: number }, patch: Partial<MischiefInput> = {}): MischiefInput {
  return { petFrame: pet, cursor, facing: 'right', canPlay: true, mouseDown: false, grounded: true, ...patch }
}

/** 켜자마자 바로 쫓는 장난꾸러기 */
const eager = () => new Mischief({ ...defaultMischiefConfig, startDelay: 0 })

function seeded(seed = 1) {
  let s = seed
  return () => {
    s = (s * 16807) % 2147483647
    return (s - 1) / 2147483646
  }
}

/** 몸을 날린 포물선을 실제 물리처럼 따라가며 몸 중심이 포인터에 가장 가까웠던 거리와 가장 높이 오른 몸 윗면 */
function fly(v: Vector, frame: Rect, target: { x: number; y: number }) {
  const p = new PetPhysics({ x: frame.x, y: frame.y }, { width: frame.width, height: frame.height })
  p.velocity = { ...v }
  let closest = Infinity
  let top = frame.y + frame.height
  for (let k = 0; k < 90; k++) {
    p.velocity.dy -= 1800 / 60
    p.velocity.dx *= Math.pow(0.6, 1 / 60)
    p.origin.x += p.velocity.dx / 60
    p.origin.y += p.velocity.dy / 60
    closest = Math.min(closest, Math.hypot(p.origin.x + frame.width / 2 - target.x, p.origin.y + frame.height / 2 - target.y))
    top = Math.max(top, p.origin.y + frame.height)
  }
  return { closest, top }
}

describe('Mischief', () => {
  it('닿지 않는 자리는 몇 번 뛰어 보고 포기, 포인터가 움직이면 다시 쫓는다', () => {
    const m = eager()
    const high = { x: 545, y: 900 } // 바로 위 너무 높고 탈 벽도 없음
    let jumps = 0
    let gaveUp = false
    for (let i = 0; i < 30 * 30 && !gaveUp; i++) {
      const cmd = m.tick(dt, input(high))
      if (cmd.type === 'jump') jumps++
      if (cmd.type === 'stopChase') gaveUp = true
    }
    expect(gaveUp).toBe(true)
    expect(jumps).toBe(m.config.maxAttempts)
    expect(m.phase).toBe('ready')
    // 포인터가 그 자리에 있는 동안은 다시 안 덤빈다 (쉬는 시간이 지나도)
    for (let i = 0; i < 30 * 20; i++) expect(m.tick(dt, input({ x: 550, y: 905 }))).toEqual({ type: 'none' })
    expect(m.tick(dt, input({ x: 900, y: 40 }))).toEqual({ type: 'chase', direction: 'right' })
  })

  it('포인터가 계속 움직이면 포기하지 않고, 벽만 오르내리는 것도 센다', () => {
    const moving = eager()
    let jumps = 0
    for (let i = 0; i < 30 * 30; i++) {
      const cmd = moving.tick(dt, input({ x: 545, y: 200 + (jumps % 2) * 100 })) // 점프할 때마다 다른 자리로 (놀아 주는 중)
      expect(cmd.type).not.toBe('stopChase')
      if (cmd.type === 'jump') jumps++
    }
    expect(jumps).toBeGreaterThan(moving.config.maxAttempts)

    const m = eager()
    const far = { x: 545, y: 900 }
    for (let i = 0; i < m.config.maxAttempts; i++) {
      expect(m.tick(dt, input(far, { wallDirection: 'left' }))).toEqual({ type: 'chase', direction: 'left' })
      m.didStartClimbing()
      expect(m.phase).toBe('chasing')
    }
    m.tick(dt, input(far, { wallDirection: 'left' }))
    m.didStartClimbing()
    expect(m.phase).toBe('ready')
    expect(m.gaveUpAt).toBeDefined()
    m.reset()
    expect(m.gaveUpAt).toBeUndefined()
  })

  it('포인터가 어디 있든 쫓아간다', () => {
    const m = eager()
    expect(m.tick(dt, input({ x: 1500, y: 40 }))).toEqual({ type: 'chase', direction: 'right' })
    expect(m.tick(dt, input({ x: 100, y: 40 }))).toEqual({ type: 'chase', direction: 'left' })
  })

  it('잡으면 물고 흔들다 던지고, 쉬었다가 다시 쫓는다', () => {
    const m = eager()
    m.tick(dt, input({ x: 700, y: 40 }))
    expect(m.tick(dt, input({ x: 560, y: 40 }))).toEqual({ type: 'startBite' })
    const hold = m.tick(dt, input({ x: 560, y: 41 }))
    expect(hold.type).toBe('holdPointer')
    let cmd = hold
    for (let k = 0; k < 60 && cmd.type === 'holdPointer'; k++) cmd = m.tick(dt, input({ x: 560, y: 41 }))
    expect(cmd).toEqual({ type: 'throwPointer' })
    m.finishThrow()
    expect(m.phase).toBe('ready')
  })

  it('물고 있을 때 클릭하면 놓아준다 / 버튼 누르는 중엔 안 문다', () => {
    const m = eager()
    m.tick(dt, input({ x: 700, y: 40 }))
    expect(m.tick(dt, input({ x: 560, y: 40 }, { mouseDown: true })).type).not.toBe('startBite')
    expect(m.tick(dt, input({ x: 560, y: 40 }))).toEqual({ type: 'startBite' })
    expect(m.tick(dt, input({ x: 560, y: 40 }, { mouseDown: true }))).toEqual({ type: 'release' })
  })

  it('공중에서 물면 문 채로 떨어지고, 땅에 닿은 뒤에 던진다', () => {
    const m = eager()
    const c = { x: 540, y: 40 }
    m.tick(dt, input({ x: 700, y: 40 }))
    expect(m.tick(dt, input(c, { grounded: false }))).toEqual({ type: 'startBite' })
    for (let k = 0; k < 90; k++) expect(m.tick(dt, input(c, { grounded: false })).type).toBe('holdPointer')
    expect(m.tick(dt, input(c))).toEqual({ type: 'throwPointer' })
  })

  it('머리 위 닿는 거리면 잠깐 웅크렸다 점프해서 닿는다', () => {
    const m = eager()
    const target = { x: 545, y: 250 }
    let cmd = m.tick(dt, input(target))
    let ticks = 1
    while (cmd.type === 'none' && ticks < 30) {
      cmd = m.tick(dt, input(target))
      ticks++
    }
    expect(cmd.type).toBe('jump')
    expect(ticks * dt).toBeGreaterThan(0.2)
    if (cmd.type === 'jump') expect(fly(cmd.velocity, pet, target).closest).toBeLessThan(30)
    expect(Mischief.leapVelocity(pet, { x: 545, y: 900 })).toBeUndefined()
  })

  it('너무 높으면 포인터에 가까운 벽으로 달려가 타고 오른 뒤, 포인터 높이에서 멀리 몸을 날린다', () => {
    const m = eager()
    const far = { x: 800, y: 700 }
    expect(m.tick(dt, input(far, { wallDirection: 'left' }))).toEqual({ type: 'chase', direction: 'left' })
    m.didStartClimbing()
    expect(m.tick(dt, input(far, { petFrame: { x: 0, y: 200, width: 80, height: 80 }, grounded: false, climbingSide: 'left' }))).toEqual({ type: 'none' })
    const level: Rect = { x: 0, y: 650, width: 80, height: 80 }
    const cmd = m.tick(dt, input(far, { petFrame: level, grounded: false, climbingSide: 'left' }))
    expect(cmd.type).toBe('jump')
    if (cmd.type === 'jump') expect(fly(cmd.velocity, level, far).closest).toBeLessThan(30)
    // 포인터가 벽 너머면 계속 오른다
    expect(m.tick(dt, input({ x: -100, y: 700 }, { petFrame: level, grounded: false, climbingSide: 'left' }))).toEqual({ type: 'none' })
  })

  it('천장 가까이선 머리를 박지 않게 낮게 날아도 닿는다', () => {
    const onWall: Rect = { x: 0, y: 700, width: 80, height: 80 }
    const target = { x: 700, y: 740 }
    const v = Mischief.wallLeap(onWall, target, 40)!
    const f = fly(v, onWall, target)
    expect(f.closest).toBeLessThan(30)
    expect(f.top).toBeLessThanOrEqual(onWall.y + onWall.height + 41)
    expect(Mischief.wallLeap(onWall, { x: 1300, y: 740 })).toBeUndefined()
  })
})

describe('PointerThrow', () => {
  const one: Rect[] = [{ x: 0, y: -1169, width: 1800, height: 1169 }]

  it('공간이 모자란 쪽이면 반대쪽으로, 넉넉하면 방향·시간·세기가 랜덤', () => {
    const rng = seeded(3)
    const dirs = new Set<string>()
    const durations = new Set<number>()
    for (let k = 0; k < 40; k++) {
      expect(PointerThrow.toss({ x: 1750, y: -900 }, one, rng).direction).toBe('left')
      expect(PointerThrow.toss({ x: 50, y: -900 }, one, rng).direction).toBe('right')
      const mid = PointerThrow.toss({ x: 900, y: -900 }, one, rng)
      dirs.add(mid.direction)
      durations.add(mid.duration)
    }
    expect(dirs.size).toBe(2)
    expect(durations.size).toBeGreaterThan(10)
  })

  it('높이도 랜덤: 위쪽 공간이 넉넉하면 높이 솟구치고, 천장은 안 넘는다', () => {
    const rng = seeded(5)
    const apexes: number[] = []
    for (let k = 0; k < 60; k++) {
      const p = PointerThrow.toss({ x: 900, y: -1069 }, one, rng) // 바닥 근처 (위로 1069)
      const apex = (p.velocity.dy * p.velocity.dy) / (2 * p.gravity)
      expect(apex).toBeLessThanOrEqual(1069 * 0.9 + 1)
      expect(p.duration).toBeGreaterThan(p.velocity.dy / p.gravity)
      apexes.push(apex)
      for (let t = 0; t <= p.duration; t += 0.05) {
        const q = p.position(t)
        expect(one.some((s) => q.x >= s.x && q.x < s.x + s.width && q.y >= s.y && q.y < s.y + s.height)).toBe(true)
      }
    }
    expect(Math.max(...apexes)).toBeGreaterThan(600)
    expect(Math.min(...apexes)).toBeLessThan(300)
  })

  it('양쪽 다 좁으면 남은 공간 안에 떨어지게 살살 / 옆 모니터로 이어지면 그쪽 공간도 센다', () => {
    const narrow: Rect[] = [{ x: 0, y: -1000, width: 600, height: 1000 }]
    const soft = PointerThrow.toss({ x: 300, y: -500 }, narrow, seeded(7))
    expect(Math.abs(soft.velocity.dx) * soft.duration).toBeLessThanOrEqual(300)
    const two: Rect[] = [...one, { x: 1800, y: -1080, width: 1920, height: 1080 }]
    expect(PointerThrow.room({ x: 1750, y: -500 }, 'right', two)).toBe(1970)
  })

  it('날아가는 중 마우스를 움직이면 그만큼 옮겨진 길로', () => {
    const p = new PointerThrow({ x: 500, y: -500 }, { dx: 100, dy: 0 }, [{ x: 0, y: -1000, width: 2000, height: 1000 }])
    p.gravity = 0
    p.offset = { dx: -200, dy: 50 }
    expect(p.position(0.5)).toEqual({ x: 350, y: -450 })
    expect(userMove({ x: 10, y: 10 }, { x: 11, y: 10 }, 2)).toEqual({ dx: 0, dy: 0 })
    expect(userMove({ x: 10, y: 10 }, { x: 30, y: 5 }, 2)).toEqual({ dx: 20, dy: -5 })
    expect(userMove(undefined, { x: 30, y: 5 })).toEqual({ dx: 0, dy: 0 })
  })
})

describe('장난꾸러기 연결부', () => {
  it('물기·던지기 그림이 없으면 화남·신남으로', () => {
    expect(fallbacks('bite')).toEqual(['bite', 'angry', 'idle'])
    expect(fallbacks('throw')).toEqual(['throw', 'happy', 'idle'])
    expect(parseStateKey('throw')).toEqual(['throw', 1])
    const angry: Animation = { file: 'angry.png', frames: 1, fps: 8, loop: true, facing: 'front' }
    expect(animationFor({ angry: [angry] }, 'bite')).toBe(angry)
  })

  it('두뇌: 쫓는 동안 계속 걷고, 벽에선 바로 오르고, 그쪽을 본다', () => {
    const b = new PetBrain()
    const rng = seeded()
    b.handle({ type: 'chase', direction: 'left' }, rng)
    expect(b.action).toBe('walk')
    expect(b.direction).toBe('left')
    b.tick(5, rng)
    b.handle({ type: 'chase', direction: 'left' }, rng)
    b.tick(0.5, rng)
    expect(b.action).toBe('walk')
    b.handle({ type: 'climbNow' }, rng)
    expect(b.action).toBe('climb')
    b.handle({ type: 'face', direction: 'right' }, rng)
    expect(b.direction).toBe('right')
  })

  it('지형: 포인터에 가장 가까운 벽 쪽', () => {
    const t = new Terrain(new ScreenLayout([{ x: 0, y: 0, width: 1600, height: 1000 }]), [], { width: 80, height: 80 })
    expect(t.nearestWallDirection(300, 0, 1400)).toBe('right')
    expect(t.nearestWallDirection(300, 0)).toBe('left')
    const withWindow = new Terrain(new ScreenLayout([{ x: 0, y: 0, width: 1600, height: 1000 }]), [{ id: 1, frame: { x: 900, y: 0, width: 300, height: 500 } }], {
      width: 80,
      height: 80,
    })
    expect(withWindow.nearestWallDirection(700, 0)).toBe('right')
  })
})
