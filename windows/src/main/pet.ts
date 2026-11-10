// 펫 한 마리 총괄 (맥 PetController.swift 대응): 창, 루프, 마우스 입력 → 두뇌/물리 → 창 위치·모습 갱신.
// 순수 로직은 shared/brain·physics·terrain 에 있고, 여기는 Electron과 연결하는 "접착제".
import { BrowserWindow, ipcMain, screen } from 'electron'
import { PetBrain, isPhysicsControlled } from '../shared/brain'
import { animationFor, shouldFlip, type PetAction } from '../shared/characterPack'
import { isNotification, moodOf, type PetEvent } from '../shared/events'
import { petOriginY, petScreenTop, sign, toModelRect, type Point, type Vector } from '../shared/geometry'
import type { PetFrameState } from '../shared/ipc'
import { effectiveLayer, type PetLayer } from '../shared/misc'
import { currentStats, isSticky, moodFrom, packMessages, recordStats, statsSpeech, walkFactor, type DailyStats, type PetMood } from '../shared/notifications'
import { loopFPS, PetPhysics, throwVelocity } from '../shared/physics'
import { pickBadge, SessionTracker, type PetBadge } from '../shared/sessions'
import { hasFullscreenWindow, ScreenLayout, Terrain, type Wall, type WindowBox } from '../shared/terrain'
import { BubbleController } from './bubble'
import { focusEvent } from './focus'
import type { LoadedPack } from './packs'
import { QuietMode } from './quiet'
import { saveSettings, settings } from './store'
import { leftButtonDown, listWindows, win32Available } from './win32'
import { applyLayer, loadView, pushToBottom, transparentWindowOptions } from './windows'

const DRAG_THRESHOLD = 4
const rng = Math.random
const now = () => performance.now() / 1000

export class PetController {
  readonly brain = new PetBrain()
  readonly physics = new PetPhysics({ x: 0, y: 0 }, { width: 80, height: 80 })
  readonly bubble = new BubbleController()
  readonly sessions = new SessionTracker()
  readonly quiet = new QuietMode()
  stats: DailyStats = currentStats(settings().dailyStats)
  mood: PetMood = 'normal'
  layer: PetLayer = settings().layer ?? 'aboveApps'
  walkOnWindows = settings().walkOnWindows ?? true
  visible = true
  /** 패널 등 다른 화면에 "상태가 바뀌었다"고 알림 */
  onChange?: () => void

  private pack?: LoadedPack
  private win?: BrowserWindow
  private terrain = new Terrain(new ScreenLayout([]))
  private layout = new ScreenLayout([])
  private climbingWall?: Wall
  private climbLimitY = Infinity
  private lastWindowScan = 0
  private lastBottomPush = 0
  private outcomes: [number, boolean][] = []
  private lastPrune = 0
  private timer?: NodeJS.Timeout
  private lastTick = now()
  private actionSerial = 0
  private lastAction: PetAction = 'idle'
  private lastVariant = 0
  private lastSent = ''
  private badge: PetBadge = { type: 'none' }
  // 드래그 상태
  private mouseDownAt?: Point // 화면 좌표(DIP)
  private dragOffset = { x: 0, y: 0 } // 커서 - 창 왼쪽 위
  private dragging = false
  private dragTrail: [number, Point][] = []

  constructor() {
    this.bubble.onActivate = (n) => focusEvent(n.event)
    this.bubble.onVisibilityChange = () => this.applyEffectiveLayer()
    this.bubble.onChange = () => this.onChange?.()
    this.quiet.onChange = (q) => {
      this.bubble.setQuiet(q)
      this.onChange?.()
    }
    ipcMain.on('pet:pointer', (_e, type: 'down' | 'up' | 'context') => {
      if (type === 'down') this.mouseDown()
      else if (type === 'up') this.mouseUp()
      else this.onContextMenu?.()
    })
  }

  /** 우클릭 메뉴 (index.ts 가 채움) */
  onContextMenu?: () => void

