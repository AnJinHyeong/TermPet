// 텀펫 윈도우판 — Electron 메인 프로세스 (Node).
// 하는 일: 트레이 아이콘 · 투명한 펫 창 · 친구 팩 읽기 · 걷기 루프(창 위치 이동)
// React 비유: 앱 전체를 감싸는 "서버" 쪽. 화면 그리기는 renderer(React)가, 창 위치·파일 접근은 여기서.
import { app, BrowserWindow, Menu, nativeImage, net, protocol, screen, shell, Tray } from 'electron'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, normalize, sep } from 'node:path'
import { pathToFileURL } from 'node:url'
import { animationFor, shouldFlip } from '../shared/characterPack'
import { initialWalker, stepWalker, type WalkerState } from '../shared/walker'
import type { PetFrameState } from '../shared/ipc'
import { loadFriends, loadPack, type LoadedPack } from './packs'

// 친구 팩은 맥 앱과 같은 위치 규칙: <AppData>/TermPet/Friends (윈도우: %APPDATA%\TermPet\Friends)
const friendsDir = join(app.getPath('appData'), 'TermPet', 'Friends')
// 개발용(맥에서 실행)일 때는 맥 앱 폴더를 어지럽히지 않게 Electron 자체 데이터는 따로 둔다
if (process.platform !== 'win32') app.setPath('userData', join(app.getPath('appData'), 'TermPet-electron-dev'))
const settingsFile = () => join(app.getPath('userData'), 'settings.json')

// 팩 그림 파일을 renderer에 주는 전용 주소: termpet://pack/<팩 키>/<파일>
protocol.registerSchemesAsPrivileged([{ scheme: 'termpet', privileges: { standard: true, secure: true, supportFetchAPI: true } }])

let packs: LoadedPack[] = []
let current: LoadedPack | undefined
let win: BrowserWindow | undefined
let tray: Tray | undefined
let walker: WalkerState | undefined
let lastSent = ''
let hidden = false

const resourcesPath = () => (app.isPackaged ? process.resourcesPath : join(__dirname, '../../resources'))

function readSettings(): { selected?: string } {
  try {
    return JSON.parse(readFileSync(settingsFile(), 'utf8'))
  } catch {
    return {}
  }
}

function saveSettings(s: { selected?: string }) {
  try {
    mkdirSync(app.getPath('userData'), { recursive: true })
    writeFileSync(settingsFile(), JSON.stringify(s, null, 2))
  } catch (e) {
    console.warn('[TermPet] 설정 저장 실패', e)
  }
}

/** 친구가 하나도 없을 때: 앱 아이콘 토끼를 대신 보여준다 */
function builtinPack(): LoadedPack {
  return loadPack(join(resourcesPath(), 'builtin'), 'builtin')
}

function reloadPacks() {
  packs = loadFriends(friendsDir)
  if (packs.length === 0) packs = [builtinPack()]
  const wanted = readSettings().selected
  current = packs.find((p) => p.key === wanted) ?? packs[0]
}

function selectPack(key: string) {
  const p = packs.find((x) => x.key === key)
  if (!p) return
  current = p
  saveSettings({ selected: key })
  placeWindow()
  lastSent = ''
  rebuildTrayMenu()
}

/** 바닥 = 작업표시줄 바로 위 (workArea 아래 끝) */
function floor() {
  const wa = screen.getPrimaryDisplay().workArea
  const { width, height } = current!.size
  return { y: wa.y + wa.height - height, minX: wa.x, maxX: wa.x + wa.width - width }
}

function placeWindow() {
  if (!win || !current) return
  const { width, height } = current.size
  const f = floor()
  walker ??= initialWalker(Math.round((f.minX + f.maxX) / 2), Math.random)
  walker.x = Math.min(f.maxX, Math.max(f.minX, walker.x))
  win.setBounds({ x: Math.round(walker.x), y: f.y, width, height })
}

