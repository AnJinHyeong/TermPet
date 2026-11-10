// 펫이 다니는 지형 = 화면 바닥 + 앱 창 윗면(선반) + 창 옆면(벽).
// 맥 앱 ScreenLayout.swift · Terrain.swift 를 그대로 옮김 (y 위로 증가 좌표, geometry.ts 참고).
// React 비유: 창 목록에서 파생된 useMemo 값. 창 목록이 바뀌면 새로 만든다.
import { contains, inset, maxX, maxY, minX, minY, sign, type Direction, type Rect, type Size } from './geometry'

/** 화면에 떠 있는 앱 창 하나 */
export interface WindowBox {
  id: number
  frame: Rect
  /** 창 주인 프로세스 id (0 = 모름) */
  owner?: number
}

// MARK: - 모니터 배치

export class ScreenLayout {
  static readonly adjacencyTolerance = 2
  /** 각 화면에서 펫이 다닐 수 있는 영역 (아래 = 바닥) */
  constructor(readonly frames: Rect[]) {}

  /** 펫 발 위치(x, y)를 포함하는 화면. y는 바닥 바로 아래 1pt까지 허용 */
  indexContaining(x: number, y: number): number | undefined {
    const i = this.frames.findIndex((f) => x >= minX(f) && x < maxX(f) && y >= minY(f) - 1 && y < maxY(f))
    return i < 0 ? undefined : i
  }

  /** x가 가로 범위에 들어가는 화면들 */
  indicesInColumn(x: number): number[] {
    return this.frames.flatMap((f, i) => (minX(f) <= x && x < maxX(f) ? [i] : []))
  }

  nearestIndex(x: number): number | undefined {
    let best: number | undefined
    let bestD = Infinity
    this.frames.forEach((f, i) => {
      const d = x < minX(f) ? minX(f) - x : x >= maxX(f) ? x - maxX(f) : 0
      if (d < bestD) {
        bestD = d
        best = i
      }
    })
    return best
  }

  /** i번 화면의 side 쪽에 붙은 화면. y를 주면 그 높이가 이웃 화면 안에 있어야 한다 */
  neighbor(i: number, side: Direction, y?: number): number | undefined {
    const f = this.frames[i]
    const tol = ScreenLayout.adjacencyTolerance
    const j = this.frames.findIndex((g, k) => {
      if (k === i) return false
      const touching = side === 'right' ? Math.abs(minX(g) - maxX(f)) < tol : Math.abs(maxX(g) - minX(f)) < tol
      if (!touching) return false
      if (y !== undefined) return y >= minY(g) - 1 && y < maxY(g)
      return minY(g) < maxY(f) && minY(f) < maxY(g)
    })
    return j < 0 ? undefined : j
  }

  /** x 위치에서 fromY 높이부터 떨어질 때 착지할 바닥 y */
  landingFloor(x: number, fromY: number): number | undefined {
    const column = this.indicesInColumn(x).map((i) => minY(this.frames[i]))
    const below = column.filter((y) => y <= fromY + 1)
    if (below.length) return Math.max(...below)
    if (column.length) return Math.min(...column)
    const n = this.nearestIndex(x)
    return n === undefined ? undefined : minY(this.frames[n])
  }
}

// MARK: - 지형

export interface Ledge {
  minX: number
  maxX: number
  y: number
  windowID: number
}
export interface Wall {
  /** 벽면 x (펫 몸이 닿는 선) */
  x: number
  /** 벽 꼭대기 y */
  top: number
  /** 창 벽이면 창 id, 화면 끝이면 null */
  windowID: number | null
  /** 벽이 펫의 어느 쪽에 있는지 */
  side: Direction
}
export interface Floor {
  y: number
  windowID: number | null
}

const ledgeContains = (l: Ledge, x: number) => x >= l.minX && x <= l.maxX

export class Terrain {
  static readonly minLedgeRatio = 0.6
  readonly ledges: Ledge[]

  /** windows: 앞(위에 그려진 창) → 뒤 순서 */
  constructor(
    readonly screens: ScreenLayout,
    readonly windows: WindowBox[] = [],
    readonly petSize: Size = { width: 80, height: 80 },
  ) {
    this.ledges = windows.flatMap((_, i) => this.computeLedges(i))
  }

  window(id: number): WindowBox | undefined {
    return this.windows.find((w) => w.id === id)
  }

  private computeLedges(i: number): Ledge[] {
    const f = this.windows[i].frame
    const y = maxY(f)
    // 1) 윗변이 들어가는 화면에서 머리 위 공간(펫 키의 80%)이 남는 부분만
    let spans: [number, number][] = this.screens.frames.flatMap((s): [number, number][] => {
      if (!(y >= minY(s) && y + this.petSize.height * 0.8 <= maxY(s))) return []
      const lo = Math.max(minX(f), minX(s))
      const hi = Math.min(maxX(f), maxX(s))
      return lo < hi ? [[lo, hi]] : []
    })
    // 2) 앞 창이 윗변 선을 덮는 부분은 뺀다
    for (let j = 0; j < i; j++) {
      const g = this.windows[j].frame
      if (!(minY(g) <= y + 1 && maxY(g) > y + 1)) continue
      spans = spans.flatMap((a) => subtract(a, [minX(g), maxX(g)]))
    }
    const minWidth = this.petSize.width * Terrain.minLedgeRatio
    return spans.filter(([a, b]) => b - a >= minWidth).map(([a, b]) => ({ minX: a, maxX: b, y, windowID: this.windows[i].id }))
  }

