// 좌표 도우미. 맥 앱(AppKit)과 같은 "y 위로 증가" 좌표를 쓴다 → Swift 물리 코드를 그대로 옮길 수 있게.
// Electron 화면 좌표(y 아래로 증가)와는 모델 y = -화면 y 로 바꿔 쓴다 (toModelRect / petScreenTop).
// React 비유: 화면 좌표 ↔ 내부 상태 좌표를 바꾸는 selector 함수 모음.

export type Direction = 'left' | 'right'
export const sign = (d: Direction) => (d === 'left' ? -1 : 1)
export const flipped = (d: Direction): Direction => (d === 'left' ? 'right' : 'left')

/** y 위로 증가하는 사각형. y = 아래쪽 끝(minY) */
export interface Rect {
  x: number
  y: number
  width: number
  height: number
}
export interface Point {
  x: number
  y: number
}
export interface Size {
  width: number
  height: number
}
export interface Vector {
  dx: number
  dy: number
}

export const minX = (r: Rect) => r.x
export const maxX = (r: Rect) => r.x + r.width
export const minY = (r: Rect) => r.y
export const maxY = (r: Rect) => r.y + r.height
export const midX = (r: Rect) => r.x + r.width / 2

export function contains(r: Rect, p: Point): boolean {
  return p.x >= r.x && p.x < maxX(r) && p.y >= r.y && p.y < maxY(r)
}

export function inset(r: Rect, d: number): Rect {
  return { x: r.x + d, y: r.y + d, width: r.width - 2 * d, height: r.height - 2 * d }
}

export function rectEquals(a: Rect | undefined, b: Rect | undefined): boolean {
  if (!a || !b) return a === b
  return a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height
}

/** Electron 화면 사각형(y 아래로) → 모델 사각형(y 위로) */
export function toModelRect(r: { x: number; y: number; width: number; height: number }): Rect {
  return { x: r.x, y: -(r.y + r.height), width: r.width, height: r.height }
}

/** 모델 발 위치(origin.y) → Electron 창의 위쪽 y */
export function petScreenTop(originY: number, height: number): number {
  return -originY - height
}

/** Electron 창 위쪽 y → 모델 발 위치 */
export function petOriginY(screenTop: number, height: number): number {
  return -(screenTop + height)
}
