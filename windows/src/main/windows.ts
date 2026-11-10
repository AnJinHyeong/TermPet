// 펫·말풍선·패널 창 공통 도우미
import { app, BrowserWindow, type BrowserWindowConstructorOptions } from 'electron'
import { join } from 'node:path'
import type { PetLayer } from '../shared/misc'
import { hwndOf, sendToBottom } from './win32'

/** 투명·테두리 없음·작업표시줄에 안 보임·클릭해도 포커스 안 뺏음 (맥의 nonactivatingPanel) */
export function transparentWindowOptions(): BrowserWindowConstructorOptions {
  return {
    transparent: true,
    frame: false,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    hasShadow: false,
    skipTaskbar: true,
    focusable: false,
    alwaysOnTop: true,
    show: false,
    backgroundColor: '#00000000',
    webPreferences: { preload: join(__dirname, '../preload/index.js'), sandbox: false },
  }
}

/** 렌더러 화면 하나를 연다 (같은 React 앱을 ?view= 로 나눠 씀) */
export function loadView(win: BrowserWindow, view: 'pet' | 'bubble' | 'panel') {
  // 개발 실행: 화면(React) 쪽 경고·오류를 터미널 로그로
  if (!app.isPackaged) {
    win.webContents.on('console-message', (e) => {
      const d = e as unknown as { level?: string; message?: string }
      if (d.level === 'warning' || d.level === 'error') console.log(`[renderer:${view}] ${d.level}: ${d.message}`)
    })
    win.webContents.on('render-process-gone', (_e, d) => console.log(`[renderer:${view}] gone`, d.reason))
  }
  if (process.env.ELECTRON_RENDERER_URL) win.loadURL(`${process.env.ELECTRON_RENDERER_URL}?view=${view}`)
  else win.loadFile(join(__dirname, '../renderer/index.html'), { query: { view } })
}

/** 표시 층 적용: 항상 위 / 바탕화면(다른 앱 창 아래) */
export function applyLayer(win: BrowserWindow, layer: PetLayer) {
  if (win.isDestroyed()) return
  if (layer === 'aboveApps') {
    win.setAlwaysOnTop(true, 'floating')
    win.setVisibleOnAllWorkspaces(true)
  } else {
    win.setAlwaysOnTop(false)
    pushToBottom(win)
  }
}

export function pushToBottom(win: BrowserWindow) {
  if (process.platform === 'win32' && !win.isDestroyed()) sendToBottom(hwndOf(win.getNativeWindowHandle()))
}
