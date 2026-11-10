// 말풍선 창 + 알림 큐 (맥 BubbleController.swift 대응).
//  - 새 알림 → 큐에 넣고 말풍선 표시, 3초 뒤 숨김 (미확인 알림은 펫 머리 위 "!"로 남음)
//  - 말풍선 클릭 → 해당 프로젝트로 이동 + 다음 알림, × → 이동 없이 다음 알림
// 말풍선 크기는 React가 그린 뒤 재서 알려 준다(bubble:size) → 창 크기·위치를 맞춘다.
import { BrowserWindow, ipcMain, screen } from 'electron'
import type { PetEvent } from '../shared/events'
import type { BubbleState } from '../shared/ipc'
import { placeBubble, type PetLayer, type ScreenRect } from '../shared/misc'
import { defaultMessages, isSticky, makeContent, NotificationQueue, type BubbleContent, type BubbleMessages, type PetNotification } from '../shared/notifications'
import { applyLayer, loadView, transparentWindowOptions } from './windows'

export class BubbleController {
  readonly queue = new NotificationQueue()
  messages: BubbleMessages = defaultMessages
  displayMs = 3000
  isShowing = false
  /** 말풍선이 나타나거나 사라질 때 (바탕화면 모드에서 잠깐 앞으로 올리기용) */
  onVisibilityChange?: (showing: boolean) => void
  /** 말풍선 본문 클릭 → 프로젝트로 이동 */
  onActivate?: (n: PetNotification) => void
  /** 큐가 바뀔 때 (머리 위 ! 표시 갱신용) */
  onChange?: () => void

  private win?: BrowserWindow
  private hideTimer?: NodeJS.Timeout
  private petRect: ScreenRect = { x: 0, y: 0, width: 80, height: 80 }
  private size = { width: 200, height: 80 }
  private state?: BubbleState
  private quiet = false
  private layer: PetLayer = 'aboveApps'

  constructor() {
    ipcMain.on('bubble:size', (_e, w: number, h: number) => {
      const size = { width: Math.ceil(w), height: Math.ceil(h) }
      if (size.width === this.size.width && size.height === this.size.height) return
      this.size = size
      this.reposition(true)
    })
    ipcMain.on('bubble:click', (_e, target: 'body' | 'close') => (target === 'close' ? this.dismissCurrent() : this.activateCurrent()))
  }

  get hasUnread() {
    return !this.queue.isEmpty
  }

  setQuiet(q: boolean) {
    if (q === this.quiet) return
    this.quiet = q
    if (q) this.hide()
    else if (this.hasUnread) this.show()
  }

  enqueue(e: PetEvent) {
    const content = makeContent(e, this.messages, Math.random)
    if (this.queue.push({ id: e.id, event: e, content }) === 'ignored') return
    this.onChange?.()
    if (!this.quiet) this.show()
  }

  /** 알림이 아닌 펫의 혼잣말 (오늘 기록). 미확인 알림이 있으면 그걸 먼저 */
  say(content: BubbleContent) {
    if (!this.queue.isEmpty) return this.show()
    this.present({ content, kind: 'working', badge: 0, tailX: 60, below: false })
    this.scheduleHide()
  }

  /** 세션이 다시 움직이면(승인됨/새 질문) 그 세션의 지난 알림을 치운다 */
  resolve(e: PetEvent) {
    const wasCurrent = this.queue.removeSession(e)
    this.onChange?.()
    if (wasCurrent && this.isShowing) this.advance()
  }

  show() {
    const cur = this.queue.current
    if (!cur) return this.hide()
    this.present({ content: cur.content, kind: cur.event.kind, badge: this.queue.pendingCount, tailX: 60, below: false })
    if (isSticky(cur.event)) clearTimeout(this.hideTimer)
    else this.scheduleHide()
  }

  /** 앱 종료 중 등 창이 이미 파괴됐으면 undefined (파괴된 창을 만지면 예외) */
  private get live(): BrowserWindow | undefined {
    return this.win && !this.win.isDestroyed() ? this.win : undefined
  }

  hide() {
    clearTimeout(this.hideTimer)
    this.live?.hide()
    this.setShowing(false)
  }

  activateCurrent() {
    const n = this.queue.popCurrent()
    this.onChange?.()
    if (!n) return this.hide() // 혼잣말은 누르면 닫기만
    this.onActivate?.(n)
    this.advance()
  }

  dismissCurrent() {
    this.queue.popCurrent()
    this.onChange?.()
    this.advance()
  }

  chime() {
    this.live?.webContents.send('bubble:chime')
  }

  /** 펫이 움직일 때마다 → 말풍선이 따라감 (Electron 화면 좌표) */
  follow(pet: ScreenRect) {
    const moved = pet.x !== this.petRect.x || pet.y !== this.petRect.y || pet.width !== this.petRect.width
    this.petRect = pet
    if (moved && this.isShowing) this.reposition(false)
  }

  setLayer(layer: PetLayer) {
    this.layer = layer
    if (this.live) applyLayer(this.live, layer)
  }

  // MARK: - private

  private advance() {
    if (this.queue.isEmpty || this.quiet) this.hide()
    else this.show()
  }

  private scheduleHide() {
    clearTimeout(this.hideTimer)
    this.hideTimer = setTimeout(() => this.hide(), this.displayMs)
  }

  private setShowing(v: boolean) {
    if (v === this.isShowing) return
    this.isShowing = v
    this.onVisibilityChange?.(v)
  }

  private present(state: BubbleState) {
    const win = this.ensureWindow()
    this.state = state
    this.reposition(true)
    if (!win.isVisible()) win.showInactive()
    if (this.layer !== 'desktop') win.moveTop()
    this.setShowing(true)
  }

  private reposition(sendState: boolean) {
    const win = this.live
    if (!win || !this.state) return
    const center = { x: Math.round(this.petRect.x + this.petRect.width / 2), y: Math.round(this.petRect.y + this.petRect.height / 2) }
    const area = screen.getDisplayNearestPoint(center).workArea
    const p = placeBubble(this.size, this.petRect, area)
    const tailChanged = p.tailX !== this.state.tailX || p.below !== this.state.below
    this.state = { ...this.state, tailX: p.tailX, below: p.below }
    win.setBounds({ x: p.x, y: p.y, width: this.size.width, height: this.size.height })
    if (sendState || tailChanged) win.webContents.send('bubble:state', this.state)
  }

  private ensureWindow(): BrowserWindow {
    if (this.win && !this.win.isDestroyed()) return this.win
    const win = new BrowserWindow({ ...transparentWindowOptions(), width: this.size.width, height: this.size.height })
    loadView(win, 'bubble')
    // 처음 그려질 때 현재 내용을 보내 준다
    win.webContents.on('did-finish-load', () => this.state && win.webContents.send('bubble:state', this.state))
    applyLayer(win, this.layer)
    this.win = win
    return win
  }
}
