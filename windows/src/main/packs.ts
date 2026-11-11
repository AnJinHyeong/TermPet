// 친구 팩 목록 읽기 (Node 파일 시스템). 해석 규칙은 shared/characterPack.ts
// 위치: %APPDATA%\TermPet\Friends\<id>\character.json  (맥 앱과 같은 구조 → 같은 zip을 그대로 씀)
import { closeSync, existsSync, openSync, readdirSync, readFileSync, readSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { animations, displaySize, parsePack, type Animation, type CharacterPack, type PetAction } from '../shared/characterPack'

export interface LoadedPack {
  /** 메뉴·설정에 쓰는 고유 키 (friend.<id> / builtin) */
  key: string
  name: string
  folder: string
  pack: CharacterPack
  anims: Partial<Record<PetAction, Animation[]>>
  size: { width: number; height: number }
  /** 친구 고르기 타일에 쓸 대표 그림 (source.png 가 있으면 그것, 없으면 idle 첫 프레임) */
  thumbnail: string
}

/** PNG 파일 머리(IHDR)에서 가로 크기만 읽는다 — 이미지 라이브러리 없이 프레임 수 계산용 */
export function pngWidth(file: string): number | undefined {
  try {
    // 파일 전체가 아니라 앞 24바이트만 읽는다 (패널을 열 때마다 모든 그림을 통째로 읽지 않게)
    const head = Buffer.alloc(24)
    const fd = openSync(file, 'r')
    let n = 0
    try {
      n = readSync(fd, head, 0, 24, 0)
    } finally {
      closeSync(fd)
    }
    if (n < 24 || head.toString('ascii', 12, 16) !== 'IHDR') return undefined
    return head.readUInt32BE(16)
  } catch {
    return undefined
  }
}

export function loadPack(folder: string, key: string): LoadedPack {
  const pack = parsePack(readFileSync(join(folder, 'character.json'), 'utf8'))
  const widths: Record<string, number> = {}
  for (const spec of Object.values(pack.states)) {
    const w = pngWidth(join(folder, spec.file))
    if (w) widths[spec.file] = w
  }
  const thumbnail = existsSync(join(folder, 'source.png')) ? 'source.png' : pack.states.idle.file
  return { key, name: pack.name ?? pack.id, folder, pack, anims: animations(pack, widths), size: displaySize(pack), thumbnail }
}

/** Friends 폴더의 팩들 (order → 이름 순). 읽지 못한 팩은 건너뛰고 로그만 남긴다 */
export function loadFriends(friendsDir: string): LoadedPack[] {
  if (!existsSync(friendsDir)) return []
  const out: [number, LoadedPack][] = []
  for (const name of readdirSync(friendsDir)) {
    if (name.startsWith('.')) continue
    const folder = join(friendsDir, name)
    try {
      if (!statSync(folder).isDirectory()) continue
      const p = loadPack(folder, '')
      p.key = `friend.${p.pack.id}`
      out.push([p.pack.order ?? 999, p])
    } catch (e) {
      console.warn(`[TermPet] 팩을 건너뜀: ${folder}: ${(e as Error).message}`)
    }
  }
  return out.sort((a, b) => a[0] - b[0] || a[1].name.localeCompare(b[1].name)).map(([, p]) => p)
}
