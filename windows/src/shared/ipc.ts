// main ↔ renderer 메시지 모양 (양쪽이 같은 타입을 import → props 타입 공유하듯)
import type { Animation, PetAction } from './characterPack'
import type { EventKind, EventSource } from './events'
import type { PetLayer } from './misc'
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

export interface PanelFriend {
  key: string
  name: string
  thumbnail: string
  selected: boolean
}

export type IntegrationKind = 'claude' | 'codex' | 'powershell'

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
  layer: PetLayer
  mood: PetMood
  server: { ok: boolean; text: string }
  statsLine?: string
  sessions: PanelSession[]
  integrations: { kind: IntegrationKind; title: string; subtitle: string; installed: boolean; needsUpdate: boolean; available: boolean }[]
  quiet: { manualOn: boolean; duringMeetings: boolean; soundOnAsk: boolean; isQuiet: boolean }
  launchAtLogin: boolean
  update: { state: 'idle' | 'checking' | 'upToDate' | 'available' | 'updating' | 'failed'; version?: string; message?: string }
  isDev: boolean
}

export type PanelAction =
  | { type: 'selectFriend'; key: string }
  | { type: 'importFriends' }
  | { type: 'openFriendsFolder' }
  | { type: 'setVisible'; visible: boolean }
  | { type: 'toggleSleep' }
  | { type: 'toggleWalkOnWindows' }
  | { type: 'dropFromTop' }
  | { type: 'testNotification' }
  | { type: 'toggleIntegration'; kind: IntegrationKind; remove: boolean }
  | { type: 'quietManual' }
  | { type: 'quietMeetings' }
  | { type: 'soundOnAsk' }
  | { type: 'setLayer'; layer: PetLayer }
  | { type: 'focusSession'; id: string }
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
