// 패널의 "AI 연결" 버튼: 설정 파일을 백업한 뒤 텀펫 항목만 추가/삭제 (맥 IntegrationManager.swift 대응).
// 사용자가 버튼을 눌렀을 때만 파일을 바꾼다. 해석할 수 없는 파일이면 손대지 않고 에러.
import { app } from 'electron'
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import type { IntegrationKind } from '../shared/ipc'
import { backupStamp, claudeHookCommands, ClaudeHooks, CodexNotify, IntegrationError, PowerShellProfile } from '../shared/integrations'
import { hookCmd, hookPs1 } from './paths'

export const INTEGRATIONS: { kind: IntegrationKind; title: string; subtitle: string }[] = [
  { kind: 'claude', title: 'Claude Code', subtitle: '응답 완료 · 권한 요청' },
  { kind: 'codex', title: 'Codex', subtitle: '응답 완료' },
  { kind: 'powershell', title: '터미널 명령', subtitle: '30초 넘게 걸린 PowerShell 명령' },
]

const home = homedir()

/** 연동별 설정 파일. PowerShell 은 Windows PowerShell 5.1 · PowerShell 7 프로필 둘 다 */
export function filesFor(kind: IntegrationKind): string[] {
  switch (kind) {
    case 'claude':
      return [join(home, '.claude', 'settings.json')]
    case 'codex':
      return [join(home, '.codex', 'config.toml')]
    case 'powershell': {
      const docs = app.getPath('documents') // OneDrive 로 옮긴 문서 폴더도 정확히
      return [join(docs, 'WindowsPowerShell', 'Microsoft.PowerShell_profile.ps1'), join(docs, 'PowerShell', 'Microsoft.PowerShell_profile.ps1')]
    }
  }
}

interface FileText {
  path: string
  text?: string
  bom: boolean
}

function readText(path: string): FileText {
  let real = path
  try {
    real = realpathSync(path) // dotfiles 심볼릭 링크면 실제 파일을 고친다
  } catch {
    /* 없는 파일 */
  }
  if (!existsSync(real)) return { path: real, bom: false }
  const buf = readFileSync(real)
  const bom = buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf
  const text = buf.toString('utf8', bom ? 3 : 0)
  if (text.includes('�') || (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe)) {
    throw new IntegrationError(`${path} 이 UTF-8 이 아니라서 건드리지 않았어요`)
  }
  return { path: real, text, bom }
}

/** 맥에서 개발 실행할 땐 실제 설정 파일(맥 앱이 쓰는)에 윈도우용 명령을 넣지 않게 막는다 */
export function isAvailable(kind: IntegrationKind): boolean {
  if (process.platform !== 'win32') return false
  return kind !== 'codex' || existsSync(join(home, '.codex'))
}

export function status(kind: IntegrationKind): { installed: boolean; needsUpdate: boolean } {
  try {
    const files = filesFor(kind).map(readText)
    switch (kind) {
      case 'claude': {
        const installed = ClaudeHooks.isInstalled(files[0].text)
        return { installed, needsUpdate: installed && ClaudeHooks.missingEvents(files[0].text).length > 0 }
      }
      case 'codex':
        return { installed: CodexNotify.isInstalled(files[0].text), needsUpdate: false }
      case 'powershell': {
        const states = files.map((f) => PowerShellProfile.isInstalled(f.text))
        return { installed: states.some(Boolean), needsUpdate: states.some(Boolean) && !states.every(Boolean) }
      }
    }
  } catch {
    return { installed: false, needsUpdate: false }
  }
}

/** 연결 ↔ 해제 (업데이트가 필요하면 해제 대신 빠진 항목만 추가). 바뀐 파일들의 백업 경로를 돌려준다 */
export function toggle(kind: IntegrationKind, remove: boolean): string[] {
  if (!isAvailable(kind)) throw new IntegrationError('이 환경에서는 연결할 수 없어요')
  const { installed, needsUpdate } = status(kind)
  const on = installed && (remove || !needsUpdate)
  const files = filesFor(kind).map(readText) // 모두 먼저 읽어서 하나라도 못 읽으면 아무것도 안 바꾼다
  const updates: [FileText, string][] = files.map((f) => {
    switch (kind) {
      case 'claude':
        return [f, on ? ClaudeHooks.uninstall(f.text ?? '{}') : ClaudeHooks.install(f.text, claudeHookCommands(hookCmd))]
      case 'codex':
        return [f, on ? CodexNotify.uninstall(f.text ?? '') : CodexNotify.install(f.text, hookPs1)]
      case 'powershell':
        return [f, on ? PowerShellProfile.uninstall(f.text ?? '') : PowerShellProfile.install(f.text)]
    }
  })
  const backups: string[] = []
  const stamp = backupStamp(new Date())
  for (const [f, next] of updates) {
    if (next === (f.text ?? '')) continue
    if (f.text === undefined && on) continue // 해제인데 파일이 없으면 만들 필요 없음
    if (f.text !== undefined) {
      const backup = `${f.path}.termpet-backup-${stamp}`
      writeFileSync(backup, readFileSync(f.path))
      backups.push(backup)
    }
    mkdirSync(dirname(f.path), { recursive: true })
    // PowerShell 5.1 은 BOM 없는 UTF-8 을 ANSI 로 읽는다 → 새 프로필은 BOM 을 붙이고, 기존 파일은 원래대로
    const bom = f.text === undefined ? kind === 'powershell' : f.bom
    writeFileSync(f.path, (bom ? '﻿' : '') + next)
  }
  return backups
}
