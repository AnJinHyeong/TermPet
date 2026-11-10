// 사용자 설정 파일에 텀펫 연동을 넣고/빼는 순수 로직 (맥 앱 IntegrationConfig.swift 이식 + 윈도우용 PowerShell).
// 원칙: 기존 내용은 건드리지 않고 우리 항목만 추가/삭제. 해석할 수 없는 파일이면 에러로 멈춘다 (덮어쓰지 않음).

export class IntegrationError extends Error {}

// MARK: - Claude Code (~/.claude/settings.json)

export const CLAUDE_CORE_EVENTS = ['Stop', 'Notification']
export const CLAUDE_PROGRESS_EVENTS = ['UserPromptSubmit', 'PostToolUse', 'StopFailure', 'SessionEnd']
export const CLAUDE_EVENTS = [...CLAUDE_CORE_EVENTS, ...CLAUDE_PROGRESS_EVENTS]
export const HOOK_MARKER = 'termpet-hook'

/**
 * 윈도우 훅 명령. Claude Code가 훅을 Git Bash로 돌릴지 cmd.exe로 돌릴지 버전마다 달라서
 * (TODO: 공식 문서에서 확정되면 정리) 양쪽 다 실행되는 형태로 만든다:
 * 슬래시(/) 절대 경로 + 큰따옴표, 환경변수($HOME/%USERPROFILE%) 없이.
 */
export function claudeHookCommands(hookCmdPath: string) {
  const p = hookCmdPath.replaceAll('\\', '/')
  return { command: `"${p}" claude`, toolCommand: `"${p}" claude-tool` }
}

type Json = Record<string, unknown>

function parseSettings(text: string | undefined): Json {
  if (!text || !text.trim()) return {}
  let v: unknown
  try {
    v = JSON.parse(text.replace(/^﻿/, '')) // 메모장이 붙이는 BOM 제거
  } catch {
    throw new IntegrationError('settings.json 이 올바른 JSON 객체가 아니에요')
  }
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw new IntegrationError('settings.json 이 올바른 JSON 객체가 아니에요')
  return v as Json
}

const isOurs = (hook: unknown) => typeof (hook as Json)?.command === 'string' && ((hook as Json).command as string).includes(HOOK_MARKER)
const groupHooks = (g: unknown): unknown[] => (Array.isArray((g as Json)?.hooks) ? ((g as Json).hooks as unknown[]) : [])
const hasOurs = (groups: unknown) => Array.isArray(groups) && groups.some((g) => groupHooks(g).some(isOurs))

function hooksOf(text: string | undefined): Json | undefined {
  try {
    const h = parseSettings(text).hooks
    return typeof h === 'object' && h !== null ? (h as Json) : undefined
  } catch {
    return undefined
  }
}

export const ClaudeHooks = {
  isInstalled(text: string | undefined): boolean {
    const h = hooksOf(text)
    return !!h && CLAUDE_CORE_EVENTS.every((e) => hasOurs(h[e]))
  },

  missingEvents(text: string | undefined): string[] {
    const h = hooksOf(text) ?? {}
    return CLAUDE_EVENTS.filter((e) => !hasOurs(h[e]))
  },

  entry(event: string, cmds: { command: string; toolCommand: string }): Json {
    const e: Json = { type: 'command', command: event === 'PostToolUse' ? cmds.toolCommand : cmds.command, timeout: 5 }
    if (CLAUDE_PROGRESS_EVENTS.includes(event)) e.async = true
    return e
  },

  install(text: string | undefined, cmds: { command: string; toolCommand: string }): string {
    const root = parseSettings(text)
    const hooks = (typeof root.hooks === 'object' && root.hooks !== null ? root.hooks : {}) as Json
    for (const event of CLAUDE_EVENTS) {
      if (hasOurs(hooks[event])) continue
      const groups = Array.isArray(hooks[event]) ? (hooks[event] as unknown[]) : []
      hooks[event] = [...groups, { hooks: [ClaudeHooks.entry(event, cmds)] }]
    }
    root.hooks = hooks
    return JSON.stringify(root, null, 2) + '\n'
  },

  uninstall(text: string): string {
    const root = parseSettings(text)
    const hooks = root.hooks as Json | undefined
    if (typeof hooks !== 'object' || hooks === null) return text
    for (const event of CLAUDE_EVENTS) {
      const groups = hooks[event]
      if (!Array.isArray(groups)) continue
      const cleaned = groups.flatMap((g) => {
        if (!Array.isArray((g as Json)?.hooks)) return [g]
        const kept = groupHooks(g).filter((h) => !isOurs(h))
        return kept.length ? [{ ...(g as Json), hooks: kept }] : []
      })
      if (cleaned.length) hooks[event] = cleaned
      else delete hooks[event]
    }
    return JSON.stringify(root, null, 2) + '\n'
  },
}

// MARK: - PowerShell 프로필 (긴 명령 알림) — 맥의 ~/.zshrc 대응

export const PROFILE_MARKER = '.termpet\\termpet-profile.ps1'
export const PROFILE_COMMENT = '# 텀펫: 오래 걸린 명령 알림'
export const PROFILE_LINE = `if (Test-Path "$HOME\\.termpet\\termpet-profile.ps1") { . "$HOME\\.termpet\\termpet-profile.ps1" }`

const isProfileLine = (l: string) => l.includes(PROFILE_MARKER) && !l.trim().startsWith('#')

