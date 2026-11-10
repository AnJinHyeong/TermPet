// 외부 이벤트(Claude Code 훅 / Codex notify / 쉘) → 앱 표준 PetEvent. 맥 앱 PetEvent.swift · EventDecoder.swift 이식.
// 외부 형식이 바뀌어도 죽지 않게 모든 필드를 방어적으로 읽는다 (zod 대신 손으로 typeof 검사).
import type { PetAction } from './characterPack'

export type EventSource = 'claude' | 'codex' | 'shell'
/** done/error/ask = 말풍선 알림. working/ended = 진행 상황 신호 (머리 위 표시만) */
export type EventKind = 'done' | 'error' | 'ask' | 'working' | 'ended'

export interface PetEvent {
  id: string
  source: EventSource
  kind: EventKind
  /** 말풍선에 그대로 표시할 문구 (없으면 캐릭터 문구) */
  message?: string
  /** 보조 설명 (마지막 답변 첫 줄, 쉘 명령어) */
  detail?: string
  cwd?: string
  sessionId?: string
  transcriptPath?: string
  command?: string
  exitCode?: number
  durationSec?: number
  /** 호스트 앱 식별자. 윈도우: 에디터 exe 경로(VSCODE_GIT_ASKPASS_NODE) 또는 'WindowsTerminal' 등 */
  host?: string
  /** TERM_PROGRAM 환경변수 (vscode, WezTerm …) */
  termProgram?: string
  /** Claude Code Notification 훅의 notification_type */
  notificationType?: string
  /** 같은 터미널의 세션을 한 줄로 합치기 위한 터미널 id (윈도우: WT_SESSION) */
  terminal?: string
  receivedAt: number
}

/** 요청 메타데이터 (훅 스크립트가 HTTP 헤더로 보냄) */
export interface DecodeContext {
  host?: string
  termProgram?: string
  terminal?: string
}

export class DecodeError extends Error {
  /** ignored = 받았지만 알림으로 보여줄 필요가 없음 (200으로 답함) */
  constructor(
    message: string,
    readonly ignored = false,
  ) {
    super(message)
  }
}

let counter = 0
export function makeEvent(fields: Omit<PetEvent, 'id' | 'receivedAt'> & Partial<Pick<PetEvent, 'id' | 'receivedAt'>>): PetEvent {
  return { id: `e${Date.now()}-${++counter}`, receivedAt: Date.now(), ...fields }
}

/** cwd의 마지막 폴더명 = 프로젝트 이름 (윈도우 \ 와 / 모두) */
export function projectName(e: Pick<PetEvent, 'cwd'>): string | undefined {
  if (!e.cwd) return undefined
  const parts = e.cwd.split(/[\\/]+/).filter(Boolean)
  const name = parts[parts.length - 1]
  return !name || /^[A-Za-z]:$/.test(name) ? undefined : name
}

export const isIdlePrompt = (e: PetEvent) => e.notificationType === 'idle_prompt'
export const isNotification = (e: PetEvent) => e.kind === 'done' || e.kind === 'error' || e.kind === 'ask'

export function moodOf(e: PetEvent): PetAction {
  switch (e.kind) {
    case 'done':
      return 'happy'
    case 'error':
      return 'angry'
    case 'ask':
      return 'ask'
    default:
      return 'idle'
  }
}

// MARK: - 방어적 읽기

type Obj = Record<string, unknown>

function parseObject(body: string): Obj {
  let v: unknown
  try {
    v = JSON.parse(body)
  } catch {
    throw new DecodeError('invalid JSON')
  }
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw new DecodeError('invalid JSON')
  return v as Obj
}
const str = (o: Obj, k: string) => (typeof o[k] === 'string' && o[k] !== '' ? (o[k] as string) : undefined)
function num(o: Obj, k: string): number | undefined {
  const v = o[k]
  if (typeof v === 'number' && Number.isFinite(v)) return v
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v)
  return undefined
}
const nonEmpty = (s: string | undefined) => (s && s.trim() ? s.trim() : undefined)

