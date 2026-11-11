// 패널의 [연결 확인]: 각 PC 환경에서 알림이 실제로 오는지 처음부터 끝까지 확인한다.
// 설정 파일만 보는 게 아니라, 훅 명령을 Claude Code·Codex 가 하는 것과 같은 방식으로 직접 실행해서
// 앱 서버까지 도착하는지(한글 인코딩 포함) 본다. 실패하면 단계별로 이유와 해결 방법을 알려 준다.
// React 비유: 버튼 클릭 → async 함수가 단계별 결과 배열을 만들어 상태로 돌려주는 것.
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { randomBytes } from 'node:crypto'
import { SELF_TEST_CWD, SELF_TEST_EVENT, type PetEvent } from '../shared/events'
import { executionPolicyBlocksProfile, hooksBlockedBy } from '../shared/integrations'
import type { CheckResult, CheckStep, IntegrationKind } from '../shared/ipc'
import { claudeCmds, claudeSettingsFile, readText, status } from './integrations'
import { hookPs1 } from './paths'

const SELF_TEST_PREFIX = 'termpet-selftest-'

// MARK: - 서버에 도착한 확인용 이벤트 기다리기

const waiting = new Map<string, (e: PetEvent) => void>()

/** 서버가 받은 이벤트가 [연결 확인]이 보낸 것이면 기다리던 쪽에 넘기고 true (펫에는 cwd·세션 없이 전달) */
export function takeSelfTest(e: PetEvent): boolean {
  if (!e.sessionId?.startsWith(SELF_TEST_PREFIX)) return false
  waiting.get(e.sessionId)?.(e)
  waiting.delete(e.sessionId)
  return true
}

function waitFor(id: string, ms: number): Promise<PetEvent | undefined> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      waiting.delete(id)
      resolve(undefined)
    }, ms)
    waiting.set(id, (e) => {
      clearTimeout(timer)
      resolve(e)
    })
  })
}

// MARK: - 프로세스 실행

interface RunResult {
  code: number | null
  output: string
}

/** 명령 실행 (stdin 을 UTF-8 바이트로 넣고, 출력은 앞부분만). 시간 초과면 강제 종료 */
function run(file: string, args: string[], stdin?: string, timeoutMs = 15000): Promise<RunResult> {
  return new Promise((resolve) => {
    let output = ''
    let done = false
    const finish = (r: RunResult) => {
      if (!done) {
        done = true
        resolve(r)
      }
    }
    try {
      const child = spawn(file, args, { windowsHide: true })
      const timer = setTimeout(() => {
        child.kill()
        finish({ code: null, output: output || '시간 초과' })
      }, timeoutMs)
      const collect = (b: Buffer) => {
        if (output.length < 2000) output += b.toString('utf8')
      }
      child.stdout.on('data', collect)
      child.stderr.on('data', collect)
      child.on('error', (err) => {
        clearTimeout(timer)
        finish({ code: -1, output: err.message })
      })
      child.on('close', (code) => {
        clearTimeout(timer)
        finish({ code, output })
      })
      child.stdin.on('error', () => {}) // 스크립트가 stdin 을 다 안 읽고 끝나도 무시
      child.stdin.end(stdin === undefined ? undefined : Buffer.from(stdin, 'utf8'))
    } catch (err) {
      finish({ code: -1, output: (err as Error).message })
    }
  })
}

/** 출력에서 사람이 읽을 첫 줄 (PowerShell 오류 메시지 등) */
const firstLine = (s: string) => s.split(/\r?\n/).map((l) => l.trim()).find((l) => l) ?? ''

/** Windows PowerShell 5.1 (윈도우 10/11 에 항상 있음). Claude Code 가 훅을 PowerShell 로 돌릴 때와 같은 방식 */
const powershell = (command: string, stdin?: string) => run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], stdin)

