// 윈도우에서만 도는 실제 동작 테스트: settings.json 에 넣는 훅 명령을 Claude Code 처럼 PowerShell 로 실행해서
// 텀펫 서버(가짜)까지 도착하는지 본다. 맥에서는 건너뛰고, GitHub Actions(windows-latest)에서 돈다.
// - Windows PowerShell 5.1 / PowerShell 7 둘 다
// - 실행 정책 Restricted 여도 동작 (스크립트 파일이 아니라 내용을 실행하므로)
// - 한글 JSON 이 바이트 그대로, PostToolUse 큰 입력은 앞부분만, 앱이 꺼져 있어도 빨리 조용히 끝남
import { spawn, spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { createServer, type IncomingMessage } from 'node:http'
import type { AddressInfo } from 'node:net'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { claudeHookCommands } from '../shared/integrations'

const isWin = process.platform === 'win32'
const script = resolve(__dirname, '../../resources/hooks/termpet-claude.ps1')
const shells = isWin ? ['powershell.exe', ...(spawnSync('pwsh', ['-v']).status === 0 ? ['pwsh'] : [])] : []

interface Got {
  path: string
  token?: string
  body: Buffer
}

function runHook(shell: string, command: string, stdin: Buffer, profileDir: string): Promise<{ code: number | null; ms: number; out: string }> {
  return new Promise((done) => {
    const start = Date.now()
    // -ExecutionPolicy Restricted: 스크립트 실행이 막힌 PC와 같은 조건
    const child = spawn(shell, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Restricted', '-Command', command], {
      env: { ...process.env, USERPROFILE: profileDir },
      windowsHide: true,
    })
    let out = ''
    child.stdout.on('data', (b) => (out += b))
    child.stderr.on('data', (b) => (out += b))
    child.stdin.on('error', () => {})
    child.stdin.end(stdin)
    child.on('close', (code) => done({ code, ms: Date.now() - start, out }))
  })
}

describe.skipIf(!isWin)('Claude 훅 스크립트 (윈도우 실제 실행)', () => {
  const got: Got[] = []
  let server: ReturnType<typeof createServer>
  // 사용자 이름에 한글·공백·작은따옴표가 있는 PC 흉내
  const home = mkdtempSync(join(tmpdir(), "텀펫 O'Neil "))
  const bin = join(home, '.termpet', 'bin')
  let cmds: ReturnType<typeof claudeHookCommands>

  beforeAll(async () => {
    server = createServer((req: IncomingMessage, res) => {
      const chunks: Buffer[] = []
      req.on('data', (c: Buffer) => chunks.push(c))
      req.on('end', () => {
        got.push({ path: req.url ?? '', token: req.headers['x-termpet-token'] as string | undefined, body: Buffer.concat(chunks) })
        res.end('ok')
      })
    })
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', r))
    const port = (server.address() as AddressInfo).port
    mkdirSync(bin, { recursive: true })
    writeFileSync(join(home, '.termpet', 'token'), 'secret-token')
    writeFileSync(join(home, '.termpet', 'port'), `${port}\n`)
    const copy = join(bin, 'termpet-claude.ps1')
    writeFileSync(copy, readFileSync(script))
    cmds = claudeHookCommands(copy)
  })
  afterAll(() => server?.close())

  for (const shell of shells) {
    it(`${shell}: 한글 JSON 이 바이트 그대로 + 토큰`, async () => {
      got.length = 0
      const json = Buffer.from(JSON.stringify({ hook_event_name: 'Stop', session_id: 's1', cwd: 'C:\\프로젝트', last_assistant_message: '다 끝났어요 ✨' }), 'utf8')
      const r = await runHook(shell, cmds.command, json, home)
      expect(r.out).toBe('')
      expect(r.code).toBe(0)
      expect(got).toHaveLength(1)
      expect(got[0].path).toBe('/hook/claude')
      expect(got[0].token).toBe('secret-token')
      expect(got[0].body.equals(json)).toBe(true)
    }, 30000)

    it(`${shell}: PostToolUse 큰 입력은 앞부분만`, async () => {
      got.length = 0
      const big = Buffer.from(JSON.stringify({ session_id: 's1', cwd: 'C:\\p', tool_response: 'x'.repeat(3_000_000) }), 'utf8')
      const r = await runHook(shell, cmds.toolCommand, big, home)
      expect(r.code).toBe(0)
      expect(got[0].path).toBe('/hook/claude-tool')
      expect(got[0].body.length).toBeLessThanOrEqual(8192 + 65536)
      expect(got[0].body.toString('utf8')).toContain('"session_id":"s1"')
    }, 30000)

    it(`${shell}: 앱이 꺼져 있어도 조용히 0으로 빨리 끝남`, async () => {
      const off = mkdtempSync(join(tmpdir(), 'termpet-off '))
      mkdirSync(join(off, '.termpet'), { recursive: true })
      writeFileSync(join(off, '.termpet', 'token'), 'secret-token')
      writeFileSync(join(off, '.termpet', 'port'), '1\n') // 아무도 안 듣는 포트
      const r = await runHook(shell, cmds.command, Buffer.from('{}'), off)
      expect(r.out).toBe('')
      expect(r.code).toBe(0)
      expect(r.ms).toBeLessThan(8000)
    }, 30000)
  }
})
