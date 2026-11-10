// 텀펫 윈도우판 — Electron 메인 프로세스 (Node). 맥 앱 AppDelegate + MenuBarExtra 에 해당.
// 하는 일: 트레이 아이콘·패널, 펫·말풍선 창(pet.ts / bubble.ts), 알림 서버, 친구 팩, AI 연결, 업데이트.
// React 비유: 앱 전체를 감싸는 "서버" 쪽. 화면 그리기는 renderer(React)가, 창 위치·파일 접근은 여기서.
import { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, net, protocol, screen, shell, Tray, type MenuItemConstructorOptions } from 'electron'
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs'
import { join, normalize, sep } from 'node:path'
import { pathToFileURL } from 'node:url'
import { makeEvent, type PetEvent } from '../shared/events'
import type { IntegrationKind, PanelAction, PanelState } from '../shared/ipc'
import { LAYERS } from '../shared/misc'
import { currentStats, statsSummary } from '../shared/notifications'
import { focusEvent } from './focus'
import { importPacks } from './importer'
import { INTEGRATIONS, isAvailable, status as integrationStatus, toggle as toggleIntegration } from './integrations'
import { loadFriends, loadPack, type LoadedPack } from './packs'
import { installBundledScripts, loadOrCreateToken, resourcesPath, writePort } from './paths'
import { PetController } from './pet'
import { startServer, type ServerState } from './server'
import { saveSettings, settings } from './store'
import { Updater } from './updater'
import { win32Available } from './win32'
import { loadView } from './windows'

const isWin = process.platform === 'win32'
// 개발용(맥에서 실행)일 때는 맥 앱 폴더를 어지럽히지 않게 Electron 데이터는 따로 둔다
if (!isWin) app.setPath('userData', join(app.getPath('appData'), 'TermPet-electron-dev'))

/** 친구 팩 폴더: 맥 앱과 같은 규칙 <AppData>/TermPet/Friends (윈도우: %APPDATA%\TermPet\Friends).
 *  맥 개발 실행에서 "친구 추가하기"는 맥 앱 친구를 지우지 않게 개발용 폴더에 넣고, 그 폴더가 있으면 그걸 읽는다 */
const macAppFriends = join(app.getPath('appData'), 'TermPet', 'Friends')
const devFriends = () => join(app.getPath('userData'), 'Friends')
const importTarget = () => (isWin ? macAppFriends : devFriends())
function friendsDir() {
  if (isWin) return macAppFriends
  try {
    if (readdirSync(devFriends()).some((n) => !n.startsWith('.'))) return devFriends()
  } catch {
    /* 없음 */
  }
  return macAppFriends
}

// 맥 개발 실행은 맥 앱(47821)과 겹치지 않게
const DEFAULT_PORT = isWin ? 47821 : 47831

// 팩 그림 파일을 renderer에 주는 전용 주소: termpet://pack/<팩 키>/<파일>
protocol.registerSchemesAsPrivileged([{ scheme: 'termpet', privileges: { standard: true, secure: true, supportFetchAPI: true } }])

let packs: LoadedPack[] = []
let current: LoadedPack | undefined
let tray: Tray | undefined
let panel: BrowserWindow | undefined
let panelHeight = 600
let serverState: ServerState = { type: 'stopped' }
const pet = new PetController()
const updater = new Updater()

// MARK: - 친구 팩

function builtinPack(): LoadedPack {
  return loadPack(join(resourcesPath(), 'builtin'), 'builtin')
}

function reloadPacks() {
  packs = loadFriends(friendsDir())
  if (packs.length === 0) packs = [builtinPack()]
  const wanted = settings().selected
  current = packs.find((p) => p.key === wanted) ?? packs[0]
}

function selectPack(key: string) {
  const p = packs.find((x) => x.key === key)
  if (!p) return
  current = p
  saveSettings({ selected: key })
  pet.setPack(p)
  refreshUI()
}

async function importFriends(folder = false) {
  hidePanel()
  const r = await dialog.showOpenDialog({
    title: '친구 팩 고르기',
    message: '캐릭터 팩이 든 zip 파일(또는 폴더)을 골라 주세요. 지금 친구들은 지워지고 새 친구들로 바뀌어요',
    buttonLabel: '추가',
    // 윈도우 파일 선택 창은 파일과 폴더를 한 번에 못 고른다 → 기본은 zip, 트레이 메뉴에 '폴더에서'
    properties: folder ? ['openDirectory'] : ['openFile'],
    filters: folder ? undefined : [{ name: 'zip', extensions: ['zip'] }],
  })
  const source = r.filePaths[0]
  if (r.canceled || !source) return
  try {
    const ids = importPacks(source, importTarget())
    reloadPacks()
    const names = ids.map((id) => packs.find((p) => p.key === `friend.${id}`)?.name ?? id)
    if (ids[0]) selectPack(`friend.${ids[0]}`)
    void alert(`친구를 ${ids.length}명으로 새로 바꿨어요`, names.join(', '))
  } catch (e) {
    void alert('친구를 추가하지 못했어요', (e as Error).message)
  }
}

