// 패널(맥과 같은 구성) 뒤의 순수 로직: 최근 알림 기록, 설정값 범위
import { describe, expect, it } from 'vitest'
import { makeEvent } from './events'
import { HISTORY_MAX, NotificationHistory, timeAgo } from './history'
import { DEFAULT_PREFS, normalizePrefs, scaledSize } from './prefs'

const content = { title: 'proj', body: '다 했어요' }

describe('최근 알림 기록', () => {
  it('알림만 최신순으로, 진행 신호·입력 대기 리마인더는 기록 안 함', () => {
    const h = new NotificationHistory()
    h.record(makeEvent({ source: 'claude', kind: 'working', sessionId: 's' }), content)
    h.record(makeEvent({ source: 'claude', kind: 'ask', sessionId: 's', notificationType: 'idle_prompt' }), content)
    expect(h.entries).toHaveLength(0)
    h.record(makeEvent({ source: 'claude', kind: 'done', sessionId: 'a' }), { title: 'a', body: '1' })
    h.record(makeEvent({ source: 'codex', kind: 'error', sessionId: 'b' }), { title: 'b', body: '2' })
    expect(h.entries.map((x) => x.title)).toEqual(['b', 'a'])
  })

  it('같은 세션의 지난 권한 요청은 새 알림으로 대체', () => {
    const h = new NotificationHistory()
    h.record(makeEvent({ source: 'claude', kind: 'ask', sessionId: 's' }), { title: 'p', body: '권한' })
    h.record(makeEvent({ source: 'claude', kind: 'done', sessionId: 's' }), { title: 'p', body: '끝' })
    expect(h.entries.map((x) => x.body)).toEqual(['끝'])
  })

  it(`최대 ${HISTORY_MAX}개, 지우기`, () => {
    const h = new NotificationHistory()
    for (let i = 0; i < HISTORY_MAX + 5; i++) h.record(makeEvent({ source: 'shell', kind: 'done' }), { title: String(i), body: '' })
    expect(h.entries).toHaveLength(HISTORY_MAX)
    expect(h.entries[0].title).toBe(String(HISTORY_MAX + 4))
    h.clear()
    expect(h.entries).toHaveLength(0)
  })

  it('"방금 / n분 전 / n시간 전"', () => {
    expect(timeAgo(30_000)).toBe('방금')
    expect(timeAgo(3 * 60_000 + 5_000)).toBe('3분 전')
    expect(timeAgo(2 * 3600_000 + 1)).toBe('2시간 전')
  })
})

describe('설정값 (맥 PetPreferences 와 같은 범위)', () => {
  it('빠진 값은 기본값, 범위 밖은 끝값, 이상한 값은 기본값', () => {
    expect(normalizePrefs()).toEqual(DEFAULT_PREFS)
    expect(normalizePrefs({ sizeScale: 9, speedScale: 0.1, bubbleSeconds: Number.NaN })).toEqual({ sizeScale: 1.6, speedScale: 0.5, bubbleSeconds: 3 })
  })
  it('크기 배율 (반올림, 최소 24px)', () => {
    expect(scaledSize({ width: 100, height: 80 }, 1.25)).toEqual({ width: 125, height: 100 })
    expect(scaledSize({ width: 30, height: 30 }, 0.6)).toEqual({ width: 24, height: 24 })
  })
})
