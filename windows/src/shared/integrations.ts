// 사용자 설정 파일에 텀펫 연동을 넣고/빼는 순수 로직 (맥 앱 IntegrationConfig.swift 이식 + 윈도우용 PowerShell).
// 원칙: 기존 내용은 건드리지 않고 우리 항목만 추가/삭제. 해석할 수 없는 파일이면 에러로 멈춘다 (덮어쓰지 않음).

export class IntegrationError extends Error {}

// MARK: - Claude Code (~/.claude/settings.json)

export const CLAUDE_CORE_EVENTS = ['Stop', 'Notification']
export const CLAUDE_PROGRESS_EVENTS = ['UserPromptSubmit', 'PostToolUse', 'StopFailure', 'SessionEnd']
export const CLAUDE_EVENTS = [...CLAUDE_CORE_EVENTS, ...CLAUDE_PROGRESS_EVENTS]
export const HOOK_MARKER = 'termpet-hook'

export interface ClaudeHookCommands {
  command: string
  toolCommand: string
}

/** PowerShell 작은따옴표 문자열 ('' 로 이스케이프) */
export const psQuote = (s: string) => `'${s.replaceAll("'", "''")}'`

/**
 * 윈도우 훅 명령. Claude Code 는 훅을 Git Bash 로, Git 이 없으면 PowerShell 로 돌린다 (공식 문서:
 * https://code.claude.com/docs/en/hooks — "Git Bash on Windows, or PowerShell when Git Bash isn't installed").
 * PC마다 셸이 달라지지 않게 훅 항목에 `"shell": "powershell"` 을 지정하고, PowerShell 문법으로 쓴다.
 * 스크립트 파일을 `& .ps1` 로 부르면 실행 정책(Restricted)에 막히므로, 파일 내용을 scriptblock 으로 만들어 실행한다.
 */
export function claudeHookCommands(ps1Path: string): ClaudeHookCommands {
  const run = `& ([scriptblock]::Create([IO.File]::ReadAllText(${psQuote(ps1Path)})))`
  return { command: `${run} claude`, toolCommand: `${run} claude-tool` }
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

/** 우리 훅: 지금 형식(termpet-claude.ps1)과 예전 형식(termpet-hook.cmd) 모두 */
const CLAUDE_MARKERS = [HOOK_MARKER, 'termpet-claude']
const isOurs = (hook: unknown) => {
  const c = (hook as Json)?.command
  return typeof c === 'string' && CLAUDE_MARKERS.some((m) => c.includes(m))
}
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

  /** 빠진 이벤트가 있거나, 우리 항목이 지금 형식과 다르면(예전 .cmd 명령 등) 업데이트 필요 */
  needsUpdate(text: string | undefined, cmds: ClaudeHookCommands): boolean {
    const h = hooksOf(text) ?? {}
    return CLAUDE_EVENTS.some((e) => !isCurrent(h[e], ClaudeHooks.entry(e, cmds)))
  },

  /**
   * 이벤트별 항목. 윈도우는 PowerShell 을 띄우는 데 0.3~1초 걸려서 모두 async(백그라운드) —
   * 응답이 끝날 때 Claude 를 기다리게 하지 않는다 (알림만 보내고 결정은 안 하므로 async 여도 됨).
   */
  entry(event: string, cmds: ClaudeHookCommands): Json {
    return { type: 'command', shell: 'powershell', command: event === 'PostToolUse' ? cmds.toolCommand : cmds.command, timeout: 10, async: true }
  },

  /** 우리 항목을 지금 형식으로 (예전 형식은 지우고 새로). 이미 최신이면 그대로. 다른 훅은 건드리지 않는다 */
  install(text: string | undefined, cmds: ClaudeHookCommands): string {
    const root = parseSettings(text)
    const hooks = (typeof root.hooks === 'object' && root.hooks !== null ? root.hooks : {}) as Json
    for (const event of CLAUDE_EVENTS) {
      const want = ClaudeHooks.entry(event, cmds)
      if (isCurrent(hooks[event], want)) continue
      const groups = withoutOurs(hooks[event])
      hooks[event] = [...groups, { hooks: [want] }]
    }
    root.hooks = hooks
    return JSON.stringify(root, null, 2) + '\n'
  },

  uninstall(text: string): string {
    const root = parseSettings(text)
    const hooks = root.hooks as Json | undefined
    if (typeof hooks !== 'object' || hooks === null) return text
    for (const event of CLAUDE_EVENTS) {
      if (!Array.isArray(hooks[event])) continue
      const cleaned = withoutOurs(hooks[event])
      if (cleaned.length) hooks[event] = cleaned
      else delete hooks[event]
    }
    return JSON.stringify(root, null, 2) + '\n'
  },
}