  get isSleeping() {
    return this.brain.action === 'sleep'
  }
  get usesWindows() {
    return this.walkOnWindows && this.layer === 'aboveApps' && win32Available()
  }
  get currentPack() {
    return this.pack
  }

  // MARK: - 시작

  start(pack: LoadedPack) {
    this.setPack(pack)
    this.refreshLayout()
    // 처음엔 주 화면 바닥 가운데
    const wa = screen.getPrimaryDisplay().workArea
    this.physics.origin = { x: wa.x + wa.width / 2 - this.physics.size.width / 2, y: petOriginY(wa.y + wa.height - this.physics.size.height, this.physics.size.height) }
    const { width, height } = this.physics.size
    const win = new BrowserWindow({ ...transparentWindowOptions(), width, height })
    loadView(win, 'pet')
    win.webContents.on('did-finish-load', () => {
      this.lastSent = ''
      this.sendFrame()
    })
    win.once('ready-to-show', () => {
      this.placeWindow()
      if (this.visible) win.showInactive()
      this.applyEffectiveLayer()
    })
    this.win = win
    // 모니터 연결/해제, 해상도·작업표시줄 변경
    const relayout = () => setTimeout(() => this.settle(), 300)
    screen.on('display-added', relayout)
    screen.on('display-removed', relayout)
    screen.on('display-metrics-changed', relayout)
    this.quiet.start()
    this.schedule(30)
  }

  // MARK: - 외부 API

  setPack(pack: LoadedPack) {
    this.pack = pack
    this.bubble.messages = packMessages(pack.pack.messages)
    const size = pack.size
    if (size.width === this.physics.size.width && size.height === this.physics.size.height) return
    // 발 위치와 가로 중심은 유지한 채 크기만 바꾼다
    this.physics.origin.x += (this.physics.size.width - size.width) / 2
    this.physics.size = { ...size }
    this.rebuildTerrain(this.terrain.windows)
    this.placeWindow()
    if (this.win && !this.dragging) this.beginFall()
    this.lastSent = ''
  }

  toggleSleep() {
    this.brain.handle({ type: this.isSleeping ? 'wake' : 'sleep' }, rng)
    this.sendFrame()
    this.onChange?.()
  }

  react(action: PetAction) {
    this.brain.handle({ type: 'react', action }, rng)
    this.sendFrame()
  }

  setVisible(v: boolean) {
    this.visible = v
    if (v) {
      if (!this.win?.isDestroyed()) this.win?.showInactive()
      this.applyEffectiveLayer()
    } else {
      if (!this.win?.isDestroyed()) this.win?.hide()
      this.bubble.hide() // 미확인 알림은 큐에 남아 있다가 다시 보이면 "!"로
    }
    this.onChange?.()
  }

  setLayer(layer: PetLayer) {
    this.layer = layer
    saveSettings({ layer })
    this.applyEffectiveLayer()
    this.rescanWindows(true)
    // 바탕화면 층에선 창 뒤라 창 위를 다니지 않는다 → 창 위에 있었다면 내려온다
    if (!this.dragging && (this.physics.standingOn !== null || this.brain.action === 'climb')) this.beginFall()
    this.onChange?.()
  }

  setWalkOnWindows(v: boolean) {
    this.walkOnWindows = v
    saveSettings({ walkOnWindows: v })
    this.rescanWindows(true)
    if (!this.dragging && (this.physics.standingOn !== null || this.brain.action === 'climb')) this.beginFall()
    this.onChange?.()
  }

  /** 화면 위쪽 랜덤한 곳에서 떨어뜨리기 (창 위에 떨어지면 거기서 논다) */
  dropFromTop() {
    this.refreshLayout()
    const frames = this.layout.frames
    const i = this.layout.indexContaining(this.physics.centerX, this.physics.origin.y) ?? this.layout.nearestIndex(this.physics.centerX)
    if (i === undefined) return
    const f = frames[i]
    this.physics.origin = { x: f.x + rng() * Math.max(0, f.width - this.physics.size.width), y: f.y + f.height - this.physics.size.height }
    this.placeWindow()
    this.beginFall()
  }

