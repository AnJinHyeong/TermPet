// 윈도우 설치 파일에 넣을 koffi 윈도우용 바이너리를 받아 node_modules 에 둔다.
// npm 은 다른 OS용 선택 패키지를 설치하지 않아서(맥에서 빌드할 때) npm pack 으로 직접 받아 푼다.
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const version = JSON.parse(readFileSync('node_modules/koffi/package.json', 'utf8')).version
const name = `@koromix/koffi-win32-x64@${version}`
const work = mkdtempSync(join(tmpdir(), 'koffi-win-'))
try {
  const out = execFileSync('npm', ['pack', name, '--pack-destination', work, '--silent'], { encoding: 'utf8', shell: process.platform === 'win32' }).trim()
  const tgz = join(work, out.split('\n').pop())
  const dest = join('node_modules', '@koromix', 'koffi-win32-x64')
  rmSync(dest, { recursive: true, force: true })
  mkdirSync(dest, { recursive: true })
  execFileSync('tar', ['-xzf', tgz, '-C', dest, '--strip-components=1'])
  console.log(`✓ ${name} → ${dest}`)
} finally {
  rmSync(work, { recursive: true, force: true })
}
