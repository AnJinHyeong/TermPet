// 알림이 온 에디터/터미널 판별 + 말풍선 클릭 시 할 일 (맥 앱 HostApp.swift 의 윈도우판). 순수 로직.
// 윈도우에는 번들 ID가 없어서 훅이 보내는 값으로 추정한다:
//  - VSCODE_GIT_ASKPASS_NODE: VS Code 계열 통합 터미널이면 에디터 exe 경로 (Cursor.exe, Code.exe …)
//  - TERM_PROGRAM: vscode / WezTerm …
//  - WT_SESSION: Windows Terminal
export type HostKind = 'cursor' | 'vscode' | 'vscodeInsiders' | 'windsurf' | 'windowsTerminal' | 'wezterm' | 'claudeApp' | 'other'

export interface HostApp {
  kind: HostKind
  /** 알고 있는 실행 파일 경로 (훅이 보내 준 경우) */
  exePath?: string
}

/** 폴더를 열면 그 프로젝트 창으로 이동하는 에디터 */
export const opensProjectFolder = (k: HostKind) => k === 'cursor' || k === 'vscode' || k === 'vscodeInsiders' || k === 'windsurf'

const baseName = (p: string) => p.split(/[\\/]/).pop()!.toLowerCase()

export function resolveHost(host: string | undefined, termProgram: string | undefined): HostApp | undefined {
  if (host) {
    const name = baseName(host)
    const isPath = /[\\/]/.test(host)
    const withPath = (kind: HostKind): HostApp => (isPath ? { kind, exePath: host } : { kind })
    if (name === 'cursor.exe') return withPath('cursor')
    if (name === 'code.exe') return withPath('vscode')
    if (name === 'code - insiders.exe') return withPath('vscodeInsiders')
    if (name === 'windsurf.exe') return withPath('windsurf')
    if (host === 'WindowsTerminal' || name === 'windowsterminal.exe') return { kind: 'windowsTerminal' }
    if (name === 'wezterm-gui.exe') return { kind: 'wezterm' }
    if (name === 'claude.exe') return { kind: 'claudeApp' } // Claude 데스크톱 앱 (일반 채팅 MCP 알림)
  }
  switch (termProgram) {
    case 'vscode':
      return { kind: 'vscode' } // Cursor도 vscode라서 exe 경로가 없으면 VS Code로 추정할 수밖에 없다
    case 'WezTerm':
      return { kind: 'wezterm' }
  }
  return host ? { kind: 'other' } : undefined
}

/** 표준 설치 위치 후보 (사용자 설치 → 전체 설치) */
export function editorCandidates(kind: HostKind, env: { LOCALAPPDATA?: string; ProgramFiles?: string }): string[] {
  const local = env.LOCALAPPDATA ?? ''
  const pf = env.ProgramFiles ?? 'C:\\Program Files'
  switch (kind) {
    case 'cursor':
      return [`${local}\\Programs\\cursor\\Cursor.exe`, `${pf}\\Cursor\\Cursor.exe`]
    case 'vscode':
      return [`${local}\\Programs\\Microsoft VS Code\\Code.exe`, `${pf}\\Microsoft VS Code\\Code.exe`]
    case 'vscodeInsiders':
      return [`${local}\\Programs\\Microsoft VS Code Insiders\\Code - Insiders.exe`, `${pf}\\Microsoft VS Code Insiders\\Code - Insiders.exe`]
    case 'windsurf':
      return [`${local}\\Programs\\Windsurf\\Windsurf.exe`, `${pf}\\Windsurf\\Windsurf.exe`]
    default:
      return []
  }
}

/** 앞으로 가져올 창의 프로세스 이름 */
export function processNamesFor(kind: HostKind): string[] {
  switch (kind) {
    case 'windowsTerminal':
      return ['windowsterminal.exe']
    case 'wezterm':
      return ['wezterm-gui.exe']
    case 'claudeApp':
      return ['claude.exe']
    case 'cursor':
      return ['cursor.exe']
    case 'vscode':
      return ['code.exe']
    case 'vscodeInsiders':
      return ['code - insiders.exe']
    case 'windsurf':
      return ['windsurf.exe']
    default:
      return []
  }
}

export type FocusAction = { type: 'openFolder'; host: HostApp; path: string } | { type: 'activate'; host: HostApp } | { type: 'none' }

export function planFocus(e: { host?: string; termProgram?: string; cwd?: string }, projectRoot: (cwd: string) => string): FocusAction {
  const host = resolveHost(e.host, e.termProgram)
  if (!host || host.kind === 'other') return { type: 'none' }
  if (opensProjectFolder(host.kind) && e.cwd) return { type: 'openFolder', host, path: projectRoot(e.cwd) }
  return { type: 'activate', host }
}

/** cwd에서 위로 올라가며 .git 이 있는 폴더(프로젝트 루트)를 찾는다 (하위 폴더를 새 창으로 여는 것 방지) */
export function findProjectRoot(cwd: string, home: string, exists: (p: string) => boolean): string {
  const sepr = cwd.includes('\\') ? '\\' : '/'
  let dir = cwd.replace(/[\\/]+$/, '')
  const norm = (p: string) => p.replace(/[\\/]+$/, '').toLowerCase()
  while (dir && norm(dir) !== norm(home) && !/^[A-Za-z]:$/.test(dir) && dir !== '') {
    if (exists(dir + sepr + '.git')) return dir
    const i = Math.max(dir.lastIndexOf('\\'), dir.lastIndexOf('/'))
    if (i <= 0) break
    dir = dir.slice(0, i)
  }
  return cwd
}