export const PowerShellProfile = {
  isInstalled(text: string | undefined): boolean {
    return (text ?? '').split(/\r?\n/).some(isProfileLine)
  },
  install(text: string | undefined): string {
    const t = text ?? ''
    if (PowerShellProfile.isInstalled(t)) return t
    const nl = t.includes('\r\n') ? '\r\n' : '\n'
    const base = !t || t.endsWith('\n') ? t : t + nl
    return base + nl + PROFILE_COMMENT + nl + PROFILE_LINE + nl
  },
  uninstall(text: string): string {
    const nl = text.includes('\r\n') ? '\r\n' : '\n'
    return text
      .split(/\r?\n/)
      .filter((l) => !isProfileLine(l) && l !== PROFILE_COMMENT)
      .join(nl)
  },
}

// MARK: - Codex (~/.codex/config.toml)

/**
 * Codex는 루트의 `notify = ["프로그램", "인자", ...]` 하나만 받고 끝에 JSON을 붙여 실행한다.
 * 윈도우: notify = ["powershell.exe", ..., "-File", "<termpet-hook.ps1>", "codex"]
 * 이미 다른 notify가 있으면 "연결(chain)": [..., "codex-chain", <원래 명령...>] → 해제 시 원래 줄로 복원
 */
export const CodexNotify = {
  hookPrefix(ps1Path: string): string[] {
    return ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ps1Path]
  },

  /** 우리 notify면 [codex 인자 위치] 반환 */
  ourIndex(args: string[]): number {
    const i = args.findIndex((a) => a.includes(HOOK_MARKER))
    return i < 0 ? -1 : i + 1
  },

  isInstalled(text: string | undefined): boolean {
    const found = text ? rootNotify(text) : undefined
    return !!found && CodexNotify.ourIndex(found[1]) >= 0
  },

  install(text: string | undefined, ps1Path: string): string {
    const t = text ?? ''
    if (CodexNotify.isInstalled(t)) return t
    const nl = t.includes('\r\n') ? '\r\n' : '\n'
    const prefix = CodexNotify.hookPrefix(ps1Path)
    const found = rootNotify(t)
    if (found) {
      const lines = t.split(/\r?\n/)
      lines[found[0]] = renderNotify([...prefix, 'codex-chain', ...found[1]])
      return lines.join(nl)
    }
    if (hasUnparsedRootNotify(t)) throw new IntegrationError('config.toml 의 notify 형식을 읽을 수 없어요. 한 줄 배열로 바꾼 뒤 다시 시도해 주세요')
    const lines = t ? t.split(/\r?\n/) : []
    let first = lines.findIndex((l) => l.trim().startsWith('['))
    if (first < 0) first = lines.length
    lines.splice(first, 0, renderNotify([...prefix, 'codex']))
    let out = lines.join(nl)
    if (!out.endsWith('\n')) out += nl
    return out
  },

  uninstall(text: string): string {
    const found = rootNotify(text)
    if (!found) return text
    const [index, args] = found
    const at = CodexNotify.ourIndex(args)
    if (at < 0) return text
    const nl = text.includes('\r\n') ? '\r\n' : '\n'
    const lines = text.split(/\r?\n/)
    if (args[at] === 'codex-chain' && args.length > at + 1) lines[index] = renderNotify(args.slice(at + 1))
    else lines.splice(index, 1)
    return lines.join(nl)
  },
}

/** 첫 [테이블] 전의 `notify = [...]` 줄 번호와 값 */
export function rootNotify(text: string): [number, string[]] | undefined {
  const lines = text.split(/\r?\n/)
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line.startsWith('[')) return undefined
    const m = /^notify\s*=(.*)$/.exec(line)
    if (!m) continue
    const arr = parseStringArray(m[1])
    return arr ? [i, arr] : undefined
  }
  return undefined
}

function hasUnparsedRootNotify(text: string): boolean {
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim()
    if (line.startsWith('[')) return false
    if (line.startsWith('notify')) return true
  }
  return false
}

/** `["a", 'b', "c\"d"] # 주석` → 배열. TOML 기본 문자열("")과 리터럴 문자열('') 지원. 형식이 다르면 undefined */
export function parseStringArray(value: string): string[] | undefined {
  let s = value.trim()
  if (!s.startsWith('[')) return undefined
  s = s.slice(1)
  const out: string[] = []
  for (;;) {
    s = s.replace(/^[ \t]+/, '')
    if (s.startsWith(']')) return out
    const q = s[0]
    if (q !== '"' && q !== "'") return undefined
    s = s.slice(1)
    let item = ''
    let closed = false
    while (s.length) {
      const c = s[0]
      s = s.slice(1)
      if (q === '"' && c === '\\' && s.length) {
        const n = s[0]
        s = s.slice(1)
        item += n === 'n' ? '\n' : n === 't' ? '\t' : n
        continue
      }
      if (c === q) {
        closed = true
        break
      }
      item += c
    }
    if (!closed) return undefined
    out.push(item)
    s = s.replace(/^[ \t]+/, '')
    if (s.startsWith(',')) s = s.slice(1)
  }
}

export function renderNotify(args: string[]): string {
  return 'notify = [' + args.map((a) => '"' + a.replaceAll('\\', '\\\\').replaceAll('"', '\\"') + '"').join(', ') + ']'
}

/** 백업 파일 이름용 시각 (yyyyMMdd-HHmmss) */
export function backupStamp(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
}
