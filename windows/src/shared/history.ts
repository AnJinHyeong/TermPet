// 최근 알림 기록 (맥 NotificationHistory.swift 이식). 말풍선을 놓쳐도 패널 "최근 알림"에서 다시 보고 그 창으로 갈 수 있게.
// React 비유: 새 항목을 앞에 붙이고 길이를 자르는 reducer — [item, ...prev].slice(0, max)
import { isIdlePrompt, isNotification, type PetEvent } from './events'
import type { BubbleContent } from './notifications'

export interface HistoryEntry {
  id: string
  event: PetEvent
  title: string
  body: string
  date: number
}

export const HISTORY_MAX = 30

export class NotificationHistory {
  /** 최신이 맨 앞 */
  entries: HistoryEntry[] = []

  /**
   * 알림 하나 기록. 진행 신호(작업 중 등)·"입력 기다리는 중" 리마인더는 기록하지 않는다.
   * 같은 세션의 이전 권한 요청은 새 알림으로 대체한다 (승인했거나 끝났으니 의미 없음).
   */
  record(e: PetEvent, content: BubbleContent) {
    if (!isNotification(e) || isIdlePrompt(e)) return
    if (e.sessionId) {
      this.entries = this.entries.filter((x) => !(x.event.sessionId === e.sessionId && x.event.source === e.source && x.event.kind === 'ask'))
    }
    this.entries.unshift({ id: e.id, event: e, title: content.title, body: content.body, date: e.receivedAt })
    if (this.entries.length > HISTORY_MAX) this.entries.length = HISTORY_MAX
  }

  clear() {
    this.entries = []
  }
}

/** "방금" / "3분 전" / "2시간 전" (맥 RecentRow 와 같은 규칙) */
export function timeAgo(ms: number): string {
  const s = Math.max(0, ms / 1000)
  if (s < 60) return '방금'
  if (s < 3600) return `${Math.floor(s / 60)}분 전`
  return `${Math.floor(s / 3600)}시간 전`
}
