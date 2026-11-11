// 윈도우 OS 기능 호출 (user32 / dwmapi / kernel32) — koffi FFI 로 C 함수를 직접 부른다.
// 맥의 CGWindowListCopyWindowInfo · NSWorkspace 활성화 대응.
// React 비유: 브라우저에 없는 기능을 쓰려고 네이티브 모듈을 감싼 작은 어댑터. 윈도우가 아니면 모두 조용히 아무 일도 안 한다.
import { createRequire } from 'node:module'

/** 화면 위 앱 창 (물리 픽셀, 화면 좌표 y 아래로) */
export interface NativeWindow {
  hwnd: bigint
  pid: number
  rect: { x: number; y: number; width: number; height: number }
}

interface Api {
  EnumWindows: (cb: unknown, lparam: number) => boolean
  EnumWindowsProc: unknown
  IsWindowVisible: (h: bigint) => boolean
  IsIconic: (h: bigint) => boolean
  GetWindowLongPtrW: (h: bigint, index: number) => number | bigint
  GetClassNameW: (h: bigint, buf: Buffer, max: number) => number
  GetWindowThreadProcessId: (h: bigint, pid: number[]) => number
  DwmGetWindowAttributeRect: (h: bigint, attr: number, out: Record<string, number>, size: number) => number
  DwmGetWindowAttributeInt: (h: bigint, attr: number, out: number[], size: number) => number
  SetWindowPos: (h: bigint, after: bigint, x: number, y: number, cx: number, cy: number, flags: number) => boolean
  SetForegroundWindow: (h: bigint) => boolean
  GetForegroundWindow: () => bigint | number
  IsWindow: (h: bigint) => boolean
  ShowWindow: (h: bigint, cmd: number) => boolean
  GetAsyncKeyState: (key: number) => number
  SetCursorPos: (x: number, y: number) => boolean
  OpenProcess: (access: number, inherit: boolean, pid: number) => bigint | number
  QueryFullProcessImageNameW: (h: bigint | number, flags: number, buf: Buffer, size: number[]) => boolean
  CloseHandle: (h: bigint | number) => boolean
  keybd_event: (vk: number, scan: number, flags: number, extra: number) => void
}

let api: Api | null | undefined

function load(): Api | null {
  if (api !== undefined) return api
  api = null
  if (process.platform !== 'win32') return api
  try {
    // koffi 는 네이티브 모듈이라 번들에 넣지 않고 실행 중에 불러온다
    const koffi = createRequire(__filename)('koffi')
    const user32 = koffi.load('user32.dll')
    const dwm = koffi.load('dwmapi.dll')
    const kernel32 = koffi.load('kernel32.dll')
    koffi.struct('RECT', { left: 'long', top: 'long', right: 'long', bottom: 'long' })
    const EnumWindowsProc = koffi.proto('bool __stdcall EnumWindowsProc(intptr_t hwnd, intptr_t lparam)')
    api = {
      EnumWindowsProc,
      EnumWindows: user32.func('bool __stdcall EnumWindows(EnumWindowsProc *cb, intptr_t lparam)'),
      IsWindowVisible: user32.func('bool __stdcall IsWindowVisible(intptr_t hwnd)'),
      IsIconic: user32.func('bool __stdcall IsIconic(intptr_t hwnd)'),
      GetWindowLongPtrW: user32.func('intptr_t __stdcall GetWindowLongPtrW(intptr_t hwnd, int index)'),
      GetClassNameW: user32.func('int __stdcall GetClassNameW(intptr_t hwnd, _Out_ void *buf, int max)'),
      GetWindowThreadProcessId: user32.func('uint32_t __stdcall GetWindowThreadProcessId(intptr_t hwnd, _Out_ uint32_t *pid)'),
      DwmGetWindowAttributeRect: dwm.func('DwmGetWindowAttribute', 'long', ['intptr_t', 'uint32_t', koffi.out(koffi.pointer('RECT')), 'uint32_t']),
      DwmGetWindowAttributeInt: dwm.func('DwmGetWindowAttribute', 'long', ['intptr_t', 'uint32_t', koffi.out(koffi.pointer('uint32_t')), 'uint32_t']),
      SetWindowPos: user32.func('bool __stdcall SetWindowPos(intptr_t hwnd, intptr_t after, int x, int y, int cx, int cy, uint32_t flags)'),
      SetForegroundWindow: user32.func('bool __stdcall SetForegroundWindow(intptr_t hwnd)'),
      GetForegroundWindow: user32.func('intptr_t __stdcall GetForegroundWindow()'),
      IsWindow: user32.func('bool __stdcall IsWindow(intptr_t hwnd)'),
      ShowWindow: user32.func('bool __stdcall ShowWindow(intptr_t hwnd, int cmd)'),
      GetAsyncKeyState: user32.func('short __stdcall GetAsyncKeyState(int key)'),
      SetCursorPos: user32.func('bool __stdcall SetCursorPos(int x, int y)'),
      keybd_event: user32.func('void __stdcall keybd_event(uint8_t vk, uint8_t scan, uint32_t flags, uintptr_t extra)'),
      OpenProcess: kernel32.func('intptr_t __stdcall OpenProcess(uint32_t access, bool inherit, uint32_t pid)'),
      QueryFullProcessImageNameW: kernel32.func('bool __stdcall QueryFullProcessImageNameW(intptr_t h, uint32_t flags, _Out_ void *buf, _Inout_ uint32_t *size)'),
      CloseHandle: kernel32.func('bool __stdcall CloseHandle(intptr_t h)'),
    }
  } catch (e) {
    console.warn('[TermPet] win32 연동을 불러오지 못함 (창 위 산책·창 이동 꺼짐)', e)
    api = null
  }
  return api
}

