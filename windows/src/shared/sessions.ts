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

export function sessionKey(e: PetEvent): string | undefined {
  if (!e.sessionId) return undefined
  if (e.terminal) return `${e.source}:tty:${e.terminal}`
  return `${e.source}:${e.sessionId}`
}

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

    let state: SessionState
    if (e.kind === 'working') state = 'working'
    else if (e.kind === 'done') state = 'done'
    else if (e.kind === 'error') state = 'error'
    else state = isIdlePrompt(e) ? (prev?.state ?? 'done') : 'waiting' // idle_prompt 는 권한 대기가 아님

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

  /** 오래된 세션 정리. 바뀐 게 있으면 true */
  prune(now = Date.now()): boolean {
    let changed = false
    for (const [k, s] of this.sessions) {
      const age = now - s.lastSeen
      const keep = s.state === 'working' || s.state === 'waiting' ? age < STALE_AFTER : age < KEEP_FINISHED_FOR
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
