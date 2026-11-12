// "GPT 앱 채팅": ChatGPT(Codex) 데스크톱 앱 로그 한 줄 → 일반 GPT 채팅 신호. 순수 로직 (맥 ChatGPTAppLog.swift 대응).
// 일반 채팅은 OpenAI 서버에서 돌아서 notify/훅이 없다. 앱이 자기 로그에 대화 갱신을 남기므로 그 줄을 읽는다.
// 로그 위치 (앱 코드 기준): 윈도우 %LOCALAPPDATA%\Codex\Logs\년\월\일 (UTC 날짜), 맥 ~/Library/Logs/com.openai.codex/…
// 공식 형식이 아니라서 앱이 업데이트되면 바뀔 수 있다 (그러면 조용히 알림이 안 올 뿐).
import { makeEvent, type PetEvent } from './events'

// 주의: `update_ignored … conversation_not_loaded` 는 "이 앱 창에 안 열려 있는 대화"의 서버 소식이라 휴대폰·웹에서 한 대화가
// 끝났을 때도 똑같이 찍힌다 (PC 에선 아무것도 안 물었는데 알림이 반복) → 이 앱에서 최근에 연 적이 있는 대화(seen)일 때만 알린다.
/** completedElsewhere = 이 앱 창에 안 열린 대화가 끝났다는 서버 소식, seen = 이 앱에서 그 대화를 열었거나 갱신함 (알림 아님) */
export type ChatGPTSignal = { type: 'started' | 'completed' | 'completedElsewhere' | 'seen'; conversationId: string }

/** 이벤트의 host 값 (hostApp.resolveHost 가 ChatGPT 앱으로 알아본다) */
export const CHATGPT_HOST = 'ChatGPT'

export function parseChatGPTLogLine(line: string): ChatGPTSignal | undefined {
  const ignoredUpdate = line.includes('chatgpt_conversation_update_ignored')
  const started = line.includes('Received turn/started')
  const completed =
    (line.includes('chatgpt_conversation_refetch_completed') && line.includes('reason=explicit_update')) ||
    line.includes('[desktop-notifications] show turn-complete')
  const elsewhere = ignoredUpdate && line.includes('updateType=completed')
  // conversationId=<uuid> 또는 대화 주소 /c/<uuid> (앱에서 그 대화를 열면 찍힌다)
  const m = /(?:conversationId=|\/c\/)([0-9a-fA-F-]{36})/.exec(line)
  if (!m) return undefined
  const id = m[1].toLowerCase()
  if (isCodexThread(id)) return undefined // Codex 대화는 notify 가 알려 준다
  if (started) return { type: 'started', conversationId: id }
  if (completed) return { type: 'completed', conversationId: id }
  if (elsewhere) return { type: 'completedElsewhere', conversationId: id }
  // 서버가 밀어 준 소식(update_ignored)·놓친 메시지 따라잡기(missed_messages)는 다른 기기에서 한 대화에도 찍힌다 → 연 것으로 안 친다
  if (ignoredUpdate || line.includes('reason=missed_messages')) return undefined
  return { type: 'seen', conversationId: id }
}

/** Codex 스레드 ID = UUID 버전 7 (세 번째 묶음이 7로 시작). 일반 채팅 ID 는 아니다 (예: 6af42003-045c-83ee-…) */
export function isCodexThread(id: string): boolean {
  const parts = id.split('-')
  return parts.length === 5 && parts[2].startsWith('7')
}

/** 날짜 폴더 (UTC) — 예: <root>/2026/11/11 */
export function dayFolder(root: string, date: Date, sep = '/'): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return [root, String(date.getUTCFullYear()), p(date.getUTCMonth() + 1), p(date.getUTCDate())].join(sep)
}

/** 한 대화의 완료 신호가 여러 줄(갱신 + 앱 알림)로 오므로 이 시간 안의 같은 신호는 한 번만 */
export const DEDUPE_MS = 20_000

/** 이 앱에서 대화를 연 뒤 이 시간 안에 온 "안 열린 대화 완료" 소식만 알린다 (물어 놓고 다른 대화로 넘어간 경우) */
export const LOCAL_WINDOW_MS = 30 * 60_000

export class ChatGPTReducer {
  private last = new Map<string, number>()
  /** 이 앱에서 열었던 대화 → 마지막으로 본 시각 */
  private seen = new Map<string, number>()

  event(signal: ChatGPTSignal, now = Date.now()): PetEvent | undefined {
    if (signal.type === 'seen') {
      if (this.seen.size > 200) for (const [k, v] of this.seen) if (now - v >= LOCAL_WINDOW_MS) this.seen.delete(k)
      this.seen.set(signal.conversationId, now)
      return undefined
    }
    if (signal.type === 'completedElsewhere') {
      // 이 앱에서 연 적 없는 대화 = 다른 기기에서 한 대화 → 알리지 않는다
      const t = this.seen.get(signal.conversationId)
      if (t === undefined || now - t >= LOCAL_WINDOW_MS) return undefined
    } else {
      this.seen.set(signal.conversationId, now)
    }
    const kind = signal.type === 'started' ? 'working' : 'done'
    const key = `${kind}:${signal.conversationId}`
    const t = this.last.get(key)
    if (t !== undefined && now - t < DEDUPE_MS) return undefined
    if (this.last.size > 200) for (const [k, v] of this.last) if (now - v >= DEDUPE_MS) this.last.delete(k)
    this.last.set(key, now)
    return makeEvent({ source: 'codex', kind, sessionId: signal.conversationId, host: CHATGPT_HOST, title: 'ChatGPT', receivedAt: now })
  }
}
