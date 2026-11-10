import { describe, expect, it } from 'vitest'
import { animationFor, animations, displaySize, frameIndex, PackError, parsePack, parseStateKey, shouldFlip } from './characterPack'

const pack = parsePack(JSON.stringify({
  id: 'kuri', name: '쿠리만쥬', frameWidth: 220, frameHeight: 220, scale: 0.42, facing: 'front',
  states: {
    idle: { file: 'idle.png', frames: 8, fps: 6 },
    'idle.2': { file: 'idle-2.png', fps: 6 },
    walk: { file: 'walk.png', frames: 8, fps: 10, facing: 'right' },
    'happy.3': { file: 'h3.png' },
    happy: { file: 'h1.png' },
    oops: { file: 'x.png' },
  },
}))

describe('parsePack', () => {
  it('맥 앱과 같은 검증 규칙', () => {
    expect(() => parsePack('{')).toThrow(PackError)
    expect(() => parsePack(JSON.stringify({ id: 'a b', frameWidth: 1, frameHeight: 1, states: { idle: { file: 'a' } } }))).toThrow(/id/)
    expect(() => parsePack(JSON.stringify({ id: 'a', frameWidth: 0, frameHeight: 1, states: { idle: { file: 'a' } } }))).toThrow(/frameWidth/)
    expect(() => parsePack(JSON.stringify({ id: 'a', frameWidth: 1, frameHeight: 1, states: { walk: { file: 'a' } } }))).toThrow(/idle/)
    expect(() => parsePack(JSON.stringify({ id: 'a', frameWidth: 1, frameHeight: 1, states: { idle: { file: '../evil.png' } } }))).toThrow(/밖/)
    expect(() => parsePack(JSON.stringify({ id: 'a', frameWidth: 1, frameHeight: 1, states: { idle: { file: '..\\evil.png' } } }))).toThrow(/밖/)
  })

  it('창 크기 = 프레임 × scale (512 상한)', () => {
    expect(displaySize(pack)).toEqual({ width: 92, height: 92 })
    expect(displaySize({ ...pack, scale: 4 })).toEqual({ width: 512, height: 512 })
  })
})

describe('상태 키와 포즈', () => {
  it('parseStateKey', () => {
    expect(parseStateKey('idle')).toEqual(['idle', 1])
    expect(parseStateKey('walk.2')).toEqual(['walk', 2])
    expect(parseStateKey('walk.0')).toBeNull()
    expect(parseStateKey('dance')).toBeNull()
  })

  it('변형 번호 순으로 정렬, 모르는 키는 무시, 프레임 수는 시트 폭으로 제한', () => {
    const a = animations(pack, { 'idle-2.png': 220 * 4, 'walk.png': 220 * 6 })
    expect(a.happy?.map((x) => x.file)).toEqual(['h1.png', 'h3.png'])
    expect(a.idle?.[1].frames).toBe(4)       // frames 생략 → 시트 폭 / frameWidth
    expect(a.walk?.[0].frames).toBe(6)       // 8 요청했지만 6장뿐
    expect(a.walk?.[0].facing).toBe('right') // 동작별 facing이 팩 facing보다 우선
    expect(a.idle?.[0].facing).toBe('front')
    expect(Object.keys(a)).not.toContain('oops')
  })

  it('없는 동작은 대체: climb → dragged → idle', () => {
    const a = animations(pack)
    expect(animationFor(a, 'climb')?.file).toBe('idle.png')
    expect(animationFor(a, 'sleep')?.file).toBe('idle.png')
    expect(animationFor(a, 'happy', 1)?.file).toBe('h3.png')
    expect(animationFor(a, 'happy', -3)?.file).toBe('h3.png')
  })

  it('프레임 번호 (반복/한 번)', () => {
    expect(frameIndex({ frames: 8, fps: 10, loop: true }, 0.95)).toBe(1)
    expect(frameIndex({ frames: 8, fps: 10, loop: false }, 5)).toBe(7)
    expect(frameIndex({ frames: 1, fps: 10, loop: true }, 5)).toBe(0)
  })

  it('걷는 방향으로 좌우 반전 (front는 그대로)', () => {
    expect(shouldFlip('right', 'left')).toBe(true)
    expect(shouldFlip('right', 'right')).toBe(false)
    expect(shouldFlip('left', 'left')).toBe(false)
    expect(shouldFlip('front', 'left')).toBe(false)
  })
})