/** Git Bash 위치 (Claude Code 가 Git 이 있으면 Bash 를 기본 셸로 쓴다 — 우리 훅은 셸을 PowerShell 로 고정해서 상관없음) */
function gitBashPath(): string | undefined {
  const fromEnv = process.env.CLAUDE_CODE_GIT_BASH_PATH
  const candidates = [
    fromEnv,
    join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Git', 'bin', 'bash.exe'),
    join(process.env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local'), 'Programs', 'Git', 'bin', 'bash.exe'),
  ]
  return candidates.find((p) => p && existsSync(p))
}

/** 관리자(회사) 설정 파일 — 공식 문서의 윈도우 경로 (예전 위치 포함) */
function managedSettingsText(): string | undefined {
  for (const p of ['C:\\Program Files\\ClaudeCode\\managed-settings.json', 'C:\\ProgramData\\ClaudeCode\\managed-settings.json']) {
    try {
      const t = readText(p).text
      if (t !== undefined) return t
    } catch {
      /* 못 읽으면 없는 것으로 */
    }
  }
  return undefined
}

// MARK: - 연동별 확인

export interface DiagnoseContext {
  serverOk: boolean
  serverText: string
}

const step = (label: string, ok: boolean | null, detail?: string): CheckStep => ({ label, ok, detail })

export async function diagnose(kind: IntegrationKind, ctx: DiagnoseContext): Promise<CheckResult> {
  if (process.platform !== 'win32') return { running: false, ok: false, steps: [step('윈도우에서만 확인할 수 있어요', false)] }
  switch (kind) {
    case 'claude':
      return diagnoseClaude(ctx)
    case 'codex':
      return diagnoseCodex(ctx)
    case 'powershell':
      return diagnosePowerShell(ctx)
  }
}

function finish(steps: CheckStep[], fix?: CheckResult['fix']): CheckResult {
  return { running: false, ok: steps.every((s) => s.ok !== false), steps, fix }
}

async function diagnoseClaude(ctx: DiagnoseContext): Promise<CheckResult> {
  const steps: CheckStep[] = []
  const st = status('claude')
  const settingsPath = claudeSettingsFile()
  if (!st.installed) steps.push(step('설정 파일', false, `${settingsPath} 에 텀펫 훅이 없어요. [연결]을 눌러 주세요`))
  else if (st.needsUpdate) steps.push(step('설정 파일', false, '예전 형식이에요. [업데이트]를 누르면 이 PC에 맞게 바꿔요 (백업 후)'))
  else steps.push(step('설정 파일', true, 'PowerShell 로 실행되게 연결돼 있어요'))

  let userText: string | undefined
  try {
    userText = readText(settingsPath).text
  } catch {
    /* 위에서 이미 알림 */
  }
  const blocked = hooksBlockedBy(userText, managedSettingsText())
  steps.push(blocked ? step('훅 허용', false, blocked) : step('훅 허용', true))

  const bash = gitBashPath()
  steps.push(step('Git Bash', null, bash ? '있음 (텀펫 훅은 셸을 PowerShell 로 고정해서 상관없어요)' : '없음 → Claude Code 기본 셸이 PowerShell 이에요 (텀펫 훅은 그대로 동작)'))

  steps.push(step('알림 서버', ctx.serverOk, ctx.serverOk ? undefined : ctx.serverText))
  if (!ctx.serverOk || !st.installed) return finish(steps)

  // 실제 실행: settings.json 에 넣는 것과 같은 명령을 PowerShell 로, 같은 JSON 을 stdin 으로
  const id = SELF_TEST_PREFIX + randomBytes(6).toString('hex')
  const input = JSON.stringify({ hook_event_name: SELF_TEST_EVENT, session_id: id, cwd: SELF_TEST_CWD })
  const arrived = waitFor(id, 12000)
  const result = await powershell(claudeCmds().command, input)
  const e = await arrived
  if (!e) {
    const why = result.code === null ? 'PowerShell 이 응답하지 않아요' : firstLine(result.output) || `종료 코드 ${result.code}`
    steps.push(step('훅 실행 → 앱 도착', false, `도착하지 않았어요: ${why}. 백신·보안 프로그램이 PowerShell 을 막는지 확인해 주세요`))
  } else if (e.cwd !== SELF_TEST_CWD) {
    steps.push(step('훅 실행 → 앱 도착', false, '도착했지만 한글이 깨져요. 이 화면을 캡처해서 알려 주세요'))
  } else {
    steps.push(step('훅 실행 → 앱 도착', true, '펫 말풍선이 떴다면 끝! 이미 열려 있던 Claude 세션도 곧 반영돼요'))
  }
  return finish(steps)
}

async function diagnoseCodex(ctx: DiagnoseContext): Promise<CheckResult> {
  const steps: CheckStep[] = []
  const st = status('codex')
  steps.push(st.installed ? step('설정 파일', true) : step('설정 파일', false, '~/.codex/config.toml 에 텀펫 notify 가 없어요. [연결]을 눌러 주세요'))
  steps.push(step('알림 서버', ctx.serverOk, ctx.serverOk ? undefined : ctx.serverText))
  if (!ctx.serverOk || !st.installed) return finish(steps)

  // Codex 가 하는 것처럼 JSON 을 마지막 인자로 넘겨 notify 스크립트 실행
  const id = SELF_TEST_PREFIX + randomBytes(6).toString('hex')
  const json = JSON.stringify({ type: 'agent-turn-complete', 'thread-id': id, cwd: SELF_TEST_CWD, 'last-assistant-message': '연결 확인 완료!' })
  const arrived = waitFor(id, 12000)
  const result = await run('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', hookPs1, 'codex', json])
  const e = await arrived
  if (!e) steps.push(step('notify 실행 → 앱 도착', false, `도착하지 않았어요: ${firstLine(result.output) || `종료 코드 ${result.code}`}`))
  else steps.push(step('notify 실행 → 앱 도착', true, e.cwd === SELF_TEST_CWD ? undefined : '도착했지만 한글 경로가 깨져요'))
  return finish(steps)
}