  /** 펫 발(가로 중심 x, 높이 y)이 올라서 있는 창 선반 */
  ledge(x: number, y: number, windowID?: number): Ledge | undefined {
    return this.ledges.find((l) => Math.abs(l.y - y) < 1.5 && ledgeContains(l, x) && (windowID === undefined || l.windowID === windowID))
  }

  /** fromY → toY 로 떨어지는 동안 처음 닿는 바닥 */
  landing(x: number, fromY: number, toY: number): Floor | undefined {
    let best: Floor | undefined
    for (const l of this.ledges) {
      if (ledgeContains(l, x) && l.y <= fromY + 0.5 && l.y >= toY && (!best || l.y > best.y)) best = { y: l.y, windowID: l.windowID }
    }
    const floorY = this.screens.landingFloor(x, fromY)
    if (floorY !== undefined && (floorY >= toY || floorY > fromY) && (!best || floorY > best.y)) best = { y: floorY, windowID: null }
    return best
  }

  /** 몸 왼쪽 x가 oldX → newX 로 움직일 때 부딪히는 첫 창 옆면 */
  windowWall(oldX: number, newX: number, feetY: number, direction: Direction): Wall | undefined {
    const w = this.petSize.width
    let hit: Wall | undefined
    this.windows.forEach((box, i) => {
      const f = box.frame
      if (!(minY(f) < feetY + this.petSize.height * 0.6 && maxY(f) > feetY + 4)) return
      let sideX: number
      if (direction === 'right') {
        sideX = minX(f)
        if (!(oldX + w <= sideX + 0.5 && newX + w > sideX)) return
      } else {
        sideX = maxX(f)
        if (!(oldX >= sideX - 0.5 && newX < sideX)) return
      }
      // 벽 중간이 앞 창에 가려 있으면 안 보이는 벽 → 무시
      if (this.isCovered({ x: sideX, y: Math.min(maxY(f), feetY + this.petSize.height / 2) }, i)) return
      const wall: Wall = { x: sideX, top: maxY(f), windowID: box.id, side: direction }
      if (!hit || (direction === 'right' ? sideX < hit.x : sideX > hit.x)) hit = wall
    })
    return hit
  }

  /** i번 창보다 앞에 있는 창이 점을 덮는지 */
  isCovered(p: { x: number; y: number }, i: number): boolean {
    return this.windows.slice(0, i).some((w) => contains(inset(w.frame, -1), p))
  }

  /** 창 벽을 다 오른 뒤 올라설 선반 */
  ledgeAfterClimbing(wall: Wall): Ledge | undefined {
    if (wall.windowID === null) return undefined
    const x = wall.x + sign(wall.side) * (this.petSize.width * 0.5 + 1)
    return this.ledges.find((l) => l.windowID === wall.windowID && Math.abs(l.y - wall.top) < 1.5 && ledgeContains(l, x))
  }

  /** 창 벽을 오를 때 머리가 막히는 높이(발 기준). 막는 앞 창이 없으면 undefined */
  climbCeiling(wall: Wall, feetY: number): number | undefined {
    if (wall.windowID === null) return undefined
    const i = this.windows.findIndex((w) => w.id === wall.windowID)
    if (i < 0) return undefined
    const ys = this.windows
      .slice(0, i)
      .map((g) => g.frame)
      .filter((f) => minX(f) - 1 <= wall.x && wall.x <= maxX(f) + 1 && maxY(f) > feetY + 1 && minY(f) < wall.top && minY(f) >= feetY - 1)
      .map((f) => minY(f) - this.petSize.height)
    return ys.length ? Math.min(...ys) : undefined
  }

  /** 화면 위쪽 끝 */
  ceiling(x: number): number | undefined {
    const ys = this.screens.indicesInColumn(x).map((i) => maxY(this.screens.frames[i]))
    return ys.length ? Math.max(...ys) : undefined
  }
}

function subtract(a: [number, number], b: [number, number]): [number, number][] {
  if (!(b[0] < a[1] && b[1] > a[0])) return [a]
  const out: [number, number][] = []
  if (b[0] > a[0]) out.push([a[0], b[0]])
  if (b[1] < a[1]) out.push([b[1], a[1]])
  return out
}

/**
 * 전체 화면 창이 있는지: 화면을 꽉 채우는 창 (윈도우는 전체 화면이면 작업표시줄이 숨는다 → 맨 바닥까지 내려감).
 * screen: 그 모니터의 전체 영역(bounds)
 */
export function hasFullscreenWindow(windows: WindowBox[], screen: Rect): boolean {
  return windows.some(
    (w) => minX(w.frame) <= minX(screen) + 2 && maxX(w.frame) >= maxX(screen) - 2 && minY(w.frame) <= minY(screen) + 2 && maxY(w.frame) >= maxY(screen) - 2,
  )
}
