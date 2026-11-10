// 작은 순수 로직 모음: 조용한 시간, 마이크 사용 판정, 표시 층, 말풍선 위치, 업데이트 버전 비교, 친구 폴더 이름.

// MARK: - 조용한 시간 (맥 QuietMode.swift)

export const QUIET_MANUAL_MS = 60 * 60_000

export function isQuiet(now: number, manualUntil: number | undefined, duringMeetings: boolean, micInUse: boolean): boolean {
  if (manualUntil !== undefined && now < manualUntil) return true
  return duringMeetings && micInUse
}

/**
 * 마이크를 지금 어떤 앱이든 쓰고 있는지 — `reg query ...\CapabilityAccessManager\ConsentStore\microphone /s /v LastUsedTimeStop` 결과 해석.
 * 쓰는 중인 앱은 LastUsedTimeStop 이 0 이다. (녹음이 아니라 상태만 읽어서 권한 불필요)
 */
export function micInUseFromRegQuery(output: string): boolean {
  return output.split(/\r?\n/).some((l) => /LastUsedTimeStop\s+REG_QWORD\s+0x0+\s*$/i.test(l))
}

// MARK: - 표시 층 (맥 PetWindowLayer.swift)

export type PetLayer = 'aboveApps' | 'desktop' | 'desktopPopUp'
export const LAYERS: { id: PetLayer; title: string; short: string }[] = [
  { id: 'aboveApps', title: '프로그램 위에 표시', short: '항상 위' },
  { id: 'desktop', title: '바탕화면에만 표시', short: '바탕화면' },
  { id: 'desktopPopUp', title: '바탕화면에만 + 알림 시 앞으로', short: '알림 때만 위' },
]

export function effectiveLayer(setting: PetLayer, bubbleShowing: boolean): PetLayer {
  return bubbleShowing && setting === 'desktopPopUp' ? 'aboveApps' : setting
}

// MARK: - 말풍선 위치 (맥 BubblePlacement.swift, 여기는 Electron 화면 좌표: y 아래로 증가)

export interface ScreenRect {
  x: number
  y: number
  width: number
  height: number
}

export function placeBubble(size: { width: number; height: number }, pet: ScreenRect, screen: ScreenRect) {
  const margin = 4
  const overlap = 14 // 펫 창 위쪽은 장식(!, zzz) 공간이라 살짝 겹쳐 올린다
  const tailInset = 24
  let x = pet.x + pet.width / 2 - size.width / 2
  x = Math.min(Math.max(x, screen.x + margin), screen.x + screen.width - size.width - margin)
  let y = pet.y + overlap - size.height
  let below = false
  if (y < screen.y + margin) {
    below = true // 위에 공간이 없으면 아래에
    y = pet.y + pet.height - overlap / 2
  }
  const tailX = Math.min(Math.max(pet.x + pet.width / 2 - x, tailInset), size.width - tailInset)
  return { x: Math.round(x), y: Math.round(y), tailX, below }
}

// MARK: - 업데이트 (맥 AppUpdater.swift)

export const normalizeVersion = (v: string) => v.trim().replace(/^[vV]+/, '')

/** 숫자 단위 비교 ("0.10.0" > "0.9.9"). 숫자가 아니면 false */
export function isNewer(latest: string, current: string): boolean {
  const parts = (s: string) => {
    const c = normalizeVersion(s).split('.').map(Number)
    return c.length && c.every((n) => Number.isInteger(n)) ? c : undefined
  }
  const a = parts(latest)
  const b = parts(current)
  if (!a || !b) return false
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] ?? 0
    const y = b[i] ?? 0
    if (x !== y) return x > y
  }
  return false
}

/** GitHub 릴리스 JSON → { tag, 윈도우 설치 파일 주소 } */
export function parseRelease(json: unknown): { tag: string; installerUrl?: string } | undefined {
  const o = json as { tag_name?: unknown; assets?: { name?: unknown; browser_download_url?: unknown }[] }
  if (typeof o?.tag_name !== 'string') return undefined
  const asset = (Array.isArray(o.assets) ? o.assets : []).find((a) => typeof a?.name === 'string' && /^TermPet-Setup-.*\.exe$/i.test(a.name))
  return { tag: o.tag_name, installerUrl: typeof asset?.browser_download_url === 'string' ? asset.browser_download_url : undefined }
}

// MARK: - 친구 팩 가져오기

/** 팩 id → 폴더 이름 (경로 문자 제거) */
export function safeFolderName(id: string): string {
  const name = id.replace(/[/\\:]/g, '_').replace(/^[. ]+|[. ]+$/g, '')
  return name || 'friend'
}

