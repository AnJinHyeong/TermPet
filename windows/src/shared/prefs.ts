// 패널 "설정·알림" 탭의 값들 (펫 크기·걷기 속도·말풍선 유지 시간) — 맥 PetPreferences.swift 와 같은 범위·기본값.
// 순수 값 + 범위 보정만 담당 → 테스트 가능. 화면 반영은 main/pet.ts 가 한다.

export interface PetPrefs {
  /** 캐릭터 크기 배율 (1 = 원래 크기) */
  sizeScale: number
  /** 걷기 속도 배율 */
  speedScale: number
  /** 말풍선이 떠 있는 시간(초) */
  bubbleSeconds: number
}

export const SIZE_RANGE: [number, number] = [0.6, 1.6]
export const SPEED_RANGE: [number, number] = [0.5, 2.0]
export const BUBBLE_RANGE: [number, number] = [2, 10]
export const DEFAULT_PREFS: PetPrefs = { sizeScale: 1, speedScale: 1, bubbleSeconds: 3 }

function clamp(v: unknown, [lo, hi]: [number, number], fallback: number): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) return fallback
  return Math.min(Math.max(v, lo), hi)
}

/** 저장된 값(빠졌거나 이상한 값 포함) → 범위 안의 값 */
export function normalizePrefs(p?: Partial<PetPrefs>): PetPrefs {
  return {
    sizeScale: clamp(p?.sizeScale, SIZE_RANGE, DEFAULT_PREFS.sizeScale),
    speedScale: clamp(p?.speedScale, SPEED_RANGE, DEFAULT_PREFS.speedScale),
    bubbleSeconds: clamp(p?.bubbleSeconds, BUBBLE_RANGE, DEFAULT_PREFS.bubbleSeconds),
  }
}

/** 캐릭터 원래 크기 × 배율 (반올림, 최소 24px) */
export function scaledSize(size: { width: number; height: number }, scale: number) {
  return { width: Math.max(24, Math.round(size.width * scale)), height: Math.max(24, Math.round(size.height * scale)) }
}
