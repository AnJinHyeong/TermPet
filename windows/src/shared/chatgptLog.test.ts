// "GPT 앱 채팅" (맥 Tests/ChatGPTAppLogTests.swift 대응) — 실제 로그에서 가져온 줄
import { mkdirSync, appendFileSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ChatGPTWatcher } from '../main/chatgptWatcher'
import { ChatGPTReducer, dayFolder, isCodexThread, LOCAL_WINDOW_MS, parseChatGPTLogLine } from './chatgptLog'
import { planFocus } from './hostApp'

const refetch =
  '2026-11-11T07:58:12.569Z info [electron-message-handler] chatgpt_conversation_refetch_completed asyncStatus=null conversationId=6af42003-045c-83ee-8b87-4716e0b39754 currentNodeApplied=true mappingSize=9 reason=explicit_update rendererWebContentsId=1'
const ignored =
  '2026-11-11T07:55:17.420Z info [electron-message-handler] chatgpt_conversation_update_ignored conversationId=6af3fa1e-3e00-83ee-8ede-39fb3d94acbd reason=conversation_not_loaded rendererWebContentsId=1 updateType=completed'
const shown = '2026-11-11T07:55:22.054Z info [electron-message-handler] [desktop-notifications] show turn-complete conversationId=6af3fa2c-4db4-8191-82cc-eea3cd30808e rendererWebContentsId=1'
const started = '2026-11-11T07:54:44.856Z error [electron-message-handler] Received turn/started for unknown conversation conversationId=6af3fa2c-4db4-8191-82cc-eea3cd30808e'

describe('ChatGPT 앱 로그', () => {
  it('답변 완료·시작 줄을 알아본다', () => {
    expect(parseChatGPTLogLine(refetch)).toEqual({ type: 'completed', conversationId: '6af42003-045c-83ee-8b87-4716e0b39754' })
    expect(parseChatGPTLogLine(ignored)?.type).toBe('completedElsewhere')
    expect(parseChatGPTLogLine(shown)?.type).toBe('completed')
    expect(parseChatGPTLogLine(started)).toEqual({ type: 'started', conversationId: '6af3fa2c-4db4-8191-82cc-eea3cd30808e' })
  })

  it('Codex 대화(UUID v7)와 다른 줄은 건너뛴다', () => {
    expect(parseChatGPTLogLine('… [desktop-notifications] show turn-complete conversationId=01a1c98a-03f6-7ea0-a0a2-ae7a0bf1510f')).toBeUndefined()
    expect(parseChatGPTLogLine('… chatgpt_conversation_refetch_completed conversationId=6af42003-045c-83ee-8b87-4716e0b39754 reason=focus')?.type).toBe('seen') // 알림은 아니고 '여기서 연 대화' 표시
    expect(parseChatGPTLogLine('… [desktop-notifications] show turn-complete conversationId=null')).toBeUndefined()
    expect(isCodexThread('019f20ee-0994-7022-876d-d68d432affce')).toBe(true)
    expect(isCodexThread('6af42003-045c-83ee-8b87-4716e0b39754')).toBe(false)
  })

  it('이 앱에서 연 대화만 "안 열린 대화 완료"를 알린다 (휴대폰·웹에서 한 대화는 조용히)', () => {
    const id = '6af42003-045c-83ee-8b87-4716e0b39754'
    expect(parseChatGPTLogLine(`… chatgpt_conversation_refetch_started conversationId=${id} reason=explicit_update`)).toEqual({ type: 'seen', conversationId: id })
    expect(parseChatGPTLogLine(`… IAB_LIFECYCLE received browser sidebar owner sync ownerRoutePath=/c/${id} windowId=1`)).toEqual({ type: 'seen', conversationId: id })
    expect(parseChatGPTLogLine(`… chatgpt_conversation_update_ignored conversationId=${id} reason=conversation_not_loaded updateType=refetch`)).toBeUndefined()
    expect(parseChatGPTLogLine(`… chatgpt_conversation_refetch_completed conversationId=${id} reason=missed_messages`)).toBeUndefined()

    const r = new ChatGPTReducer()
    expect(r.event({ type: 'completedElsewhere', conversationId: 'phone' }, 1000)).toBeUndefined()
    expect(r.event({ type: 'seen', conversationId: 'here' }, 1000)).toBeUndefined()
    expect(r.event({ type: 'completedElsewhere', conversationId: 'here' }, 61_000)?.kind).toBe('done')
    expect(r.event({ type: 'completedElsewhere', conversationId: 'here' }, 61_000 + LOCAL_WINDOW_MS)).toBeUndefined()
    expect(r.event({ type: 'completed', conversationId: 'c3' }, 1000)).toBeDefined()
    expect(r.event({ type: 'completedElsewhere', conversationId: 'c3' }, 121_000)).toBeDefined()
  })

  it('같은 턴은 한 번만, 제목은 ChatGPT, 누르면 ChatGPT 앱', () => {
    const r = new ChatGPTReducer()
    const e = r.event({ type: 'completed', conversationId: 'c1' }, 1000)!
    expect(e.kind).toBe('done')
    expect(e.title).toBe('ChatGPT')
    expect(r.event({ type: 'completed', conversationId: 'c1' }, 6000)).toBeUndefined()
    expect(r.event({ type: 'completed', conversationId: 'c1' }, 61_000)).toBeDefined()
    expect(r.event({ type: 'started', conversationId: 'c1' }, 62_000)?.kind).toBe('working')
    const plan = planFocus(e, (c) => c)
    expect(plan.type === 'activate' && plan.host.kind).toBe('chatgpt')
  })

  it('날짜 폴더는 UTC (한국 아침 8시 = UTC 전날)', () => {
    expect(dayFolder('C:\\L', new Date('2026-11-11T23:00:00Z'), '\\')).toBe('C:\\L\\2026\\11\\11')
  })
})

describe('ChatGPTWatcher', () => {
  let dir: string | undefined
  afterEach(() => {
    if (dir) rmSync(dir, { recursive: true, force: true })
  })

  it('켠 뒤에 붙은 줄만 읽고, 줄이 반쯤 쓰였으면 다음에 이어서', () => {
    dir = mkdtempSync(join(tmpdir(), 'termpet-gptlog-'))
    const day = dayFolder(dir, new Date(), process.platform === 'win32' ? '\\' : '/')
    mkdirSync(day, { recursive: true })
    const file = join(day, 'codex-desktop-a.log')
    writeFileSync(file, shown + '\n') // 켜기 전 내용 → 무시
    const got = vi.fn()
    const w = new ChatGPTWatcher(got, () => [dir!])
    w.start()
    w.stop() // 타이머 없이 poll 을 직접 부른다
    w.poll()
    expect(got).not.toHaveBeenCalled()
    appendFileSync(file, refetch.slice(0, 50))
    w.poll()
    expect(got).not.toHaveBeenCalled()
    appendFileSync(file, refetch.slice(50) + '\n')
    w.poll()
    expect(got).toHaveBeenCalledTimes(1)
    // 켠 뒤 새로 생긴 파일은 처음부터
    writeFileSync(join(day, 'codex-desktop-b.log'), shown + '\n')
    w.poll()
    expect(got).toHaveBeenCalledTimes(2)
  })
})
