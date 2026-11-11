// 앱 설정 저장 (맥의 UserDefaults ≈ localStorage). userData/settings.json 에 JSON으로.
import { app } from 'electron'
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { PetLayer } from '../shared/misc'
import type { DailyStats } from '../shared/notifications'
import type { PetPrefs } from '../shared/prefs'

export interface Settings {
  selected?: string
  layer?: PetLayer
  walkOnWindows?: boolean
  /** 장난꾸러기 모드 (기본 꺼짐) */
  mischief?: boolean
  /** "GPT 앱 채팅" 연결 (ChatGPT 앱 로그 읽기, 기본 꺼짐) */
  chatgptApp?: boolean
  quietDuringMeetings?: boolean
  soundOnAsk?: boolean
  port?: number
  dailyStats?: DailyStats
  /** 크기·걷기 속도·말풍선 유지 시간 */
  prefs?: Partial<PetPrefs>
}

let cache: Settings | undefined
const file = () => join(app.getPath('userData'), 'settings.json')

export function settings(): Settings {
  if (cache) return cache
  try {
    cache = JSON.parse(readFileSync(file(), 'utf8')) as Settings
  } catch {
    cache = {}
  }
  return cache
}

/** 일부만 바꿔 저장 (React setState(prev => ({...prev, ...patch})) 처럼) */
export function saveSettings(patch: Partial<Settings>) {
  cache = { ...settings(), ...patch }
  try {
    mkdirSync(app.getPath('userData'), { recursive: true })
    const tmp = file() + '.tmp'
    writeFileSync(tmp, JSON.stringify(cache, null, 2))
    renameSync(tmp, file()) // 쓰다가 꺼져도 파일이 깨지지 않게
  } catch (e) {
    console.warn('[TermPet] 설정 저장 실패', e)
  }
}
