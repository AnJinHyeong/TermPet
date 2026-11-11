// ~/.termpet 아래 파일들 (맥 앱 TermPetPaths.swift 와 같은 구조):
//   ~/.termpet/token                     인증 토큰
//   ~/.termpet/port                      현재 서버 포트 (훅 스크립트가 읽음)
//   ~/.termpet/events.log                받은 요청 기록
//   ~/.termpet/bin/termpet-claude.ps1    Claude Code 훅 (stdin → HTTP, "shell": "powershell")
//   ~/.termpet/bin/termpet-hook.cmd      예전 Claude Code 훅 (0.5.0 이하 설정이 부르던 것 — 업데이트 전까지 유지)
//   ~/.termpet/bin/termpet-hook.ps1      Codex notify 훅
//   ~/.termpet/termpet-profile.ps1       PowerShell 긴 명령 알림
import { app } from 'electron'
import { randomBytes } from 'node:crypto'
import { appendFileSync, chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

// 맥에서 개발 실행할 때는 맥 앱이 쓰는 ~/.termpet(포트·토큰·훅)을 건드리지 않게 따로
export const root = join(homedir(), process.platform === 'win32' ? '.termpet' : '.termpet-electron-dev')
export const tokenFile = join(root, 'token')
export const portFile = join(root, 'port')
export const eventsLog = join(root, 'events.log')
export const binDir = join(root, 'bin')
export const hookCmd = join(binDir, 'termpet-hook.cmd')
export const hookClaudePs1 = join(binDir, 'termpet-claude.ps1')
export const hookPs1 = join(binDir, 'termpet-hook.ps1')
export const profileScript = join(root, 'termpet-profile.ps1')

export const resourcesPath = () => (app.isPackaged ? process.resourcesPath : join(__dirname, '../../resources'))

/** 토큰을 읽고, 없으면 새로 만든다 (32바이트 hex) */
export function loadOrCreateToken(): string {
  mkdirSync(root, { recursive: true, mode: 0o700 })
  try {
    const t = readFileSync(tokenFile, 'utf8').trim()
    if (t.length >= 32) return t
  } catch {
    /* 새로 만든다 */
  }
  const token = randomBytes(32).toString('hex')
  writeFileSync(tokenFile, token, { mode: 0o600 }) // 줄바꿈 없이 (cmd 의 set /p 로 그대로 읽게)
  return token
}

export function writePort(port: number) {
  try {
    writeFileSync(portFile, `${port}\n`)
  } catch (e) {
    console.warn('[TermPet] port 파일 기록 실패', e)
  }
}

/** 앱에 들어 있는 스크립트를 ~/.termpet 에 설치 (항상 최신본. 텀펫 소유 파일이라 덮어써도 됨) */
export function installBundledScripts() {
  mkdirSync(binDir, { recursive: true })
  const src = join(resourcesPath(), 'hooks')
  const items: [string, string][] = [
    ['termpet-hook.cmd', hookCmd],
    ['termpet-claude.ps1', hookClaudePs1],
    ['termpet-hook.ps1', hookPs1],
    ['termpet-profile.ps1', profileScript],
  ]
  for (const [name, dest] of items) {
    try {
      const data = readFileSync(join(src, name))
      if (existsSync(dest) && readFileSync(dest).equals(data)) continue
      copyFileSync(join(src, name), dest)
      if (name.endsWith('.cmd')) chmodSync(dest, 0o755)
    } catch (e) {
      console.warn(`[TermPet] 스크립트 설치 실패: ${name}`, e)
    }
  }
}

/** 요청 기록 한 줄 추가 (256KB 넘으면 .1 로 넘기고 새로) */
export function appendEventsLog(line: string) {
  try {
    if (existsSync(eventsLog) && statSync(eventsLog).size > 256 * 1024) {
      rmSync(eventsLog + '.1', { force: true })
      renameSync(eventsLog, eventsLog + '.1')
    }
    appendFileSync(eventsLog, line + '\n')
  } catch {
    /* 기록 실패는 무시 */
  }
}