  /** 외부 이벤트 수신 → 감정 + 말풍선 */
  receive(incoming: PetEvent) {
    const e = { ...incoming }
    this.sessions.apply(e)
    if (!isNotification(e)) {
      // 작업 시작·도구 실행·세션 종료: 세션이 다시 움직이면 지난 권한 요청 알림은 해결된 것
      if (this.sessions.stateOf(e) !== 'waiting') this.bubble.resolve(e)
      this.onChange?.()
      return
    }
    this.stats = recordStats(this.stats, e)
    saveSettings({ dailyStats: this.stats })
    if (e.kind === 'done' || e.kind === 'error') {
      const wasGloomy = this.mood === 'gloomy'
      this.outcomes.push([Date.now(), e.kind === 'done'])
      if (this.outcomes.length > 20) this.outcomes.splice(0, this.outcomes.length - 20)
      this.updateMood()
      if (wasGloomy && e.kind === 'done' && !e.message) {
        const lines = ['휴, 이번엔 됐다!', '드디어 성공!', '됐다…! 다행이야']
        e.message = lines[Math.floor(rng() * lines.length)]
      }
    }
    this.brain.handle({ type: 'react', action: moodOf(e), duration: 3 }, rng)
    this.bubble.enqueue(e)
    if (!this.visible) this.bubble.hide()
    // 권한 요청은 작업이 멈춘 상태라 소리로 한 번 더
    if (isSticky(e) && this.quiet.soundOnAsk && !this.quiet.quiet && this.visible) this.bubble.chime()
    this.sendFrame()
    this.onChange?.()
  }

  // MARK: - 루프

  /** 동작에 맞춘 간격으로 다음 걸음 예약 (setInterval 대신: fps 를 바꾸기 쉽게) */
  private schedule(fps: number) {
    this.timer = setTimeout(() => this.tick(), 1000 / fps)
  }

  private tick() {
    const t = now()
    const dt = Math.min(t - this.lastTick, 0.2) // 렉 걸려도 순간이동 없게
    this.lastTick = t
    try {
      if (this.visible) this.step(dt)
    } catch (e) {
      console.warn('[TermPet] 루프 오류', e)
    }
    let fps = this.dragging || this.mouseDownAt ? 60 : loopFPS(this.brain.action)
    if (this.physics.standingOn !== null) fps = Math.max(fps, 20) // 창을 끌 때 매끄럽게 따라가게
    if (!this.visible) fps = 2
    this.schedule(fps)
  }

  private step(dt: number) {
    if (this.mouseDownAt) this.trackMouse()
    this.brain.tick(dt, rng)
    if (!this.dragging) this.rescanWindows(false)

    switch (this.brain.action) {
      case 'walk': {
        const r = this.physics.walk(this.brain.direction, this.walkSpeed, dt, this.terrain)
        if (r.type === 'hitWall') {
          this.brain.handle({ type: 'hitWall', window: r.wall.windowID !== null }, rng)
          if (this.currentAction() === 'climb') this.startClimbing(r.wall)
        } else if (r.type === 'reachedEdge') {
          this.brain.handle({ type: 'reachedEdge' }, rng)
          // 선반 끝에서 폴짝 뛰어내리기
          if (this.currentAction() === 'fall') this.physics.prepareFall(this.terrain, { dx: sign(this.brain.direction) * 110, dy: 420 })
        } else if (r.type === 'startFalling') {
          this.beginFall()
        }
        break
      }
      case 'climb':
        this.stepClimb(dt)
        break
      case 'fall':
        if (this.physics.fall(dt, this.terrain)) this.brain.handle({ type: 'landed' }, rng)
        break
      default:
        // 서 있는데 발밑 창이 사라졌으면(닫힘·최소화·가려짐) 떨어진다
        if (!this.dragging && !isPhysicsControlled(this.brain.action) && this.physics.standingOn !== null) {
          if (!this.terrain.ledge(this.physics.centerX, this.physics.origin.y, this.physics.standingOn)) this.beginFall()
        }
    }

    if (!this.dragging) this.placeWindow()
    if (this.lastTick - this.lastPrune > 10) {
      this.lastPrune = this.lastTick
      if (this.sessions.prune()) this.onChange?.()
      this.updateMood()
    }
    // 신날 때는 가끔 깡충 (평균 20초에 한 번)
    if (this.mood === 'cheerful' && this.brain.action === 'idle' && rng() < dt / 20) this.brain.handle({ type: 'react', action: 'happy', duration: 1.2 }, rng)
    // 바탕화면 층: 다른 창이 활성화되며 위로 올라와도 다시 맨 뒤로 (1초마다)
    if (this.win && !this.win.isDestroyed() && effectiveLayer(this.layer, this.bubble.isShowing) !== 'aboveApps' && this.lastTick - this.lastBottomPush > 1) {
      this.lastBottomPush = this.lastTick
      pushToBottom(this.win)
    }
    this.badge = pickBadge(this.sessions.count('waiting'), this.sessions.count('working'), this.bubble.hasUnread && !this.bubble.isShowing)
    this.sendFrame()
  }