/** 여러 줄 → 첫 번째 내용 있는 줄, 마크다운 기호 제거, 최대 120자 */
export function oneLine(text: string): string {
  const line =
    text
      .split(/\r?\n/)
      .map((l) => l.trim())
      .find((l) => l) ?? ''
  const cleaned = line.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '').replace(/^[#*\-> ]+|[#*\-> ]+$/g, '')
  return [...cleaned].length > 120 ? [...cleaned].slice(0, 119).join('') + '…' : cleaned
}

// MARK: - 표준 이벤트 (POST /event)

export function decodeStandard(body: string, ctx: DecodeContext = {}): PetEvent {
  const o = parseObject(body)
  const source = str(o, 'source')
  if (!source) throw new DecodeError('missing source')
  if (source !== 'claude' && source !== 'codex' && source !== 'shell') throw new DecodeError('invalid source')
  const exitCode = num(o, 'exitCode')
  let kind: EventKind
  const kindRaw = str(o, 'kind')
  if (kindRaw) {
    if (!['done', 'error', 'ask', 'working', 'ended'].includes(kindRaw)) throw new DecodeError('invalid kind')
    kind = kindRaw as EventKind
  } else if (exitCode !== undefined) {
    kind = exitCode === 0 ? 'done' : 'error'
  } else {
    throw new DecodeError('missing kind')
  }
  const command = str(o, 'command')
  return makeEvent({
    source,
    kind,
    message: str(o, 'message'),
    detail: str(o, 'detail') ?? (command ? oneLine(command) : undefined),
    cwd: str(o, 'cwd'),
    sessionId: str(o, 'sessionId'),
    transcriptPath: str(o, 'transcriptPath'),
    command,
    exitCode,
    durationSec: num(o, 'durationSec'),
    host: str(o, 'host') ?? str(o, 'hostBundleId') ?? ctx.host,
    termProgram: str(o, 'termProgram') ?? ctx.termProgram,
    terminal: ctx.terminal,
  })
}

// MARK: - Claude Code 훅 원본 (POST /hook/claude)

/** 공식 문서(https://code.claude.com/docs/en/hooks) 기준 공통 필드: session_id, transcript_path, cwd, hook_event_name */
export function decodeClaudeHook(body: string, ctx: DecodeContext = {}): PetEvent {
  const o = parseObject(body)
  const name = str(o, 'hook_event_name') ?? ''
  const e = makeEvent({
    source: 'claude',
    kind: 'done',
    cwd: str(o, 'cwd'),
    sessionId: str(o, 'session_id'),
    transcriptPath: str(o, 'transcript_path'),
    host: ctx.host,
    termProgram: ctx.termProgram,
    terminal: ctx.terminal,
  })
  switch (name) {
    case 'Stop': {
      const last = str(o, 'last_assistant_message')
      e.detail = last ? nonEmpty(oneLine(last)) : undefined
      break
    }
    case 'Notification': {
      const type = str(o, 'notification_type')
      e.notificationType = type
      if (type === undefined || ['permission_prompt', 'idle_prompt', 'elicitation_dialog', 'elicitation_url_dialog', 'agent_needs_input'].includes(type)) {
        e.kind = 'ask'
      } else if (type === 'agent_completed') {
        e.kind = 'done'
      } else {
        throw new DecodeError(`notification_type=${type}`, true) // auth_success 등은 행동 불필요
      }
      e.message = koreanNotification(nonEmpty(str(o, 'message')), type)
      break
    }
    case 'StopFailure':
      e.kind = 'error'
      e.message = nonEmpty(str(o, 'error'))
      break
    case 'UserPromptSubmit':
      e.kind = 'working'
      break
    case 'PreToolUse':
    case 'PostToolUse':
      e.kind = 'working'
      e.detail = str(o, 'tool_name')
      break
    case 'SessionEnd':
      e.kind = 'ended'
      break
    default:
      // TODO: 다른 훅 이벤트(SubagentStop 등)를 연결하게 되면 추가
      throw new DecodeError(`hook_event_name=${name}`, true)
  }
  return e
}

/**
 * PostToolUse 입력(POST /hook/claude-tool)에는 도구 결과(수 MB 가능)가 통째로 들어 있다.
 * 윈도우 훅(.cmd)은 jq도 문자열 처리도 어려워서 원본을 그대로 보내고, 앱이 앞부분에서 session_id·cwd만 뽑는다.
 * 공통 필드는 맨 앞쪽에 오므로 첫 4KB만 본다.
 */
export function decodeClaudeTool(head: string, ctx: DecodeContext = {}): PetEvent {
  const text = head.slice(0, 4096)
  const field = (k: string) => {
    const m = new RegExp(`"${k}"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`).exec(text)
    if (!m) return undefined
    try {
      return JSON.parse(`"${m[1]}"`) as string // \\ 이스케이프 풀기 (윈도우 경로)
    } catch {
      return m[1]
    }
  }
  const sessionId = field('session_id')
  if (!sessionId) throw new DecodeError('missing session_id', true)
  return makeEvent({
    source: 'claude',
    kind: 'working',
    cwd: field('cwd'),
    sessionId,
    detail: field('tool_name'),
    host: ctx.host,
    termProgram: ctx.termProgram,
    terminal: ctx.terminal,
  })
}

/** Claude Code 알림(영어) → 한국어. 이미 한국어면 그대로, 원문이 없으면 undefined */
export function koreanNotification(message: string | undefined, type: string | undefined): string | undefined {
  if (message === undefined) return undefined
  if (/[가-힣]/.test(message)) return message
  const text = message.trim()
  const lower = text.toLowerCase()
  const usePrefix = 'claude needs your permission to use '
  if (lower.startsWith(usePrefix)) {
    const tool = text.slice(usePrefix.length).replace(/^[ .]+|[ .]+$/g, '')
    return tool ? `${tool} 사용을 허락해 줄래요?` : '권한 확인이 필요해요'
  }
  if (lower.includes('permission')) return '권한 확인이 필요해요'
  if (lower.includes('waiting for your input') || lower.includes('waiting for input')) return '입력을 기다리고 있어요'
  if (lower.includes('needs your attention')) return '확인이 필요해요'
  switch (type) {
    case 'permission_prompt':
      return '권한 확인이 필요해요'
    case 'idle_prompt':
      return '입력을 기다리고 있어요'
    case 'elicitation_dialog':
      return '선택해 줄 게 있어요'
    case 'elicitation_url_dialog':
      return '링크에서 확인해 줄 게 있어요'
    case 'agent_needs_input':
      return '입력이 필요해요'
    case 'agent_completed':
      return '작업이 끝났어요'
    default:
      return message
  }
}

// MARK: - Codex notify (POST /hook/codex)

/** TODO: Codex 문서 기준 {"type":"agent-turn-complete", "last-assistant-message", "cwd", "thread-id"} — 그 외는 무시 */
export function decodeCodexNotify(body: string, ctx: DecodeContext = {}): PetEvent {
  const o = parseObject(body)
  const type = str(o, 'type') ?? ''
  if (type !== 'agent-turn-complete') throw new DecodeError(`type=${type}`, true)
  const last = str(o, 'last-assistant-message')
  return makeEvent({
    source: 'codex',
    kind: 'done',
    detail: last ? nonEmpty(oneLine(last)) : undefined,
    cwd: str(o, 'cwd'),
    sessionId: str(o, 'thread-id') ?? str(o, 'session-id'),
    host: ctx.host,
    termProgram: ctx.termProgram,
    terminal: ctx.terminal,
  })
}