function openFriendsFolder() {
  const dir = isWin ? macAppFriends : friendsDir()
  mkdirSync(dir, { recursive: true })
  void shell.openPath(dir)
}

async function alert(title: string, detail: string) {
  await dialog.showMessageBox({ type: 'info', title: '텀펫', message: title, detail, buttons: ['확인'] })
}

// MARK: - AI 연결

function onToggleIntegration(kind: IntegrationKind, remove: boolean) {
  const before = integrationStatus(kind)
  const updating = before.needsUpdate && !remove
  const title = INTEGRATIONS.find((i) => i.kind === kind)!.title
  try {
    toggleIntegration(kind, remove)
    if (kind === 'powershell' && !before.installed) {
      void alert(
        '터미널 명령 알림을 연결했어요',
        '새로 여는 PowerShell 창부터 적용돼요.\n\n프로필 스크립트가 막혀 있으면(실행 정책 Restricted) 동작하지 않아요. 그럴 땐 PowerShell 에서 한 번:\nSet-ExecutionPolicy -Scope CurrentUser RemoteSigned',
      )
    } else if (kind === 'claude' && (updating || !before.installed)) {
      void alert('Claude Code를 연결했어요', '새로 시작하는 Claude Code 세션부터 펫 머리 위에 작업 중(…)·권한 대기(✋)가 표시돼요.')
    }
  } catch (e) {
    void alert(`${title} 연결을 바꾸지 못했어요`, `${(e as Error).message}\n\n설정 파일은 바뀌지 않았어요.`)
  }
  refreshUI()
}

// MARK: - 패널 (맥 메뉴바 패널과 같은 구성)

function panelState(): PanelState {
  const p = current
  const idle = p ? p.anims.idle?.[0] : undefined
  const st = updater.status
  return {
    version: app.getVersion(),
    friends: packs.map((x) => ({ key: x.key, name: x.name, thumbnail: x.thumbnail, selected: x.key === p?.key })),
    selectedName: p?.name ?? '텀펫',
    stage:
      p && idle
        ? { packKey: p.key, file: idle.file, frames: idle.frames, fps: idle.fps, pixelArt: p.pack.pixelArt ?? false, frameWidth: p.pack.frameWidth, frameHeight: p.pack.frameHeight }
        : undefined,
    visible: pet.visible,
    sleeping: pet.isSleeping,
    walkOnWindows: pet.walkOnWindows,
    walkOnWindowsAvailable: win32Available(),
    layer: pet.layer,
    mood: pet.mood,
    server:
      serverState.type === 'listening'
        ? { ok: true, text: '알림 받는 중' }
        : serverState.type === 'failed'
          ? { ok: false, text: `오류: ${serverState.message}` }
          : { ok: false, text: '알림 꺼짐' },
    statsLine: statsSummary(currentStats(pet.stats)),
    sessions: pet.sessions.ordered.map((s) => ({
      id: s.id,
      title: s.projectName ?? (s.source === 'claude' ? 'Claude Code' : s.source === 'codex' ? 'Codex' : '터미널'),
      source: s.source,
      state: s.state,
      since: s.since,
    })),
    integrations: INTEGRATIONS.map((i) => ({ ...i, ...integrationStatus(i.kind), available: isAvailable(i.kind) })),
    quiet: { manualOn: pet.quiet.manualOn, duringMeetings: pet.quiet.duringMeetings, soundOnAsk: pet.quiet.soundOnAsk, isQuiet: pet.quiet.quiet },
    launchAtLogin: app.getLoginItemSettings().openAtLogin,
    update: { state: st.state, version: st.state === 'available' ? st.version : undefined, message: st.state === 'failed' ? st.message : undefined },
    isDev: !app.isPackaged,
  }
}

let refreshQueued = false
/** 상태가 바뀌면 패널·트레이 메뉴 다시 그리기 (한 틱에 여러 번 바뀌어도 한 번만) */
function refreshUI() {
  if (refreshQueued) return
  refreshQueued = true
  setImmediate(() => {
    refreshQueued = false
    if (panel && !panel.isDestroyed() && panel.isVisible()) panel.webContents.send('panel:state', panelState())
  })
}

