// 이벤트 해석·라우팅·세션·알림 큐·하루 기록 테스트 (맥 EventTests / ServerTests / SessionTrackerTests / BubbleTests 대응)
import { describe, expect, it } from 'vitest'
import { decodeClaudeHook, decodeClaudeTool, decodeCodexNotify, decodeStandard, koreanNotification, makeEvent, oneLine, projectName } from './events'
import { currentStats, formatDuration, makeContent, moodFrom, NotificationQueue, recordStats, statsSpeech, defaultMessages, packMessages } from './notifications'
import { constantTimeEquals, logLine, route } from './router'
import { isRedundantIdlePrompt, pickBadge, SessionTracker } from './sessions'

const TOKEN = 'a'.repeat(64)
const post = (path: string, body: object | string, headers: Record<string, string> = {}) =>
  route({ method: 'POST', path, headers: { 'x-termpet-token': TOKEN, ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body) }, TOKEN)

describe('router', () => {
  it('health 는 토큰 없이 200', () => {
    expect(route({ method: 'GET', path: '/health', headers: {}, body: '' }, TOKEN)).toEqual({ status: 200, body: 'ok' })
  })
  it('토큰 틀림 401, 브라우저(Origin) 403, 모르는 경로 404, GET 405', () => {
    expect(route({ method: 'POST', path: '/event', headers: { 'x-termpet-token': 'x' }, body: '{}' }, TOKEN).status).toBe(401)
    expect(post('/event', {}, { origin: 'http://evil' }).status).toBe(403)
    expect(post('/nope', {}).status).toBe(404)
    expect(route({ method: 'GET', path: '/event', headers: {}, body: '' }, TOKEN).status).toBe(405)
  })
  it('표준 이벤트 202 + 헤더의 호스트 정보', () => {
    const r = post('/event', { source: 'shell', exitCode: 1, command: 'npm run build', cwd: 'C:\\work\\fitin' }, {
      'x-termpet-host-exe': 'C:\\Users\\me\\AppData\\Local\\Programs\\cursor\\Cursor.exe',
      'x-termpet-term-program': 'vscode',
    })
    expect(r.status).toBe(202)
    expect(r.event?.kind).toBe('error')
    expect(r.event?.host).toContain('Cursor.exe')
    expect(r.event && projectName(r.event)).toBe('fitin')
  })
  it('무시할 이벤트는 200 ignored, 깨진 JSON 은 400', () => {
    expect(post('/hook/claude', { hook_event_name: 'Notification', notification_type: 'auth_success' }).status).toBe(200)
    expect(post('/hook/claude', '{oops').status).toBe(400)
  })
  it('Windows Terminal 세션은 터미널 키로', () => {
    const r = post('/hook/claude', { hook_event_name: 'Stop', session_id: 's1' }, { 'x-termpet-wt': 'abc-123' })
    expect(r.event?.host).toBe('WindowsTerminal')
    expect(r.event?.terminal).toBe('abc-123')
  })
  it('상수 시간 비교', () => {
    expect(constantTimeEquals('abc', 'abc')).toBe(true)
    expect(constantTimeEquals('abc', 'abd')).toBe(false)
    expect(constantTimeEquals('abc', 'ab')).toBe(false)
  })
  it('요청 기록 한 줄', () => {
    const e = makeEvent({ source: 'claude', kind: 'done', cwd: 'C:\\a\\proj', termProgram: 'vscode' })
    expect(logLine(new Date(2026, 10, 9, 11, 30, 2), 'POST', '/hook/claude', 202, 'accepted', e)).toBe(
      '2026-11-09 11:30:02  POST /hook/claude  202  claude/done  proj  host=vscode',
    )
  })
})

describe('Claude 훅 해석', () => {
  it('Stop → done, 마지막 답변 첫 줄', () => {
    const e = decodeClaudeHook(JSON.stringify({ hook_event_name: 'Stop', session_id: 's', cwd: '/x/y', last_assistant_message: '\n**완료했어요**\n둘째 줄' }))
    expect(e.kind).toBe('done')
    expect(e.detail).toBe('완료했어요')
  })
  it('Notification 권한 요청 → ask + 한국어', () => {
    const e = decodeClaudeHook(JSON.stringify({ hook_event_name: 'Notification', notification_type: 'permission_prompt', message: 'Claude needs your permission to use Bash' }))
    expect(e.kind).toBe('ask')
    expect(e.message).toBe('Bash 사용을 허락해 줄래요?')
  })
  it('진행 상황 신호', () => {
    expect(decodeClaudeHook('{"hook_event_name":"UserPromptSubmit"}').kind).toBe('working')
    expect(decodeClaudeHook('{"hook_event_name":"SessionEnd"}').kind).toBe('ended')
    expect(decodeClaudeHook('{"hook_event_name":"StopFailure","error":"rate limit"}').kind).toBe('error')
  })
  it('PostToolUse 원본 앞부분에서 session_id·cwd(윈도우 경로)만', () => {
    const big = JSON.stringify({ session_id: 'abc', cwd: 'C:\\work\\proj', hook_event_name: 'PostToolUse', tool_name: 'Read', tool_response: 'x'.repeat(10000) })
    const e = decodeClaudeTool(big.slice(0, 8192))
    expect(e).toMatchObject({ kind: 'working', sessionId: 'abc', cwd: 'C:\\work\\proj', detail: 'Read' })
  })
  it('한국어 알림 변환', () => {
    expect(koreanNotification('이미 한국어', 'idle_prompt')).toBe('이미 한국어')
    expect(koreanNotification('Claude is waiting for your input', 'idle_prompt')).toBe('입력을 기다리고 있어요')
    expect(koreanNotification(undefined, 'idle_prompt')).toBeUndefined()
  })
})