export const win32Available = () => load() !== null

const WS_EX_TOOLWINDOW = 0x80
const WS_EX_TRANSPARENT = 0x20
const WS_EX_NOACTIVATE = 0x08000000
const GWL_EXSTYLE = -20
const DWMWA_EXTENDED_FRAME_BOUNDS = 9
const DWMWA_CLOAKED = 14
/** 바탕화면·작업표시줄·시작 메뉴 같은 셸 창은 지형이 아니다 */
const SKIP_CLASSES = new Set([
  'Progman',
  'WorkerW',
  'Shell_TrayWnd',
  'Shell_SecondaryTrayWnd',
  'NotifyIconOverflowWindow',
  'Windows.UI.Core.CoreWindow',
  'TopLevelWindowForOverflowXamlIsland',
  'XamlExplorerHostIslandWindow',
])

const toBig = (v: number | bigint) => (typeof v === 'bigint' ? v : BigInt(v))

function className(a: Api, h: bigint): string {
  const buf = Buffer.alloc(512)
  const n = a.GetClassNameW(h, buf, 256)
  return buf.toString('utf16le', 0, Math.max(0, n) * 2)
}

/** 앞 → 뒤 순서의 보이는 앱 창 (내 프로세스 창 제외) */
export function listWindows(ownPid = process.pid): NativeWindow[] {
  const a = load()
  if (!a) return []
  const out: NativeWindow[] = []
  try {
    a.EnumWindows((raw: number | bigint) => {
      const h = toBig(raw)
      try {
        if (!a.IsWindowVisible(h) || a.IsIconic(h)) return true
        const ex = Number(toBig(a.GetWindowLongPtrW(h, GWL_EXSTYLE)) & 0xffffffffn)
        if (ex & (WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE)) return true
        const cloaked = [0]
        if (a.DwmGetWindowAttributeInt(h, DWMWA_CLOAKED, cloaked, 4) === 0 && cloaked[0] !== 0) return true // 다른 가상 데스크톱 등
        const pid = [0]
        a.GetWindowThreadProcessId(h, pid)
        if (pid[0] === ownPid) return true
        if (SKIP_CLASSES.has(className(a, h))) return true
        // 보이는 테두리 기준 크기 (GetWindowRect 는 투명한 크기 조절 테두리까지 포함해서 더 크다)
        const r: Record<string, number> = {}
        if (a.DwmGetWindowAttributeRect(h, DWMWA_EXTENDED_FRAME_BOUNDS, r, 16) !== 0) return true
        const width = r.right - r.left
        const height = r.bottom - r.top
        if (width < 120 || height < 60) return true
        out.push({ hwnd: h, pid: pid[0], rect: { x: r.left, y: r.top, width, height } })
      } catch {
        /* 창 하나 읽기 실패는 건너뜀 */
      }
      return true
    }, 0)
  } catch (e) {
    console.warn('[TermPet] EnumWindows 실패', e)
  }
  return out
}

/** Electron 창 핸들(Buffer) → 숫자 */
export function hwndOf(buf: Buffer): bigint {
  return buf.length >= 8 ? buf.readBigUInt64LE(0) : BigInt(buf.readUInt32LE(0))
}

/** 창을 맨 뒤(다른 앱 창 아래 = 바탕화면 바로 위)로 보낸다. 포커스는 건드리지 않음 */
export function sendToBottom(hwnd: bigint) {
  const a = load()
  if (!a) return
  const HWND_BOTTOM = 1n
  a.SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0200) // NOSIZE|NOMOVE|NOACTIVATE|NOOWNERZORDER
}

