// "GPT 앱 채팅": ChatGPT(Codex) 데스크톱 앱 로그 한 줄 → 일반 GPT 채팅 신호. 순수 로직 (맥 ChatGPTAppLog.swift 대응).
// 일반 채팅은 OpenAI 서버에서 돌아서 notify/훅이 없다. 앱이 자기 로그에 대화 갱신을 남기므로 그 줄을 읽는다.
// 로그 위치 (앱 코드 기준): 윈도우 %LOCALAPPDATA%\Codex\Logs\년\월\일 (UTC 날짜), 맥 ~/Library/Logs/com.openai.codex/…
// 공식 형식이 아니라서 앱이 업데이트되면 바뀔 수 있다 (그러면 조용히 알림이 안 올 뿐).
import { makeEvent, type PetEvent } from './events'

export type ChatGPTSignal = { type: 'started' | 'completed'; conversationId: string }

/** 이벤트의 host 값 (hostApp.resolveHost 가 ChatGPT 앱으로 알아본다) */
export const CHATGPT_HOST = 'ChatGPT'

export function parseChatGPTLogLine(line: string): ChatGPTSignal | undefined {
  const started = line.includes('Received turn/started')
  const completed =
    (line.includes('chatgpt_conversation_refetch_completed') && line.includes('reason=explicit_update')) ||
    (line.includes('chatgpt_conversation_update_ignored') && line.includes('updateType=completed')) ||
    line.includes('[desktop-notifications] show turn-complete')
  if (!started && !completed) return undefined
  const m = /conversationId=([0-9a-fA-F-]{36})/.exec(line)
  if (!m) return undefined
  const id = m[1].toLowerCase()
  if (isCodexThread(id)) return undefined // Codex 대화는 notify 가 알려 준다
  return { type: started ? 'started' : 'completed', conversationId: id }
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

export class ChatGPTReducer {
  private last = new Map<string, number>()

  event(signal: ChatGPTSignal, now = Date.now()): PetEvent | undefined {
    const kind = signal.type === 'started' ? 'working' : 'done'
    const key = `${kind}:${signal.conversationId}`
    const t = this.last.get(key)
    if (t !== undefined && now - t < DEDUPE_MS) return undefined
    if (this.last.size > 200) for (const [k, v] of this.last) if (now - v >= DEDUPE_MS) this.last.delete(k)
    this.last.set(key, now)
    return makeEvent({ source: 'codex', kind, sessionId: signal.conversationId, host: CHATGPT_HOST, title: 'ChatGPT', receivedAt: now })
  }
}