function createPetWindow() {
  const { width, height } = current!.size
  win = new BrowserWindow({
    width,
    height,
    transparent: true,
    frame: false,
    resizable: false,
    movable: false,
    hasShadow: false,
    skipTaskbar: true,
    focusable: false,
    alwaysOnTop: true,
    show: false,
    backgroundColor: '#00000000',
    webPreferences: { preload: join(__dirname, '../preload/index.js'), sandbox: false },
  })
  win.setAlwaysOnTop(true, 'screen-saver')
  win.setVisibleOnAllWorkspaces(true)
  if (process.env.ELECTRON_RENDERER_URL) win.loadURL(process.env.ELECTRON_RENDERER_URL)
  else win.loadFile(join(__dirname, '../renderer/index.html'))
  win.once('ready-to-show', () => {
    placeWindow()
    if (!hidden) win?.showInactive()
  })
}

/** 걷기 루프 (초당 30번): 두뇌 한 걸음 → 창 이동 → 모습이 바뀌었으면 renderer에 알림 */
function startLoop() {
  let last = Date.now()
  setInterval(() => {
    if (!win || !current || !walker) return
    const now = Date.now()
    const dt = Math.min(0.1, (now - last) / 1000)
    last = now
    const f = floor()
    walker = stepWalker(walker, dt, current.pack.walkSpeed ?? 38, { minX: f.minX, maxX: f.maxX }, Math.random)
    const { width, height } = current.size
    win.setBounds({ x: Math.round(walker.x), y: f.y, width, height })

    const anim = animationFor(current.anims, walker.action, walker.variant)
    if (!anim) return
    const state: PetFrameState = {
      packKey: current.key,
      action: walker.action,
      anim,
      flip: shouldFlip(anim.facing, walker.direction),
      pixelArt: current.pack.pixelArt ?? false,
      frameWidth: current.pack.frameWidth,
      frameHeight: current.pack.frameHeight,
      width,
      height,
    }
    const key = JSON.stringify(state)
    if (key !== lastSent) {
      lastSent = key
      win.webContents.send('pet:state', state)
    }
  }, 1000 / 30)
}

function rebuildTrayMenu() {
  if (!tray) return
  const friendItems = packs.map((p) => ({
    label: p.name,
    type: 'radio' as const,
    checked: p.key === current?.key,
    click: () => selectPack(p.key),
  }))
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: '텀펫', enabled: false },
      { type: 'separator' },
      { label: '친구 고르기', submenu: friendItems },
      {
        label: '친구 폴더 열기',
        click: () => {
          mkdirSync(friendsDir, { recursive: true })
          shell.openPath(friendsDir)
        },
      },
      {
        label: '친구 목록 새로고침',
        click: () => {
          reloadPacks()
          placeWindow()
          lastSent = ''
          rebuildTrayMenu()
        },
      },
      { type: 'separator' },
      {
        label: hidden ? '펫 보이기' : '펫 숨기기',
        click: () => {
          hidden = !hidden
          if (hidden) win?.hide()
          else win?.showInactive()
          rebuildTrayMenu()
        },
      },
      { type: 'separator' },
      { label: '종료', click: () => app.quit() },
    ]),
  )
}

function createTray() {
  const icon = nativeImage.createFromPath(join(resourcesPath(), 'tray.png'))
  tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon)
  tray.setToolTip('텀펫')
  rebuildTrayMenu()
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

// 앱을 두 번 켜면 펫이 둘이 되지 않게
if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.whenReady().then(() => {
    app.dock?.hide() // 맥에서 개발 실행할 때 Dock 아이콘 숨김 (윈도우에는 없음)
    registerPackProtocol()
    reloadPacks()
    createTray()
    createPetWindow()
    startLoop()
    screen.on('display-metrics-changed', placeWindow) // 작업표시줄 위치·해상도가 바뀌면 다시 자리 잡기
  })
  app.on('window-all-closed', () => {
    /* 트레이 앱이라 창이 없어도 계속 실행 */
  })
}
