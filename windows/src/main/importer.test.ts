// 친구 팩 가져오기 테스트 (임시 폴더에 실제 파일을 만들어서)
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { findPacks, importPacks } from './importer'

const dirs: string[] = []
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'termpet-test-'))
  dirs.push(d)
  return d
}
afterEach(() => dirs.splice(0).forEach((d) => rmSync(d, { recursive: true, force: true })))

function makePack(dir: string, id: string) {
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, 'character.json'), JSON.stringify({ id, frameWidth: 32, frameHeight: 32, states: { idle: { file: 'idle.png' } } }))
  writeFileSync(join(dir, 'idle.png'), '')
}

describe('importer', () => {
  it('하위 폴더의 팩을 모두 찾고 __MACOSX 는 건너뛴다', () => {
    const root = tmp()
    makePack(join(root, 'b', 'bunny'), 'bunny')
    makePack(join(root, 'a'), 'cat')
    makePack(join(root, '__MACOSX', 'x'), 'ghost')
    expect(findPacks(root).map(([, id]) => id)).toEqual(['cat', 'bunny'])
  })

  it('zip 을 풀어 기존 친구를 새 친구들로 교체', () => {
    const src = tmp()
    makePack(join(src, 'pack', 'cat'), 'cat')
    const zip = join(tmp(), 'friends.zip')
    execFileSync('tar', ['-a', '-cf', zip, '-C', src, 'pack']) // bsdtar: 확장자로 zip 형식
    const friends = tmp()
    makePack(join(friends, 'old'), 'old')
    expect(importPacks(zip, friends)).toEqual(['cat'])
    expect(readdirSync(friends)).toEqual(['cat'])
  })

  it('팩이 없으면 에러, 기존 친구는 그대로', () => {
    const empty = tmp()
    writeFileSync(join(empty, 'readme.txt'), 'hi')
    const friends = tmp()
    makePack(join(friends, 'old'), 'old')
    expect(() => importPacks(empty, friends)).toThrow(/찾지 못했어요/)
    expect(readdirSync(friends)).toEqual(['old'])
  })
})