describe('표준·Codex 해석', () => {
  it('kind 없으면 exitCode 로', () => {
    expect(decodeStandard('{"source":"shell","exitCode":0}').kind).toBe('done')
    expect(() => decodeStandard('{"source":"zsh","kind":"done"}')).toThrow()
  })
  it('Codex agent-turn-complete', () => {
    const e = decodeCodexNotify(JSON.stringify({ type: 'agent-turn-complete', 'last-assistant-message': 'Done', cwd: '/p', 'thread-id': 't' }))
    expect(e).toMatchObject({ source: 'codex', kind: 'done', detail: 'Done', sessionId: 't' })
  })
  it('ChatGPT(Codex) 앱의 제목 짓기 작업 알림은 무시', () => {
    const title = JSON.stringify({ title: '텀펫 알람 기능 추가', description: '알람 기능 검토' })
    expect(() => decodeCodexNotify(JSON.stringify({ type: 'agent-turn-complete', 'last-assistant-message': title }))).toThrow()
    expect(decodeCodexNotify(JSON.stringify({ type: 'agent-turn-complete', 'last-assistant-message': '{괄호로 시작하는 답}' })).detail).toBe('{괄호로 시작하는 답}')
  })
  it('oneLine 은 120자로 자른다', () => {
    expect([...oneLine('가'.repeat(200))].length).toBe(120)
  })
})

describe('SessionTracker', () => {
  const ev = (kind: 'working' | 'ask' | 'done' | 'ended', extra = {}) => makeEvent({ source: 'claude', kind, sessionId: 's1', cwd: 'C:\\p\\proj', ...extra })
  it('작업 중 → 권한 대기 → 끝남 → 제거', () => {
    const t = new SessionTracker()
    t.apply(ev('working'))
    expect(t.count('working')).toBe(1)
    t.apply(ev('ask', { notificationType: 'permission_prompt' }))
    expect(t.count('waiting')).toBe(1)
    t.apply(ev('done'))
    expect(t.ordered[0].state).toBe('done')
    expect(t.ordered[0].projectName).toBe('proj')
    t.apply(ev('ended'))
    expect(t.sessions.size).toBe(0)
  })
  it('idle_prompt 는 권한 대기가 아니다', () => {
    const t = new SessionTracker()
    t.apply(ev('done'))
    t.apply(ev('ask', { notificationType: 'idle_prompt' }))
    expect(t.ordered[0].state).toBe('done')
  })
  it('끝난 뒤 60초 리마인더(idle_prompt)는 끝 신호를 놓쳤을 때만 알림', () => {
    const idle = ev('ask', { notificationType: 'idle_prompt' })
    const t = new SessionTracker()
    t.apply(ev('done'))
    expect(isRedundantIdlePrompt(idle, t.apply(idle))).toBe(true)
    // 모르는 세션: 목록에도 안 만든다
    const unknown = new SessionTracker()
    expect(isRedundantIdlePrompt(idle, unknown.apply(idle))).toBe(true)
    expect(unknown.sessions.size).toBe(0)
    // 끝 신호를 놓쳐 아직 작업 중이면 알리고 끝난 것으로 고친다
    const missed = new SessionTracker()
    missed.apply(ev('working'))
    expect(isRedundantIdlePrompt(idle, missed.apply(idle))).toBe(false)
    expect(missed.ordered[0].state).toBe('done')
    expect(isRedundantIdlePrompt(ev('ask', { notificationType: 'permission_prompt' }), 'done')).toBe(false)
  })
  it('오래된 작업 중은 정리', () => {
    const t = new SessionTracker()
    t.apply(ev('working'), 0)
    expect(t.prune(16 * 60_000)).toBe(true)
  })
  it('Claude 앱 채팅의 답변 중은 5분 뒤 정리 (끝 신호가 빠져도 "…"이 오래 남지 않게)', () => {
    const t = new SessionTracker()
    t.apply(decodeStandard(JSON.stringify({ source: 'claude', kind: 'working', sessionId: 'claude-app-chat' })), 0)
    t.apply(ev('working'), 0)
    expect(t.prune(4 * 60_000)).toBe(false)
    expect(t.prune(5 * 60_000 + 1)).toBe(true)
    expect(t.sessions.size).toBe(1)
  })
  it('Claude 앱 Code 탭 세션이 작업 중이면 "Claude 채팅" 신호는 중복으로 버림', () => {
    const t = new SessionTracker()
    const chat = decodeStandard(JSON.stringify({ source: 'claude', kind: 'done', sessionId: 'claude-app-chat', host: 'claude.exe' }))
    expect(t.isDuplicateChatSignal(chat, 0)).toBe(false)
    t.apply(ev('working', { sessionId: 'cursor-1', host: 'Cursor.exe' }), 0)
    expect(t.isDuplicateChatSignal(chat, 0)).toBe(false)
    t.apply(ev('working', { sessionId: 'code-1', host: 'claude.exe' }), 0)
    expect(t.isDuplicateChatSignal(chat, 4_000)).toBe(true)
    expect(t.isDuplicateChatSignal(chat, 3 * 60_000)).toBe(false)
    t.apply(ev('done', { sessionId: 'code-1', host: 'claude.exe' }), 10_000)
    expect(t.isDuplicateChatSignal(chat, 11_000)).toBe(false)
  })
  it('배지 우선순위', () => {
    expect(pickBadge(1, 2, true)).toEqual({ type: 'waiting', count: 1 })
    expect(pickBadge(0, 2, true)).toEqual({ type: 'unread' })
    expect(pickBadge(0, 2, false)).toEqual({ type: 'working', count: 2 })
  })
})