async function diagnosePowerShell(ctx: DiagnoseContext): Promise<CheckResult> {
  const steps: CheckStep[] = []
  const st = status('powershell')
  steps.push(st.installed ? step('프로필', true) : step('프로필', false, 'PowerShell 프로필에 텀펫 줄이 없어요. [연결]을 눌러 주세요'))

  // 실행 정책이 Restricted 면 프로필(.ps1) 자체가 실행되지 않는다 — 윈도우 기본값이라 PC마다 다름
  const policy = await powershell('Get-ExecutionPolicy')
  const blocked = executionPolicyBlocksProfile(policy.output)
  steps.push(
    blocked
      ? step('스크립트 실행 허용', false, `실행 정책이 ${firstLine(policy.output) || '알 수 없음'}이라 프로필이 실행되지 않아요. [허용]을 누르면 내 계정에만 RemoteSigned 로 바꿔요`)
      : step('스크립트 실행 허용', true, firstLine(policy.output)),
  )
  steps.push(step('알림 서버', ctx.serverOk, ctx.serverOk ? undefined : ctx.serverText))

  if (st.installed && !blocked) {
    // 프로필을 읽는 새 PowerShell 에서 텀펫 스크립트가 실제로 올라오는지
    const loaded = await run('powershell.exe', ['-NoLogo', '-NonInteractive', '-Command', 'if ($global:__TermPetLoaded) { "termpet-ok" } else { "termpet-missing" }'])
    const ok = loaded.output.includes('termpet-ok')
    steps.push(step('새 PowerShell 창에서 불러오기', ok, ok ? '30초 넘게 걸린 명령이 끝나면 알려줘요' : firstLine(loaded.output.replace('termpet-missing', '')) || '프로필이 텀펫 스크립트를 불러오지 못했어요'))
  }
  return finish(steps, blocked ? { label: '허용', action: 'allowScripts' } : undefined)
}

/** [허용]: 현재 사용자 범위만 RemoteSigned (관리자 권한 불필요, 회사 정책이 덮으면 실패) */
export async function allowScripts(): Promise<string | undefined> {
  const r = await powershell('Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force; Get-ExecutionPolicy')
  return executionPolicyBlocksProfile(r.output) ? firstLine(r.output) || '바꾸지 못했어요 (회사 정책일 수 있어요)' : undefined
}
