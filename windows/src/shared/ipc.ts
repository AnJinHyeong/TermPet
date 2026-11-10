// main → renderer 로 보내는 메시지 모양 (양쪽이 같은 타입을 import → props 타입 공유하듯)
import type { Animation, PetAction } from './characterPack'

export interface PetFrameState {
  packKey: string
  action: PetAction
  anim: Animation
  flip: boolean
  pixelArt: boolean
  frameWidth: number
  frameHeight: number
  /** 창(=그림) 크기 px */
  width: number
  height: number
}

export interface TermPetBridge {
  onState(cb: (s: PetFrameState) => void): () => void
}