  /** handle() 뒤에 바뀐 동작 (TS 가 switch 안에서 좁혀 둔 타입을 풀기 위해 함수로 읽는다) */
  private currentAction(): PetAction {
    return this.brain.action
  }

  /** 걷기 속도: 기분 반영 + 달리기 포즈(walk.2)가 뽑히면 빠르게 */
  private get walkSpeed() {
    let speed = (this.pack?.pack.walkSpeed ?? 40) * walkFactor(this.mood)
    const walks = this.pack?.anims.walk?.length ?? 0
    if (walks > 1 && this.brain.variant % walks === 1) speed *= 1.9
    return speed
  }

  private updateMood() {
    const m = moodFrom(this.outcomes, Date.now())
    if (m !== this.mood) {
      this.mood = m
      this.onChange?.()
    }
  }

  private beginFall(v: Vector = { dx: 0, dy: 0 }) {
    this.climbingWall = undefined
    this.physics.prepareFall(this.terrain, v)
    this.brain.handle({ type: 'startFall' }, rng)
  }

  /** 모델 좌표 → 창 위치 */
  private placeWindow() {
    if (!this.win || this.win.isDestroyed()) return
    const { width, height } = this.physics.size
    const x = Math.round(this.physics.origin.x)
    const y = Math.round(petScreenTop(this.physics.origin.y, height))
    const b = this.win.getBounds()
    if (b.x !== x || b.y !== y || b.width !== width || b.height !== height) this.win.setBounds({ x, y, width, height })
    this.bubble.follow({ x, y, width, height })
  }

  /** 지금 모습 → 펫 화면(React)에 전달 (바뀌었을 때만) */
  private sendFrame() {
    if (!this.win || !this.pack) return
    if (this.brain.action !== this.lastAction || this.brain.variant !== this.lastVariant) {
      this.actionSerial++
      this.lastAction = this.brain.action
      this.lastVariant = this.brain.variant
    }
    const anim = animationFor(this.pack.anims, this.brain.action, this.brain.variant)
    if (!anim) return
    const state: PetFrameState = {
      packKey: this.pack.key,
      action: this.brain.action,
      actionSerial: this.actionSerial,
      anim,
      flip: shouldFlip(anim.facing, this.brain.direction),
      pixelArt: this.pack.pack.pixelArt ?? false,
      width: this.physics.size.width,
      height: this.physics.size.height,
      badge: this.badge,
      mood: this.mood,
    }
    const key = JSON.stringify(state)
    if (key === this.lastSent) return
    this.lastSent = key
    this.win.webContents.send('pet:state', state)
  }

  // MARK: - 지형

  /** 바닥 = 작업표시줄 위(workArea 아래 끝). 전체 화면 앱이 있는 모니터는 맨 아래까지 */
  private refreshLayout(windows: WindowBox[] = this.terrain.windows) {
    const frames = screen.getAllDisplays().map((d) => {
      const full = toModelRect(d.bounds)
      return toModelRect(hasFullscreenWindow(windows, full) ? d.bounds : d.workArea)
    })
    this.layout = new ScreenLayout(frames)
    this.rebuildTerrain(windows)
  }

