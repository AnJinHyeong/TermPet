// 말풍선 내용·알림 큐·하루 기록·기분 (맥 앱 BubbleMessages / NotificationQueue / DailyStats 이식). 순수 로직.
import type { Random } from './brain'
import { isIdlePrompt, isNotification, oneLine, projectName, type EventKind, type EventSource, type PetEvent } from './events'

// MARK: - 말풍선 문구

export interface BubbleMessages {
  done: string[]
  error: string[]
  ask: string[]
}

export const defaultMessages: BubbleMessages = {
  done: ['끝났어!', '작업 완료~', '다 됐어!'],
  error: ['에러 났어…', '빨간 줄 떴어!', '뭔가 잘못됐어!'],
  ask: ['확인해줘!', '허락이 필요해', '나 좀 봐줘!'],
}

/** 캐릭터 팩 messages → 빈 목록은 기본 문구로 */
export function packMessages(m?: Partial<BubbleMessages>): BubbleMessages {
  const pick = (list: string[] | undefined, fb: string[]) => {
    const cleaned = (list ?? []).filter((s) => typeof s === 'string' && s)
    return cleaned.length ? cleaned : fb
  }
  return { done: pick(m?.done, defaultMessages.done), error: pick(m?.error, defaultMessages.error), ask: pick(m?.ask, defaultMessages.ask) }
}

export interface BubbleContent {
  /** 상단 작은 글씨: 프로젝트 이름 */
  title: string
  body: string
  detail?: string
}

export function sourceLabel(s: EventSource): string {
  return s === 'claude' ? 'Claude Code' : s === 'codex' ? 'Codex' : '터미널'
}

/** 42 → "42초", 125 → "2분 5초", 3700 → "1시간 1분" */
export function formatDuration(seconds: number): string {
  const s = Math.round(seconds)
  if (s < 60) return `${s}초`
  if (s < 3600) return s % 60 === 0 ? `${Math.floor(s / 60)}분` : `${Math.floor(s / 60)}분 ${s % 60}초`
  const m = Math.floor((s % 3600) / 60)
  return m === 0 ? `${Math.floor(s / 3600)}시간` : `${Math.floor(s / 3600)}시간 ${m}분`
}

function pool(m: BubbleMessages, kind: EventKind): string[] {
  return kind === 'done' ? m.done : kind === 'error' ? m.error : kind === 'ask' ? m.ask : []
}

export function makeContent(e: PetEvent, messages: BubbleMessages, rng: Random): BubbleContent {
  const list = pool(messages, e.kind)
  const body = e.message ?? (list.length ? list[Math.floor(rng() * list.length)] : '!')
  let detail = e.detail
  if (e.source === 'shell' && e.durationSec !== undefined) {
    const time = formatDuration(e.durationSec)
    detail = detail ? `${detail} · ${time}` : time
  }
  return { title: projectName(e) ?? sourceLabel(e.source), body, detail }
}

// MARK: - 알림 큐

export interface PetNotification {
  id: string
  event: PetEvent
  content: BubbleContent
}

/** 미확인 알림 큐. 맨 앞(current) = 지금 말풍선. 같은 세션 알림은 교체 */
export class NotificationQueue {
  static readonly maxItems = 20
  items: PetNotification[] = []

  get current() {
    return this.items[0]
  }
  get pendingCount() {
    return Math.max(0, this.items.length - 1)
  }
  get isEmpty() {
    return this.items.length === 0
  }

  push(n: PetNotification): 'added' | 'replaced' | 'ignored' {
    const e = n.event
    if (e.sessionId) {
      const i = this.items.findIndex((x) => x.event.sessionId === e.sessionId && x.event.source === e.source)
      if (i >= 0) {
        if (isIdlePrompt(e)) return 'ignored' // 이미 미확인 알림이 있는데 "아직 기다리는 중" 리마인더
        this.items[i] = n
        return 'replaced'
      }
    }
    this.items.push(n)
    if (this.items.length > NotificationQueue.maxItems) this.items.splice(0, this.items.length - NotificationQueue.maxItems)
    return 'added'
  }

  popCurrent(): PetNotification | undefined {
    return this.items.shift()
  }

  removeAll() {
    this.items = []
  }

  /** 이 세션의 알림을 모두 치운다. 반환값: 지금 보이던 알림이 지워졌는지 */
  removeSession(e: PetEvent): boolean {
    if (!e.sessionId) return false
    const currentId = this.current?.id
    this.items = this.items.filter((x) => !(x.event.sessionId === e.sessionId && x.event.source === e.source))
    return currentId !== undefined && this.current?.id !== currentId
  }
}