/** 마우스 왼쪽 버튼이 지금 눌려 있는지 (드래그 중 창 밖에서 놓았을 때 확인용). 윈도우가 아니면 undefined */
export function leftButtonDown(): boolean | undefined {
  const a = load()
  if (!a) return undefined
  return (a.GetAsyncKeyState(0x01) & 0x8000) !== 0
}

const nameCache = new Map<number, string>()

/** 프로세스 실행 파일 이름 (소문자, 예: windowsterminal.exe) */
/** 마우스 버튼(왼쪽·오른쪽·가운데) 중 하나라도 누르고 있는지 (장난꾸러기: 드래그·선택 중엔 안 문다). 모르면 false */
export function anyMouseButtonDown(): boolean {
  const a = load()
  if (!a) return false
  return [0x01, 0x02, 0x04].some((vk) => (a.GetAsyncKeyState(vk) & 0x8000) !== 0)
}

/** 마우스 포인터를 화면 좌표(물리 픽셀)로 옮긴다 (장난꾸러기: 물고 흔들기·던지기). 권한 필요 없음 */
export function setCursorPos(x: number, y: number): boolean {
  const a = load()
  if (!a) return false
  return a.SetCursorPos(Math.round(x), Math.round(y))
}

export function processName(pid: number): string {
  const cached = nameCache.get(pid)
  if (cached !== undefined) return cached
  const a = load()
  if (!a) return ''
  let name = ''
  const h = a.OpenProcess(0x1000, false, pid) // PROCESS_QUERY_LIMITED_INFORMATION
  if (h) {
    try {
      const buf = Buffer.alloc(2048)
      const size = [1024]
      if (a.QueryFullProcessImageNameW(h, 0, buf, size)) name = buf.toString('utf16le', 0, size[0] * 2).split('\\').pop()!.toLowerCase()
    } finally {
      a.CloseHandle(h)
    }
  }
  if (nameCache.size > 500) nameCache.clear()
  nameCache.set(pid, name)
  return name
}

/** 이 프로세스 이름들 중 맨 앞 창을 앞으로 가져온다. 찾으면 true */
export function focusProcessWindow(names: string[]): boolean {
  const a = load()
  if (!a || !names.length) return false
  const target = listWindowsIncludingMinimized().find((w) => names.includes(processName(w.pid)))
  if (!target) return false
  if (a.IsIconic(target.hwnd)) a.ShowWindow(target.hwnd, 9) // SW_RESTORE
  // 윈도우는 백그라운드 앱이 다른 창을 앞으로 가져오는 걸 막는다 → Alt 키를 한 번 눌렀다 떼면 허용된다 (널리 쓰는 우회)
  a.keybd_event(0x12, 0, 0, 0)
  a.keybd_event(0x12, 0, 0x0002, 0)
  return a.SetForegroundWindow(target.hwnd)
}

/** 지금 맨 앞(키보드 입력을 받는) 창. 내 프로세스 창이면 undefined */
export function foregroundWindow(): bigint | undefined {
  const a = load()
  if (!a) return undefined
  try {
    const h = toBig(a.GetForegroundWindow())
    if (!h) return undefined
    const pid = [0]
    a.GetWindowThreadProcessId(h, pid)
    return pid[0] && pid[0] !== process.pid ? h : undefined
  } catch {
    return undefined
  }
}

/** 이 창을 앞으로 (닫혔으면 false) */
export function focusWindow(hwnd: bigint): boolean {
  const a = load()
  if (!a || !a.IsWindow(hwnd)) return false
  if (a.IsIconic(hwnd)) a.ShowWindow(hwnd, 9) // SW_RESTORE
  a.keybd_event(0x12, 0, 0, 0) // Alt 우회 (focusProcessWindow 참고)
  a.keybd_event(0x12, 0, 0x0002, 0)
  return a.SetForegroundWindow(hwnd)
}

/** 최소화된 창도 포함 (앞으로 가져오기용) */
function listWindowsIncludingMinimized(): { hwnd: bigint; pid: number }[] {
  const a = load()
  if (!a) return []
  const out: { hwnd: bigint; pid: number }[] = []
  a.EnumWindows((raw: number | bigint) => {
    const h = toBig(raw)
    try {
      if (!a.IsWindowVisible(h)) return true
      const ex = Number(toBig(a.GetWindowLongPtrW(h, GWL_EXSTYLE)) & 0xffffffffn)
      if (ex & WS_EX_TOOLWINDOW) return true
      const pid = [0]
      a.GetWindowThreadProcessId(h, pid)
      out.push({ hwnd: h, pid: pid[0] })
    } catch {
      /* 무시 */
    }
    return true
  }, 0)
  return out
}