  private rebuildTerrain(windows: WindowBox[]) {
    this.terrain = new Terrain(this.layout, this.usesWindows ? windows : [], this.physics.size)
  }

  /** 창 목록 읽기 (윈도우 전용). 창 위에 있거나 매달려 있으면 자주(창을 끌면 따라가게), 아니면 가끔 */
  private scanWindows(): WindowBox[] {
    return listWindows().map((w) => ({
      id: Number(w.hwnd),
      owner: w.pid,
      // 물리 픽셀 → DIP (화면 배율 125%·150% 등)
      frame: toModelRect(screen.screenToDipRect(null, w.rect)),
    }))
  }

  private rescanWindows(force: boolean) {
    if (!this.usesWindows) {
      if (this.terrain.windows.length || force) {
        this.refreshLayout([])
      }
      return
    }
    const t = now()
    const onWindow = this.physics.standingOn !== null || (this.climbingWall?.windowID ?? null) !== null
    const interval = onWindow ? 1 / 20 : this.brain.action === 'walk' || this.brain.action === 'fall' ? 0.25 : 0.6
    if (!force && t - this.lastWindowScan < interval) return
    this.lastWindowScan = t
    const old = this.terrain
    this.refreshLayout(this.scanWindows())

    // 서 있던 창이 움직였으면 같이 이동
    const id = this.physics.standingOn
    if (id !== null) {
      const before = old.window(id)?.frame
      const after = this.terrain.window(id)?.frame
      if (before && after && (before.x !== after.x || before.y !== after.y || before.width !== after.width || before.height !== after.height)) {
        this.physics.ride(before, after)
      }
    }
    // 매달린 벽(창)이 움직이거나 사라지면 따라가거나 떨어진다
    const wall = this.climbingWall
    if (wall && wall.windowID !== null) {
      const after = this.terrain.window(wall.windowID)?.frame
      if (after) {
        const before = old.window(wall.windowID)?.frame
        if (before) this.physics.ride(before, after)
        this.climbingWall = { ...wall, x: wall.side === 'right' ? after.x : after.x + after.width, top: after.y + after.height }
      } else {
        this.beginFall()
      }
    }
  }

  /** 화면 구성이 바뀐 뒤 자리 잡기 (순간이동 없이, 발밑이 없어졌을 때만 떨어짐) */
  private settle() {
    this.refreshLayout()
    this.rescanWindows(true)
    if (this.dragging || isPhysicsControlled(this.brain.action)) return
    const id = this.physics.standingOn
    if (id !== null) {
      if (!this.terrain.ledge(this.physics.centerX, this.physics.origin.y, id)) this.beginFall()
      return
    }
    const floor = this.layout.landingFloor(this.physics.centerX, this.physics.origin.y) ?? this.physics.origin.y
    if (Math.abs(this.physics.origin.y - floor) > 0.5) this.beginFall()
  }

  // MARK: - 벽 오르기

  private startClimbing(wall: Wall) {
    this.climbingWall = wall
    this.physics.standingOn = null
    if (wall.windowID !== null && this.terrain.ledgeAfterClimbing(wall)) {
      this.climbLimitY = Infinity // 창 꼭대기까지 올라가서 올라선다
    } else {
      // 올라설 곳이 없는 벽(화면 끝): 적당히 오르다 뛰어내린다
      const top = Math.min(wall.top, this.terrain.ceiling(this.physics.centerX) ?? wall.top) - this.physics.size.height
      const room = Math.max(0, top - this.physics.origin.y)
      this.climbLimitY = this.physics.origin.y + room * (0.25 + rng() * 0.45)
    }
  }

