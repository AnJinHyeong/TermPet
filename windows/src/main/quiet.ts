// "조용한 시간" (맥 QuietMode.swift): 이 동안 알림은 말풍선 없이 쌓아만 둔다 (머리 위 "!"는 표시).
//  - 직접 켜기: 1시간 / 회의 중 자동: 마이크를 어떤 앱이든 쓰고 있으면
import { execFile } from 'node:child_process'
import { isQuiet, micInUseFromRegQuery, QUIET_MANUAL_MS } from '../shared/misc'
import { saveSettings, settings } from './store'

const MIC_KEY = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\microphone'

export class QuietMode {
  manualUntil?: number
  duringMeetings = settings().quietDuringMeetings ?? false
  soundOnAsk = settings().soundOnAsk ?? true
  micInUse = false
  quiet = false
  onChange?: (quiet: boolean) => void
  private timer?: NodeJS.Timeout

  get manualOn() {
    return this.manualUntil !== undefined && Date.now() < this.manualUntil
  }

  toggleManual() {
    this.manualUntil = this.manualOn ? undefined : Date.now() + QUIET_MANUAL_MS
    this.refresh()
  }

  setDuringMeetings(v: boolean) {
    this.duringMeetings = v
    saveSettings({ quietDuringMeetings: v })
    this.refresh()
  }

  setSoundOnAsk(v: boolean) {
    this.soundOnAsk = v
    saveSettings({ soundOnAsk: v })
  }

  /** 5초마다 1시간 만료 확인, 마이크 상태(reg.exe 실행)는 15초마다 */
  start() {
    this.refresh()
    let n = 0
    this.timer = setInterval(() => this.refresh(++n % 3 === 0), 5000)
  }

  stop() {
    clearInterval(this.timer)
  }

  refresh(checkMic = true) {
    if (this.manualUntil !== undefined && Date.now() >= this.manualUntil) this.manualUntil = undefined
    if (!checkMic) {
      this.update()
      return
    }
    if (this.duringMeetings && process.platform === 'win32') {
      execFile('reg.exe', ['query', MIC_KEY, '/s', '/v', 'LastUsedTimeStop'], { windowsHide: true, timeout: 3000 }, (_err, out) => {
        this.micInUse = micInUseFromRegQuery(String(out ?? ''))
        this.update()
      })
    } else {
      this.micInUse = false
    }
    this.update()
  }

  private update() {
    const q = isQuiet(Date.now(), this.manualUntil, this.duringMeetings, this.micInUse)
    if (q === this.quiet) return
    this.quiet = q
    this.onChange?.(q)
  }
}