function createPanel() {
  panel = new BrowserWindow({
    width: 332,
    height: panelHeight,
    show: false,
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    backgroundColor: '#00000000',
    webPreferences: { preload: join(__dirname, '../preload/index.js'), sandbox: false },
  })
  loadView(panel, 'panel')
  panel.on('blur', () => hidePanel()) // 다른 곳을 누르면 닫힘 (맥 메뉴바 패널처럼)
  panel.webContents.on('did-finish-load', () => panel?.webContents.send('panel:state', panelState()))
}

function positionPanel() {
  if (!panel) return
  const tb = tray?.getBounds()
  const anchor = tb && tb.width > 0 ? { x: tb.x + tb.width / 2, y: tb.y + tb.height / 2 } : screen.getCursorScreenPoint()
  const wa = screen.getDisplayNearestPoint({ x: Math.round(anchor.x), y: Math.round(anchor.y) }).workArea
  const width = 332
  const height = Math.min(panelHeight, wa.height - 16)
  const x = Math.round(Math.min(Math.max(anchor.x - width / 2, wa.x + 8), wa.x + wa.width - width - 8))
  // 트레이가 화면 아래(윈도우 작업표시줄)면 위로, 위(맥 메뉴바)면 아래로 펼친다
  const below = anchor.y < wa.y + wa.height / 2
  const y = below ? wa.y + 8 : wa.y + wa.height - height - 8
  panel.setBounds({ x, y, width, height })
}

function togglePanel() {
  if (!panel || panel.isDestroyed()) createPanel()
  if (panel!.isVisible()) return hidePanel()
  positionPanel()
  panel!.webContents.send('panel:state', panelState())
  panel!.show()
  panel!.focus()
}

function hidePanel() {
  if (panel && !panel.isDestroyed() && panel.isVisible()) panel.hide()
}

ipcMain.on('panel:size', (_e, h: number) => {
  panelHeight = Math.ceil(h)
  if (panel?.isVisible()) positionPanel()
})

ipcMain.on('panel:action', (_e, a: PanelAction) => {
  switch (a.type) {
    case 'selectFriend':
      return selectPack(a.key)
    case 'importFriends':
      return void importFriends()
    case 'openFriendsFolder':
      return openFriendsFolder()
    case 'setVisible':
      return pet.setVisible(a.visible)
    case 'toggleSleep':
      return pet.toggleSleep()
    case 'toggleWalkOnWindows':
      return pet.setWalkOnWindows(!pet.walkOnWindows)
    case 'dropFromTop':
      return pet.dropFromTop()
    case 'testNotification':
      return pet.receive(makeEvent({ source: 'shell', kind: 'done', message: '알림이 잘 보이나요?' }))
    case 'toggleIntegration':
      return onToggleIntegration(a.kind, a.remove)
    case 'quietManual':
      pet.quiet.toggleManual()
      return refreshUI()
    case 'quietMeetings':
      pet.quiet.setDuringMeetings(!pet.quiet.duringMeetings)
      return refreshUI()
    case 'soundOnAsk':
      pet.quiet.setSoundOnAsk(!pet.quiet.soundOnAsk)
      return refreshUI()
    case 'setLayer':
      return pet.setLayer(a.layer)
    case 'focusSession': {
      const s = pet.sessions.sessions.get(a.id)
      hidePanel()
      if (s) focusEvent(s.focusEvent)
      return
    }
    case 'setLaunchAtLogin':
      app.setLoginItemSettings({ openAtLogin: a.on })
      return refreshUI()
    case 'checkUpdate':
      return void updater.check()
    case 'update':
      return void updater.update()
    case 'debug':
      if (a.kind === 'ask') return pet.receive(debugAsk())
      return pet.react(a.kind)
    case 'quit':
      return app.quit()
  }
})

function debugAsk(): PetEvent {
  return makeEvent({ source: 'claude', kind: 'ask', message: '권한 확인이 필요해요', cwd: process.cwd(), notificationType: 'permission_prompt', termProgram: 'vscode' })
}

// MARK: - 트레이 · 우클릭 메뉴

function trayMenu(): Menu {
  return Menu.buildFromTemplate([
    { label: '텀펫 메뉴 열기', click: () => togglePanel() },
    { type: 'separator' },
    { label: '친구 추가하기 (zip)…', click: () => void importFriends(false) },
    { label: '친구 추가하기 (폴더)…', click: () => void importFriends(true) },
    { label: '친구 폴더 열기', click: openFriendsFolder },
    {
      label: '친구 목록 새로고침',
      click: () => {
        reloadPacks()
        if (current) pet.setPack(current)
        refreshUI()
      },
    },
    { type: 'separator' },
    { label: '텀펫 종료', click: () => app.quit() },
  ])
}