  private stepClimb(dt: number) {
    const wall = this.climbingWall
    if (!wall) return this.beginFall()
    // 가끔 힘이 빠져서 미끄러진다 (평균 50초에 한 번)
    if (rng() < dt / 50) {
      this.brain.handle({ type: 'letGo' }, rng)
      return this.beginFall({ dx: -sign(wall.side) * 60, dy: 0 })
    }
    const limit = Math.min(this.climbLimitY, this.terrain.climbCeiling(wall, this.physics.origin.y) ?? Infinity)
    const speed = Math.max((this.pack?.pack.walkSpeed ?? 40) * 1.3, 50)
    const r = this.physics.climb(wall, speed, dt, this.terrain, limit)
    if (r.type === 'reachedTop') {
      this.climbingWall = undefined
      this.brain.handle({ type: 'climbedUp' }, rng)
    } else if (r.type === 'letGo') {
      this.brain.handle({ type: 'letGo' }, rng)
      this.beginFall({ dx: -sign(wall.side) * 180, dy: 380 }) // 벽을 차고 반대쪽으로 폴짝
    }
  }

  // MARK: - 마우스

  private mouseDown() {
    if (!this.win) return
    const p = screen.getCursorScreenPoint()
    const b = this.win.getBounds()
    this.mouseDownAt = p
    this.dragOffset = { x: p.x - b.x, y: p.y - b.y }
    this.dragging = false
    this.dragTrail = [[now(), this.toModelPoint(p)]]
    clearTimeout(this.timer)
    this.schedule(60)
  }

  private toModelPoint(p: Point): Point {
    return { x: p.x, y: -p.y }
  }

  /** 누르고 있는 동안 매 프레임: 커서를 따라 창 이동 (창 밖으로 빨리 움직여도 놓치지 않게 메인에서 커서를 읽는다) */
  private trackMouse(checkButton = true) {
    const start = this.mouseDownAt
    if (!start || !this.win) return
    // 창 밖에서 버튼을 놓아 mouseup 이 안 온 경우 (윈도우만 확인 가능).
    // mouseUp 안에서 부를 때는 확인하지 않는다 (확인하면 mouseUp ↔ trackMouse 가 서로 무한히 부름)
    if (checkButton && leftButtonDown() === false) return this.mouseUp()
    const p = screen.getCursorScreenPoint()
    if (!this.dragging) {
      if (Math.hypot(p.x - start.x, p.y - start.y) < DRAG_THRESHOLD) return
      this.dragging = true
      this.brain.handle({ type: 'dragStarted' }, rng)
    }
    const { width, height } = this.physics.size
    const x = p.x - this.dragOffset.x
    const y = p.y - this.dragOffset.y
    this.physics.origin = { x, y: petOriginY(y, height) }
    this.physics.standingOn = null
    this.climbingWall = undefined
    this.win.setBounds({ x, y, width, height })
    this.bubble.follow({ x, y, width, height })
    const t = now()
    this.dragTrail.push([t, this.toModelPoint(p)])
    this.dragTrail = this.dragTrail.filter(([tt]) => t - tt <= 0.1) // 최근 0.1초만
  }

  private mouseUp() {
    if (!this.mouseDownAt) return
    this.trackMouse(false)
    this.mouseDownAt = undefined
    if (this.dragging) {
      this.dragging = false
      this.rescanWindows(true)
      this.beginFall(throwVelocity(this.dragTrail))
      return
    }
    // 단일 클릭: 말풍선이 떠 있으면 말풍선 동작(이동), 숨은 미확인 알림이 있으면 다시 보기, 아니면 오늘 기록
    if (this.bubble.isShowing) this.bubble.activateCurrent()
    else if (this.bubble.hasUnread) this.bubble.show()
    else {
      this.brain.handle({ type: 'clicked' }, rng)
      this.bubble.say(statsSpeech(currentStats(this.stats)))
    }
    this.sendFrame()
    this.onChange?.()
  }

  // MARK: - 표시 층

  /** "바탕화면에만 + 알림 시 앞으로": 말풍선이 떠 있는 동안만 앱 창 위로 */
  private applyEffectiveLayer() {
    const eff = effectiveLayer(this.layer, this.bubble.isShowing)
    if (this.win) applyLayer(this.win, eff)
    this.bubble.setLayer(eff)
  }
}