describe('알림 큐·말풍선', () => {
  it('같은 세션 알림은 교체, idle_prompt 리마인더는 무시', () => {
    const q = new NotificationQueue()
    const c = { title: '', body: '' }
    const a = makeEvent({ source: 'claude', kind: 'done', sessionId: 's' })
    expect(q.push({ id: a.id, event: a, content: c })).toBe('added')
    const b = makeEvent({ source: 'claude', kind: 'ask', sessionId: 's', notificationType: 'idle_prompt' })
    expect(q.push({ id: b.id, event: b, content: c })).toBe('ignored')
    const d = makeEvent({ source: 'claude', kind: 'ask', sessionId: 's', notificationType: 'permission_prompt' })
    expect(q.push({ id: d.id, event: d, content: c })).toBe('replaced')
    expect(q.removeSession(d)).toBe(true)
    expect(q.isEmpty).toBe(true)
  })
  it('쉘 명령은 걸린 시간을 보조 설명에', () => {
    const e = makeEvent({ source: 'shell', kind: 'done', detail: 'npm test', durationSec: 125 })
    expect(makeContent(e, defaultMessages, () => 0)).toEqual({ title: '터미널', body: '끝났어!', detail: 'npm test · 2분 5초' })
  })
  it('시간 표시', () => {
    expect(formatDuration(42)).toBe('42초')
    expect(formatDuration(3700)).toBe('1시간 1분')
  })
  it('팩 문구가 비면 기본 문구', () => {
    expect(packMessages({ done: [] }).done).toEqual(defaultMessages.done)
  })
})

describe('하루 기록·기분', () => {
  it('기록하고 날짜가 바뀌면 새로', () => {
    const day1 = new Date(2026, 10, 9, 10)
    let s = recordStats(undefined, makeEvent({ source: 'claude', kind: 'done' }), day1)
    s = recordStats(s, makeEvent({ source: 'shell', kind: 'done', command: 'cargo build', durationSec: 90 }), day1)
    expect(statsSpeech(s).body).toBe('오늘 2번 끝냈어요!')
    expect(s.longestCommand).toBe('cargo build')
    expect(currentStats(s, new Date(2026, 10, 10)).aiDone).toBe(0)
  })
  it('최근 실패가 이어지면 시무룩, 성공이 이어지면 신남', () => {
    const now = 1_000_000
    expect(moodFrom([[now, false], [now, false]], now)).toBe('gloomy')
    expect(moodFrom([[now, true], [now, true], [now, true]], now)).toBe('cheerful')
    expect(moodFrom([[0, false]], 31 * 60_000)).toBe('normal')
  })
})

import { checkResult } from './misc'
describe('checkResult (버전 확인)', () => {
  const ok = { tag_name: 'v0.5.4', assets: [{ name: 'TermPet-Setup-0.5.4.exe', browser_download_url: 'https://github.com/x/TermPet-Setup-0.5.4.exe' }] }
  it('새 버전 / 최신', () => {
    expect(checkResult(200, ok, '0.5.3').state).toEqual({ state: 'available', version: '0.5.4' })
    expect(checkResult(200, ok, '0.5.4').state).toEqual({ state: 'upToDate' })
    expect(checkResult(200, ok, '0.5.4').latest).toBe('0.5.4') // 패널 안내에 "GitHub 최신 v…" 로 보여 줌
  })
  it('실패 이유를 구분한다', () => {
    expect(checkResult(403, { message: 'API rate limit exceeded' }, '0.5.3').state).toMatchObject({ state: 'failed', message: expect.stringContaining('횟수') })
    expect(checkResult(404, {}, '0.5.3').state).toMatchObject({ state: 'failed' })
    expect(checkResult(200, {}, '0.5.3').state).toEqual({ state: 'failed', message: '버전 정보를 읽지 못했어요' })
    expect(checkResult(502, undefined, '0.5.3').state).toEqual({ state: 'failed', message: '버전 확인 실패 (HTTP 502)' })
  })
})
