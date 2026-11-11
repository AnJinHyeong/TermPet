// main ↔ renderer 메시지 모양 (양쪽이 같은 타입을 import → props 타입 공유하듯)
import type { Animation, PetAction } from './characterPack'
import type { EventKind, EventSource } from './events'
import type { PetLayer } from './misc'
import type { PetPrefs } from './prefs'
import type { BubbleContent, PetMood } from './notifications'
import type { PetBadge, SessionState } from './sessions'

/** 펫 창에 그릴 모습 */
export interface PetFrameState {
  packKey: string
  action: PetAction
  /** 같은 동작이어도 새로 들어가면 애니메이션을 처음부터 (상태 진입 횟수) */
  actionSerial: number
  anim: Animation
  flip: boolean
  /** 장난꾸러기 모드: 포인터를 물고 흔드는 중 (몸 흔들기 + "앙!/으르릉") */
  biting: boolean
  pixelArt: boolean
  width: number
  height: number
  badge: PetBadge
  mood: PetMood
}

/** 말풍선 창 내용 */
export interface BubbleState {
  content: BubbleContent
  /** working = 알림이 아닌 펫의 혼잣말 */
  kind: EventKind
  badge: number
  tailX: number
  below: boolean
}

export interface PanelSession {
  id: string
  title: string
  source: EventSource
  state: SessionState
  since: number
}

/** 최근 알림 한 줄 (패널 "최근 알림") */
export interface PanelRecent {
  id: string
  title: string
  body: string
  kind: EventKind
  date: number
  /** 누르면 갈 프로젝트 창이 있는지 (없으면 마우스를 올렸을 때 본문 전체를 보여 줌) */
  hasTarget: boolean
}

export interface PanelFriend {
  key: string
  name: string
  thumbnail: string
  selected: boolean
}

export type IntegrationKind = 'claude' | 'claudeApp' | 'codex' | 'powershell'

/** [연결 확인] 한 단계: ok=true ✓ / false ✗ / null 참고 정보 */
export interface CheckStep {
  label: string
  ok: boolean | null
  detail?: string
}

export interface CheckResult {
  running: boolean
  ok?: boolean
  steps: CheckStep[]
  /** 패널에서 바로 고칠 수 있는 문제면 버튼 */
  fix?: { label: string; action: 'allowScripts' }
}

export interface PanelState {
  version: string
  friends: PanelFriend[]
  selectedName: string
  /** 무대에 보일 지금 캐릭터 (idle 그림) */
  stage?: { packKey: string; file: string; frames: number; fps: number; pixelArt: boolean; frameWidth: number; frameHeight: number }
  visible: boolean
  sleeping: boolean
  walkOnWindows: boolean
  walkOnWindowsAvailable: boolean
  /** 장난꾸러기 모드 (포인터 쫓기·물기·던지기) */
  mischief: boolean
  layer: PetLayer
  mood: PetMood
  server: { ok: boolean; text: string }
  statsLine?: string
  sessions: PanelSession[]
  /** 최근 알림 (최신 4개) */
  recent: PanelRecent[]
  prefs: PetPrefs
  integrations: { kind: IntegrationKind; title: string; subtitle: string; installed: boolean; needsUpdate: boolean; available: boolean; check?: CheckResult }[]
  quiet: { manualOn: boolean; duringMeetings: boolean; soundOnAsk: boolean; isQuiet: boolean }
  launchAtLogin: boolean
  update: { state: 'idle' | 'checking' | 'upToDate' | 'available' | 'updating' | 'failed'; version?: string; message?: string; latest?: string; checkedAt?: number }
  isDev: boolean
}

export type PanelAction =
  | { type: 'selectFriend'; key: string }
  | { type: 'importFriends' }
  | { type: 'friendMenu'; key: string }
  | { type: 'openFriendsFolder' }
  | { type: 'setVisible'; visible: boolean }
  | { type: 'toggleSleep' }
  | { type: 'toggleWalkOnWindows' }
  | { type: 'toggleMischief' }
  | { type: 'dropFromTop' }
  | { type: 'testNotification' }
  | { type: 'toggleIntegration'; kind: IntegrationKind; remove: boolean }
  | { type: 'checkIntegration'; kind: IntegrationKind }
  | { type: 'fixIntegration'; kind: IntegrationKind; action: 'allowScripts' }
  | { type: 'quietManual' }
  | { type: 'quietMeetings' }
  | { type: 'soundOnAsk' }
  | { type: 'setLayer'; layer: PetLayer }
  | { type: 'focusSession'; id: string }
  | { type: 'focusRecent'; id: string }
  | { type: 'clearRecent' }
  | { type: 'setPrefs'; prefs: Partial<PetPrefs> }
  | { type: 'setLaunchAtLogin'; on: boolean }
  | { type: 'checkUpdate' }
  | { type: 'update' }
  | { type: 'debug'; kind: 'happy' | 'angry' | 'ask' }
  | { type: 'quit' }

/** preload 가 window.termpet 으로 열어 주는 API */
export interface TermPetBridge {
  view: 'pet' | 'bubble' | 'panel'
  // 펫
  onPetState(cb: (s: PetFrameState) => void): () => void
  petPointer(type: 'down' | 'up' | 'context'): void
  // 말풍선
  onBubbleState(cb: (s: BubbleState) => void): () => void
  onChime(cb: () => void): () => void
  bubbleSize(width: number, height: number): void
  bubbleClick(target: 'body' | 'close'): void
  // 패널
  onPanelState(cb: (s: PanelState) => void): () => void
  panelAction(a: PanelAction): void
  panelSize(height: number): void
}
