// 새 버전 확인 + 업데이트 (맥 AppUpdater.swift 의 윈도우판).
//  - 확인: GitHub 최신 릴리스 태그와 지금 버전 비교 (시작 때 + 6시간마다 + 패널 버전 글씨 클릭)
//  - 업데이트: 릴리스의 TermPet-Setup-*.exe 를 받아 조용히 설치(/S)하고 다시 켠다(--force-run). 없으면 릴리스 페이지 열기
import { app, net, shell } from 'electron'
import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { checkResult } from '../shared/misc'

const LATEST = 'https://api.github.com/repos/AnJinHyeong/TermPet/releases/latest'
const RELEASES_PAGE = 'https://github.com/AnJinHyeong/TermPet/releases/latest'

export type UpdateState = { state: 'idle' | 'checking' | 'upToDate' | 'updating' } | { state: 'available'; version: string } | { state: 'failed'; message: string }

export class Updater {
  status: UpdateState = { state: 'idle' }
  onChange?: () => void
  private installerUrl?: string
  /** 마지막으로 GitHub 이 알려 준 최신 버전·확인 시각 (패널 버전 글씨에 마우스를 올리면 보임 → "최신"이 맞는지 바로 확인) */
  latest?: string
  checkedAt?: number
  readonly current = app.getVersion()

  startPeriodicChecks() {
    void this.check()
    setInterval(() => void this.check(), 6 * 3600_000)
  }

  private set(s: UpdateState) {
    this.status = s
    this.onChange?.()
  }

  async check() {
    if (this.status.state === 'updating' || this.status.state === 'checking') return
    this.set({ state: 'checking' })
    try {
      // 예전 응답이 캐시에서 나와 "최신"으로 잘못 보이지 않게: 캐시 금지 + 요청마다 다른 주소
      const res = await net.fetch(`${LATEST}?t=${Date.now()}`, {
        headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'TermPet', 'Cache-Control': 'no-cache', Pragma: 'no-cache' },
        cache: 'no-store',
      })
      const body = await res.json().catch(() => undefined)
      const out = checkResult(res.status, body, this.current)
      if (out.installerUrl) this.installerUrl = out.installerUrl
      if (out.latest) {
        this.latest = out.latest
        this.checkedAt = Date.now()
      }
      this.set(out.state)
    } catch {
      this.set({ state: 'failed', message: '인터넷 연결을 확인해 주세요' })
    }
    if (this.status.state === 'failed') this.scheduleRetry()
    else this.retries = 0
  }

  /** 확인이 실패하면 1분 → 5분 → 15분 뒤 다시 (GitHub 일시 오류·요청 횟수 제한). 그 뒤는 6시간 주기에 맡긴다 */
  private retries = 0
  private retryTimer?: ReturnType<typeof setTimeout>
  private scheduleRetry() {
    const delays = [60_000, 300_000, 900_000]
    if (this.retries >= delays.length) return
    clearTimeout(this.retryTimer)
    this.retryTimer = setTimeout(() => void this.check(), delays[this.retries++])
  }

  async update() {
    if (process.platform !== 'win32' || !this.installerUrl) {
      void shell.openExternal(RELEASES_PAGE)
      return
    }
    this.set({ state: 'updating' })
    try {
      const res = await net.fetch(this.installerUrl)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const file = join(tmpdir(), `TermPet-Setup-${Date.now()}.exe`)
      writeFileSync(file, Buffer.from(await res.arrayBuffer()))
      // 설치 프로그램이 실행 중인 텀펫을 닫고 설치한 뒤 다시 켠다 (electron-builder NSIS 옵션)
      spawn(file, ['/S', '--force-run'], { detached: true, stdio: 'ignore' }).unref()
      setTimeout(() => app.quit(), 500)
    } catch {
      this.set({ state: 'failed', message: '업데이트를 받지 못했어요' })
      void shell.openExternal(RELEASES_PAGE)
    }
  }
}