// MARK: - Claude 데스크톱 앱 일반 채팅 (%APPDATA%\Claude\claude_desktop_config.json → mcpServers.termpet)
// 공식 문서(modelcontextprotocol.io/docs/develop/connect-local-servers) 형식:
//   { "mcpServers": { "termpet": { "command": "<TermPet.exe>", "args": ["<termpet-mcp.js>"], "env": { "ELECTRON_RUN_AS_NODE": "1" } } } }
// 우리 항목(termpet) 하나만 넣고 빼고, 다른 MCP 서버와 설정은 그대로. Claude 앱을 완전히 껐다 켜야 적용.

export const MCP_SERVER_KEY = 'termpet'

export interface McpLaunch {
  /** TermPet.exe (Node 로 동작시킬 Electron 실행 파일) */
  command: string
  /** ~/.termpet/bin/termpet-mcp.js */
  script: string
}

const mcpServersOf = (root: Json): Json => (typeof root.mcpServers === 'object' && root.mcpServers !== null && !Array.isArray(root.mcpServers) ? (root.mcpServers as Json) : {})

export const ClaudeDesktop = {
  entry(l: McpLaunch): Json {
    return { command: l.command, args: [l.script], env: { ELECTRON_RUN_AS_NODE: '1' } }
  },

  isInstalled(text: string | undefined): boolean {
    try {
      return typeof mcpServersOf(parseSettings(text))[MCP_SERVER_KEY] === 'object'
    } catch {
      return false
    }
  },

  /** 연결은 돼 있는데 실행 경로가 지금 앱과 다르면 (설치 위치가 바뀜) */
  needsUpdate(text: string | undefined, l: McpLaunch): boolean {
    try {
      const ours = mcpServersOf(parseSettings(text))[MCP_SERVER_KEY] as Json | undefined
      if (!ours) return false
      return JSON.stringify(ours) !== JSON.stringify(ClaudeDesktop.entry(l))
    } catch {
      return false
    }
  },

  install(text: string | undefined, l: McpLaunch): string {
    const root = parseSettings(text)
    root.mcpServers = { ...mcpServersOf(root), [MCP_SERVER_KEY]: ClaudeDesktop.entry(l) }
    return JSON.stringify(root, null, 2) + '\n'
  },

  uninstall(text: string): string {
    const root = parseSettings(text)
    const servers = mcpServersOf(root)
    if (!(MCP_SERVER_KEY in servers)) return text
    delete servers[MCP_SERVER_KEY]
    root.mcpServers = servers
    return JSON.stringify(root, null, 2) + '\n'
  },
}

/** 이 이벤트에 우리 항목이 정확히 하나 있고 지금 형식과 같은지 */
function isCurrent(groups: unknown, want: Json): boolean {
  if (!Array.isArray(groups)) return false
  const ours = groups.flatMap((g) => groupHooks(g).filter(isOurs)) as Json[]
  return ours.length === 1 && Object.keys(want).every((k) => ours[0][k] === want[k]) && Object.keys(ours[0]).length === Object.keys(want).length
}

/** 그룹들에서 우리 항목만 뺀다 (비게 된 그룹은 없앤다) */
function withoutOurs(groups: unknown): unknown[] {
  if (!Array.isArray(groups)) return []
  return groups.flatMap((g) => {
    if (!Array.isArray((g as Json)?.hooks)) return [g]
    const kept = groupHooks(g).filter((h) => !isOurs(h))
    return kept.length ? [{ ...(g as Json), hooks: kept }] : []
  })
}

/**
 * 훅을 막는 설정 찾기 (사용자·관리자 settings.json). 막혀 있으면 이유, 아니면 undefined.
 * 공식 문서: disableAllHooks(모든 훅 끔), allowManagedHooksOnly / strictPluginOnlyCustomization(관리자 훅만 허용)
 */
export function hooksBlockedBy(userText: string | undefined, managedText: string | undefined): string | undefined {
  const read = (t: string | undefined): Json => {
    try {
      return parseSettings(t)
    } catch {
      return {}
    }
  }
  const managed = read(managedText)
  const user = read(userText)
  if (managed.disableAllHooks === true) return '회사(관리자) 설정이 모든 훅을 꺼 두었어요 (disableAllHooks)'
  if (managed.allowManagedHooksOnly === true) return '회사(관리자) 설정이 관리자 훅만 허용해요 (allowManagedHooksOnly)'
  if (managed.strictPluginOnlyCustomization === true) return '회사(관리자) 설정이 플러그인 훅만 허용해요 (strictPluginOnlyCustomization)'
  if (user.disableAllHooks === true) return '~/.claude/settings.json 에 "disableAllHooks": true 가 있어요. 지우거나 false 로 바꿔 주세요'
  return undefined
}

/** `Get-ExecutionPolicy` 결과 → 프로필 스크립트가 막히는지 (Restricted · AllSigned · Undefined(=클라이언트 기본 Restricted)) */
export function executionPolicyBlocksProfile(output: string): boolean {
  const p = output.trim().split(/\r?\n/).pop()?.trim().toLowerCase() ?? ''
  return p === 'restricted' || p === 'allsigned' || p === 'undefined'
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
