// 캐릭터 팩(character.json) 해석 — 맥 앱 Sources/Character/CharacterPack.swift 와 같은 규칙.
// UI·Electron 비의존 순수 로직이라 main(Node)·renderer(React) 양쪽에서 쓰고 Vitest로 테스트한다.

export const ACTIONS = ['idle', 'walk', 'talk', 'happy', 'angry', 'ask', 'sleep', 'dragged', 'fall', 'climb'] as const
export type PetAction = (typeof ACTIONS)[number]

/** 스프라이트가 바라보는 방향. front = 좌우 반전 안 함 */
export type Facing = 'right' | 'left' | 'front'

export interface StateSpec {
  file: string
  /** 생략하면 이미지 너비 / frameWidth */
  frames?: number
  fps?: number
  loop?: boolean
  facing?: Facing
}

export interface CharacterPack {
  id: string
  name?: string
  order?: number
  frameWidth: number
  frameHeight: number
  scale?: number
  walkSpeed?: number
  pixelArt?: boolean
  facing?: Facing
  /** 키: 동작 이름(idle), 같은 동작의 다른 포즈는 idle.2, idle.3 … */
  states: Record<string, StateSpec>
  messages?: { done?: string[]; error?: string[]; ask?: string[] }
}

/** 화면에 그릴 한 포즈 (renderer로 넘기는 값) */
export interface Animation {
  file: string
  frames: number
  fps: number
  loop: boolean
  facing: Facing
}

export class PackError extends Error {}

/** 상태 키 → [동작, 변형 번호]. "idle" → ["idle", 1], "walk.2" → ["walk", 2]. 모르는 이름은 null */
export function parseStateKey(key: string): [PetAction, number] | null {
  const [name, num] = key.split('.', 2)
  if (!(ACTIONS as readonly string[]).includes(name)) return null
  if (num === undefined) return [name as PetAction, 1]
  const n = Number(num)
  return Number.isInteger(n) && n >= 1 ? [name as PetAction, n] : null
}

/** JSON 텍스트 → 검증된 팩 (zod 없이 손으로 검사: 맥 앱의 validate()와 같은 조건) */
export function parsePack(text: string): CharacterPack {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    throw new PackError('character.json 을 읽지 못했어요 (JSON 형식 오류)')
  }
  const p = raw as CharacterPack
  if (typeof p !== 'object' || p === null) throw new PackError('character.json 형식이 아니에요')
  if (typeof p.id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(p.id)) throw new PackError('id는 영문/숫자/-/_ 만 사용 가능 (1~64자)')
  const okSize = (n: unknown) => Number.isInteger(n) && (n as number) >= 1 && (n as number) <= 1024
  if (!okSize(p.frameWidth) || !okSize(p.frameHeight)) throw new PackError('frameWidth/frameHeight는 1~1024')
  if (p.scale !== undefined && !(p.scale >= 0.1 && p.scale <= 8)) throw new PackError('scale은 0.1~8')
  if (typeof p.states !== 'object' || p.states === null || !p.states.idle) throw new PackError('states에 idle이 꼭 있어야 함')
  for (const spec of Object.values(p.states)) {
    if (typeof spec?.file !== 'string' || spec.file.includes('..') || spec.file.startsWith('/') || spec.file.includes('\\')) {
      throw new PackError(`파일 경로가 팩 폴더 밖을 가리킴: ${spec?.file}`)
    }
  }
  return p
}

/** 펫 창 크기(px). 너무 크면 512 이내로 줄인다 */
export function displaySize(pack: CharacterPack): { width: number; height: number } {
  const s = pack.scale ?? 1
  const w = pack.frameWidth * s
  const h = pack.frameHeight * s
  const shrink = Math.min(1, 512 / Math.max(w, h))
  return { width: Math.round(w * shrink), height: Math.round(h * shrink) }
}

/** 동작별 포즈 목록 (변형 번호 순). frames를 모르면 sheetWidth로 계산 */
export function animations(pack: CharacterPack, sheetWidths: Record<string, number> = {}): Partial<Record<PetAction, Animation[]>> {
  const numbered: Partial<Record<PetAction, [number, Animation][]>> = {}
  for (const [key, spec] of Object.entries(pack.states)) {
    const parsed = parseStateKey(key)
    if (!parsed) continue
    const [action, n] = parsed
    const available = sheetWidths[spec.file] ? Math.max(1, Math.floor(sheetWidths[spec.file] / pack.frameWidth)) : undefined
    const frames = Math.max(1, Math.min(spec.frames ?? available ?? 1, available ?? Infinity))
    const anim: Animation = {
      file: spec.file,
      frames,
      fps: spec.fps ?? 8,
      loop: spec.loop ?? true,
      facing: spec.facing ?? pack.facing ?? 'right',
    }
    ;(numbered[action] ??= []).push([n, anim])
  }
  const out: Partial<Record<PetAction, Animation[]>> = {}
  for (const [action, list] of Object.entries(numbered) as [PetAction, [number, Animation][]][]) {
    out[action] = list.sort((a, b) => a[0] - b[0]).map(([, anim]) => anim)
  }
  return out
}

/** 없는 동작을 무엇으로 대신할지 (벽 오르기 그림이 없으면 잡힌 그림 → 가만히) */
export function fallbacks(action: PetAction): PetAction[] {
  if (action === 'climb') return ['climb', 'dragged', 'idle']
  if (action === 'idle') return ['idle']
  return [action, 'idle']
}

/** 동작 + 변형 난수 → 보여줄 포즈 */
export function animationFor(anims: Partial<Record<PetAction, Animation[]>>, action: PetAction, variant = 0): Animation | null {
  for (const a of fallbacks(action)) {
    const list = anims[a]
    if (list && list.length > 0) return list[Math.abs(variant) % list.length]
  }
  return null
}

/** 상태 진입 후 elapsed초일 때 보여줄 프레임 번호 */
export function frameIndex(anim: Pick<Animation, 'frames' | 'fps' | 'loop'>, elapsed: number): number {
  if (anim.frames <= 1 || anim.fps <= 0 || elapsed <= 0) return 0
  const raw = Math.floor(elapsed * anim.fps)
  return anim.loop ? raw % anim.frames : Math.min(raw, anim.frames - 1)
}

/** 이동 방향에 맞게 좌우 반전할지. 그림이 front면 반전 안 함 */
export function shouldFlip(spriteFacing: Facing, moving: 'left' | 'right'): boolean {
  if (spriteFacing === 'front') return false
  return (moving === 'left') !== (spriteFacing === 'left')
}
