// 친구 팩 가져오기 (맥 FriendPackImporter.swift): zip(또는 폴더) 안의 character.json 팩들을 모두 Friends 폴더에 설치.
// 더하기 — 기존 친구는 그대로 두고, 같은 id의 친구만 새 것으로 바꾼다. 팩을 무사히 찾은 뒤에만 Friends 폴더를 건드린다.
// 압축 풀기: 윈도우 10+ 기본 tar.exe (bsdtar 라 zip 도 푼다). 맥 개발 실행에서도 bsdtar.
import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { parsePack } from '../shared/characterPack'
import { safeFolderName } from '../shared/misc'

export class ImportError extends Error {}

/** 친구 팩 zip 크기 상한 (팩 하나는 보통 1~3MB) */
export const MAX_ZIP_BYTES = 100 * 1024 * 1024
/** 폴더 안 깊이 상한 (이상한 zip 에서 끝없이 내려가지 않게) */
const MAX_DEPTH = 8

/** 진짜 폴더인지 (바로 가기·심볼릭 링크는 따라가지 않는다 → 팩 밖의 파일을 끌어오거나 무한 반복하지 않게) */
const isRealDir = (p: string) => {
  try {
    const st = lstatSync(p)
    return st.isDirectory() && !st.isSymbolicLink()
  } catch {
    return false
  }
}
const notLink = (p: string) => {
  try {
    return !lstatSync(p).isSymbolicLink()
  } catch {
    return false
  }
}

/** root 아래(자기 자신 포함) character.json 이 든 폴더들 → [폴더, 팩 id]. __MACOSX·숨김 폴더 제외, 이름순 */
export function findPacks(root: string): [string, string][] {
  const out: [string, string][] = []
  const queue: [string, number][] = [[root, 0]]
  while (queue.length) {
    const [dir, depth] = queue.shift()!
    try {
      const pack = parsePack(readFileSync(join(dir, 'character.json'), 'utf8'))
      out.push([dir, pack.id])
      continue // 팩 폴더 안은 더 들어가지 않는다
    } catch {
      /* 팩 아님 → 하위 폴더 */
    }
    let kids: string[] = []
    try {
      kids = readdirSync(dir).sort()
    } catch {
      continue
    }
    for (const k of kids) {
      if (k.startsWith('.') || k === '__MACOSX') continue
      const p = join(dir, k)
      if (depth < MAX_DEPTH && isRealDir(p)) queue.push([p, depth + 1])
    }
  }
  return out
}

function tarPath() {
  return process.platform === 'win32' ? join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'tar.exe') : 'tar'
}

function unzip(zip: string, dest: string) {
  mkdirSync(dest, { recursive: true })
  try {
    execFileSync(tarPath(), ['-xf', zip, '-C', dest], { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true })
  } catch (e) {
    const msg = String((e as { stderr?: Buffer }).stderr ?? '').trim()
    throw new ImportError('zip 파일을 풀지 못했어요.' + (msg ? `\n(${msg})` : ''))
  }
}

/** zip 안에 또 zip 이 있으면 그 자리에 풀어 둔다 (한 단계만) */
function unzipNested(dir: string) {
  const walk = (d: string, depth: number): string[] =>
    readdirSync(d).flatMap((k) => {
      if (k.startsWith('.') || k === '__MACOSX') return []
      const p = join(d, k)
      if (isRealDir(p)) return depth < MAX_DEPTH ? walk(p, depth + 1) : []
      return k.toLowerCase().endsWith('.zip') && notLink(p) ? [p] : []
    })
  for (const z of walk(dir, 0)) {
    try {
      unzip(z, z.slice(0, -4) + '.unzipped')
    } catch {
      /* 안쪽 zip 실패는 무시 */
    }
  }
}

function listing(root: string): string[] {
  try {
    return readdirSync(root)
      .filter((k) => !k.startsWith('.') && k !== '__MACOSX')
      .sort()
      .flatMap((k) => {
        const p = join(root, k)
        const kids = isRealDir(p) ? readdirSync(p).filter((x) => !x.startsWith('.')).sort() : []
        return kids.length ? kids.map((x) => `${k}/${x}`) : [k]
      })
  } catch {
    return []
  }
}

/** 설치하고, 설치된 팩 id 목록을 돌려준다 */
export function importPacks(source: string, friendsDir: string): string[] {
  const work = mkdtempSync(join(tmpdir(), 'termpet-import-'))
  try {
    let root = source
    if (source.toLowerCase().endsWith('.zip')) {
      if (statSync(source).size > MAX_ZIP_BYTES) throw new ImportError('zip 파일이 너무 커요 (100MB 이하만).')
      const copy = join(work, 'source.zip')
      cpSync(source, copy)
      root = join(work, 'unpacked')
      unzip(copy, root)
      unzipNested(root)
    }
    const packs = findPacks(root)
    if (!packs.length) {
      const list = listing(root).slice(0, 8).join(', ')
      throw new ImportError('캐릭터 팩(character.json)을 찾지 못했어요.' + (list ? `\n안에 있던 것: ${list}` : '\n(zip 안이 비어 있어요)'))
    }
    // 1) 먼저 임시 폴더에 모아 둔다 (고른 폴더가 Friends 안이어도 안전하게)
    const staging = join(work, 'staging')
    mkdirSync(staging, { recursive: true })
    const installed: string[] = []
    for (const [folder, id] of packs) {
      if (installed.includes(id)) continue
      // 심볼릭 링크는 빼고 복사 (팩 폴더 밖의 파일을 가리키는 링크가 친구 폴더에 들어오지 않게)
      cpSync(folder, join(staging, safeFolderName(id)), { recursive: true, filter: notLink })
      installed.push(id)
    }
    // 2) 같은 id의 기존 친구만 지운다 (폴더 이름이 id와 달라도). 다른 친구는 그대로
    mkdirSync(friendsDir, { recursive: true })
    for (const [old, id] of findPacks(friendsDir)) if (installed.includes(id)) rmSync(old, { recursive: true, force: true })
    // 3) 새 친구 넣기
    for (const id of installed) {
      const name = safeFolderName(id)
      const dest = join(friendsDir, name)
      if (existsSync(dest)) rmSync(dest, { recursive: true, force: true })
      try {
        renameSync(join(staging, name), dest)
      } catch {
        cpSync(join(staging, name), dest, { recursive: true }) // 다른 드라이브면 rename 불가
      }
    }
    return installed
  } finally {
    rmSync(work, { recursive: true, force: true })
  }
}