/** 권한 요청처럼 답해야 끝나는 알림은 자동으로 숨기지 않는다 */
export const isSticky = (e: PetEvent) => e.kind === 'ask' && !isIdlePrompt(e) && e.sessionId !== undefined

// MARK: - 하루 기록

export interface DailyStats {
  day: string
  aiDone: number
  shellDone: number
  errors: number
  asks: number
  longestCommand?: string
  longestSeconds: number
}

export function dayKey(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

export const emptyStats = (day: string): DailyStats => ({ day, aiDone: 0, shellDone: 0, errors: 0, asks: 0, longestSeconds: 0 })

/** 날짜가 지났으면 빈 기록 */
export function currentStats(s: DailyStats | undefined, now = new Date()): DailyStats {
  const today = dayKey(now)
  return s && s.day === today ? s : emptyStats(today)
}

export function recordStats(s: DailyStats | undefined, e: PetEvent, now = new Date()): DailyStats {
  const out = { ...currentStats(s, now) }
  if (!isNotification(e) || isIdlePrompt(e)) return out
  if (e.kind === 'done') {
    if (e.source === 'shell') out.shellDone++
    else out.aiDone++
  } else if (e.kind === 'error') out.errors++
  else if (e.kind === 'ask') out.asks++
  if (e.source === 'shell' && e.durationSec !== undefined && e.durationSec > out.longestSeconds) {
    out.longestSeconds = e.durationSec
    out.longestCommand = e.command ? oneLine(e.command) : undefined
  }
  return out
}

const total = (s: DailyStats) => s.aiDone + s.shellDone + s.errors

/** 펫을 눌렀을 때 하는 말 */
export function statsSpeech(s: DailyStats): BubbleContent {
  if (total(s) === 0 && s.asks === 0) return { title: '오늘', body: '오늘은 아직 한가해요', detail: '작업이 끝나면 알려줄게요' }
  const done = s.aiDone + s.shellDone
  const body = done === 0 ? '오늘은 아직 끝낸 일이 없어요' : `오늘 ${done}번 끝냈어요!`
  const parts: string[] = []
  if (s.aiDone) parts.push(`AI ${s.aiDone}`)
  if (s.shellDone) parts.push(`명령 ${s.shellDone}`)
  if (s.errors) parts.push(`에러 ${s.errors}`)
  if (s.asks) parts.push(`권한 요청 ${s.asks}`)
  let detail = parts.join(' · ')
  if (s.longestCommand && s.longestSeconds > 0) {
    detail += (detail ? '\n' : '') + `가장 오래: ${s.longestCommand} (${formatDuration(s.longestSeconds)})`
  }
  return { title: '오늘', body, detail: detail || undefined }
}

/** 패널 맨 위 한 줄 요약 */
export function statsSummary(s: DailyStats): string | undefined {
  if (total(s) === 0 && s.asks === 0) return undefined
  const parts = [`✓ ${s.aiDone + s.shellDone}`]
  if (s.errors) parts.push(`✗ ${s.errors}`)
  if (s.asks) parts.push(`✋ ${s.asks}`)
  if (s.longestSeconds > 0) parts.push(`가장 긴 명령 ${formatDuration(s.longestSeconds)}`)
  return parts.join(' · ')
}

// MARK: - 기분

export type PetMood = 'cheerful' | 'normal' | 'gloomy'
export const MOOD_WINDOW = 30 * 60_000

/** outcomes: [시각 ms, 성공 여부] 오래된 것부터 */
export function moodFrom(outcomes: [number, boolean][], now: number): PetMood {
  const recent = outcomes.filter(([t]) => now - t < MOOD_WINDOW)
  if (!recent.length) return 'normal'
  const errors = recent.filter(([, ok]) => !ok).length
  const successes = recent.length - errors
  const lastThree = recent.slice(-3)
  if (lastThree.filter(([, ok]) => !ok).length >= 2) return 'gloomy'
  if (errors === 0 && successes >= 3) return 'cheerful'
  if (lastThree.length === 3 && lastThree.every(([, ok]) => ok)) return 'cheerful'
  return 'normal'
}

export const walkFactor = (m: PetMood) => (m === 'cheerful' ? 1.25 : m === 'gloomy' ? 0.6 : 1)