function createTray() {
  const icon = nativeImage.createFromPath(join(resourcesPath(), 'tray.png'))
  tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon.resize({ width: 16, height: 16 }))
  tray.setToolTip('텀펫')
  tray.on('click', () => togglePanel())
  tray.on('right-click', () => tray?.popUpContextMenu(trayMenu()))
}

/** 펫 우클릭 메뉴 */
function showPetMenu() {
  const items: MenuItemConstructorOptions[] = [
    { label: pet.isSleeping ? '깨우기' : '재우기', click: () => pet.toggleSleep() },
    {
      label: '표시 위치',
      submenu: LAYERS.map((l) => ({ label: l.title, type: 'radio' as const, checked: pet.layer === l.id, click: () => pet.setLayer(l.id) })),
    },
    {
      label: '친구',
      submenu: packs.map((p) => ({ label: p.name, type: 'radio' as const, checked: p.key === current?.key, click: () => selectPack(p.key) })),
    },
    { label: '텀펫 메뉴 열기', click: () => togglePanel() },
    { type: 'separator' },
    { label: '텀펫 종료', click: () => app.quit() },
  ]
  Menu.buildFromTemplate(items).popup()
}

/** termpet://pack/<키>/<파일> → 팩 폴더 안의 파일 (폴더 밖은 거절) */
function registerPackProtocol() {
  protocol.handle('termpet', (req) => {
    const url = new URL(req.url)
    const [, key, ...rest] = decodeURIComponent(url.pathname).split('/')
    const p = url.hostname === 'pack' ? packs.find((x) => x.key === key) : undefined
    if (!p) return new Response('not found', { status: 404 })
    const file = normalize(join(p.folder, ...rest))
    if (!file.startsWith(normalize(p.folder) + sep) || !existsSync(file)) return new Response('not found', { status: 404 })
    return net.fetch(pathToFileURL(file).toString())
  })
}

function startEventServer() {
  let token: string
  try {
    token = loadOrCreateToken()
  } catch (e) {
    serverState = { type: 'failed', message: '토큰 생성 실패' }
    console.warn('[TermPet] token error', e)
    return
  }
  const stored = settings().port
  const port = stored && stored >= 1024 && stored <= 65535 ? stored : DEFAULT_PORT
  writePort(port)
  startServer(
    port,
    token,
    (e) => pet.receive(e),
    (s) => {
      serverState = s
      refreshUI()
    },
  )
}

/** 개발용: 알림·패널을 띄운 뒤 모든 창을 PNG로 저장 (화면 녹화 권한 없이 모양 확인) */
async function devSnapshot(dir: string) {
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))
  await wait(2500)
  pet.receive(debugAsk())
  togglePanel()
  panel?.removeAllListeners('blur') // 터미널에서 띄우면 앱이 포커스를 못 받아 바로 닫히므로 (개발용 스냅샷만)
  await wait(1500)
  mkdirSync(dir, { recursive: true })
  for (const w of BrowserWindow.getAllWindows()) {
    if (!w.isVisible()) continue
    const view = new URL(w.webContents.getURL()).searchParams.get('view') ?? 'win'
    const img = await w.webContents.capturePage()
    writeFileSync(join(dir, `${view}.png`), img.toPNG())
    console.log(`[snapshot] ${view} ${JSON.stringify(w.getBounds())}`)
  }
}

// 앱을 두 번 켜면 펫이 둘이 되지 않게 (두 번째 실행은 메뉴만 열어 준다)
if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.on('second-instance', () => togglePanel())
  app.whenReady().then(() => {
    app.dock?.hide() // 맥에서 개발 실행할 때 Dock 아이콘 숨김
    if (isWin) app.setAppUserModelId('com.termpet.TermPet')
    registerPackProtocol()
    reloadPacks()
    installBundledScripts()
    pet.onChange = refreshUI
    pet.onContextMenu = showPetMenu
    updater.onChange = refreshUI
    pet.start(current!)
    createTray()
    createPanel()
    startEventServer()
    updater.startPeriodicChecks()
    if (!app.isPackaged && process.env.TERMPET_SNAPSHOT) void devSnapshot(process.env.TERMPET_SNAPSHOT)
  })
  app.on('window-all-closed', () => {
    /* 트레이 앱이라 창이 없어도 계속 실행 */
  })
}
