// 진행 중인 AI 세션 상태 (맥 앱 SessionTracker.swift 이식). React 비유: Record<key, Session>을 갱신하는 reducer.
//  UserPromptSubmit / PostToolUse → 작업 중, Notification → 권한 대기, Stop → 끝남, StopFailure → 에러, SessionEnd → 제거
import { isIdlePrompt, projectName, type EventSource, type PetEvent } from './events'

export type SessionState = 'working' | 'waiting' | 'done' | 'error'

export interface Session {
  id: string
  source: EventSource
  projectName?: string
  state: SessionState
  /** 지금 상태가 시작된 시각 (ms) */
  since: number
  lastSeen: number
  /** 클릭 시 프로젝트로 이동하기 위한 정보 */
  focusEvent: PetEvent
}

export const STALE_AFTER = 15 * 60_000
export const KEEP_FINISHED_FOR = 10 * 60_000
/** Claude 앱 채팅은 Claude가 끝 신호를 빠뜨릴 수 있어서 "답변 중"을 더 빨리 지운다 (termpet-mcp.js 의 sessionId) */
export const CLAUDE_CHAT_SESSION = 'claude-app-chat'
export const CLAUDE_CHAT_STALE_AFTER = 5 * 60_000
export const CHAT_SHADOW_WINDOW = 2 * 60_000

export function sessionKey(e: PetEvent): string | undefined {
  if (!e.sessionId) return undefined
  if (e.terminal) return `${e.source}:tty:${e.terminal}`
  return `${e.source}:${e.sessionId}`
}

/**
 * idle_prompt 리마인더를 알림으로 띄울 필요가 없는지. previous = apply 가 돌려준 이전 상태.
 * 끝났다는 알림은 Stop 때 이미 했으므로, 끝 신호를 놓쳐 아직 "작업 중"으로 알고 있던 때만 알린다
 * (예전엔 완료 말풍선을 확인한 뒤에도 60초 뒤 "입력을 기다리고 있어요" 말풍선과 "!"가 매번 다시 떴다)
 */
export const isRedundantIdlePrompt = (e: PetEvent, previous: SessionState | undefined) => isIdlePrompt(e) && previous !== 'working'

export class SessionTracker {
  sessions = new Map<string, Session>()

  /** 이벤트 반영. 반환값: 이 세션의 이전 상태 */
  apply(e: PetEvent, now = Date.now()): SessionState | undefined {
    const key = sessionKey(e)
    if (!key) return undefined
    const prev = this.sessions.get(key)

    if (e.kind === 'ended') {
      // 같은 터미널에서 이미 새 대화가 시작됐다면 지우지 않는다
      if (prev && prev.focusEvent.sessionId !== e.sessionId && e.terminal) return prev.state
      this.sessions.delete(key)
      return prev?.state
    }

    // idle_prompt = Claude가 끝난 지 60초 뒤 보내는 "입력 기다리는 중" 리마인더.
    // 모르는 세션이면(끝난 뒤 닫힌 대화, /clear 직후 등) 목록에 새로 만들지 않는다
    if (isIdlePrompt(e) && !prev) return undefined

    let state: SessionState
    if (e.kind === 'working') state = 'working'
    else if (e.kind === 'done') state = 'done'
    else if (e.kind === 'error') state = 'error'
    // idle_prompt 는 권한 대기가 아님. "작업 중"이었다면 끝 신호(Stop)를 놓친 것이니 끝난 것으로 고친다
    else if (isIdlePrompt(e)) state = prev?.state === 'working' ? 'done' : (prev?.state ?? 'done')
    else state = 'waiting'

    const focus: PetEvent = { ...e }
    if (prev) {
      focus.cwd = e.cwd ?? prev.focusEvent.cwd
      focus.host = e.host ?? prev.focusEvent.host
      focus.termProgram = e.termProgram ?? prev.focusEvent.termProgram
    }
    this.sessions.set(key, {
      id: key,
      source: e.source,
      projectName: projectName(focus) ?? prev?.projectName,
      state,
      since: prev?.state === state ? prev.since : now,
      lastSeen: now,
      focusEvent: focus,
    })
    return prev?.state
  }

  stateOf(e: PetEvent): SessionState | undefined {
    const k = sessionKey(e)
    return k ? this.sessions.get(k)?.state : undefined
  }

  /**
   * Claude 앱 Code 탭(= Claude Code)은 훅 신호가 오는데, Claude가 텀펫 MCP 도구까지 불러 "Claude 채팅" 알림이 한 번 더 올 수 있다
   * → Claude 앱(claude.exe)에서 돌고 있는 Claude Code 세션이 작업 중이면 MCP 신호는 버린다 (맥 SessionTracker 와 같은 규칙)
   */
  isDuplicateChatSignal(e: PetEvent, now = Date.now()): boolean {
    if (e.sessionId !== CLAUDE_CHAT_SESSION) return false
    for (const s of this.sessions.values()) {
      if (s.source === 'claude' && s.focusEvent.sessionId !== CLAUDE_CHAT_SESSION && s.focusEvent.host?.toLowerCase() === 'claude.exe'
        && s.state === 'working' && now - s.lastSeen < CHAT_SHADOW_WINDOW) return true
    }
    return false
  }

  /** 오래된 세션 정리. 바뀐 게 있으면 true */
  prune(now = Date.now()): boolean {
    let changed = false
    for (const [k, s] of this.sessions) {
      const age = now - s.lastSeen
      const stale = s.focusEvent.sessionId === CLAUDE_CHAT_SESSION ? CLAUDE_CHAT_STALE_AFTER : STALE_AFTER
      const keep = s.state === 'working' || s.state === 'waiting' ? age < stale : age < KEEP_FINISHED_FOR
      if (!keep) {
        this.sessions.delete(k)
        changed = true
      }
    }
    return changed
  }

  /** 표시 순서: 권한 대기 → 작업 중 → 에러 → 끝남, 같은 상태끼리는 최근 순 */
  get ordered(): Session[] {
    const rank: Record<SessionState, number> = { waiting: 0, working: 1, error: 2, done: 3 }
    return [...this.sessions.values()].sort((a, b) => rank[a.state] - rank[b.state] || b.lastSeen - a.lastSeen)
  }

  count(state: SessionState): number {
    return [...this.sessions.values()].filter((s) => s.state === state).length
  }
}

/** 펫 머리 위 표시 (우선순위: 권한 대기 > 미확인 알림 > 작업 중) */
export type PetBadge = { type: 'none' } | { type: 'unread' } | { type: 'working'; count: number } | { type: 'waiting'; count: number }

export function pickBadge(waiting: number, working: number, hasUnread: boolean): PetBadge {
  if (waiting > 0) return { type: 'waiting', count: waiting }
  if (hasUnread) return { type: 'unread' }
  if (working > 0) return { type: 'working', count: working }
  return { type: 'none' }
}
