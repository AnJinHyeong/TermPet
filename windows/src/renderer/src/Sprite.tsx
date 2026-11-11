// 스프라이트 시트(가로로 프레임이 이어진 PNG)를 background-position 으로 한 칸씩 보여준다.
import { useEffect, useState } from 'react'
import { frameIndex } from '../../shared/characterPack'
import type { TermPetBridge } from '../../shared/ipc'

declare global {
  interface Window {
    termpet: TermPetBridge
  }
}

export const packUrl = (packKey: string, file: string) =>
  `termpet://pack/${encodeURIComponent(packKey)}/${file.split('/').map(encodeURIComponent).join('/')}`

interface Props {
  packKey: string
  file: string
  frames: number
  fps: number
  loop?: boolean
  width: number
  height: number
  pixelArt?: boolean
  flip?: boolean
  /** 바뀌면 애니메이션을 처음 프레임부터 */
  restartKey?: unknown
}

export function Sprite({ packKey, file, frames, fps, loop = true, width, height, pixelArt, flip, restartKey }: Props) {
  const [frame, setFrame] = useState(0)

  // 그림의 fps 에 맞춰 setTimeout 으로 프레임 번호 갱신 (useEffect cleanup = 루프 정지).
  // 예전엔 requestAnimationFrame 이라 그림이 초당 6~12장만 바뀌어도 화면 주사율(60~144Hz)로 계속 돌았다.
  useEffect(() => {
    setFrame(0)
    if (frames <= 1 || fps <= 0) return // 한 장짜리는 돌릴 필요 없음
    const start = performance.now()
    let timer = 0
    let last = 0
    const tick = () => {
      const elapsed = (performance.now() - start) / 1000
      const f = frameIndex({ frames, fps, loop }, elapsed)
      if (f !== last) setFrame((last = f))
      if (!loop && f >= frames - 1) return // 한 번만 도는 동작은 마지막 프레임에서 멈춤
      // 다음 프레임 경계까지 기다린다 (밀림이 쌓이지 않게 경과 시간 기준)
      const next = (Math.floor(elapsed * fps) + 1) / fps
      timer = window.setTimeout(tick, Math.max(1, (next - elapsed) * 1000))
    }
    tick()
    return () => window.clearTimeout(timer)
  }, [packKey, file, frames, fps, loop, restartKey])

  return (
    <div
      style={{
        width,
        height,
        backgroundImage: `url("${packUrl(packKey, file)}")`,
        backgroundRepeat: 'no-repeat',
        // 시트 높이를 칸 높이에 맞춰 줄이고(가로는 비율대로), 프레임 칸만큼 왼쪽으로 민다
        backgroundSize: `auto ${height}px`,
        backgroundPosition: `${-frame * width}px 0`,
        imageRendering: pixelArt ? 'pixelated' : 'auto',
        transform: flip ? 'scaleX(-1)' : undefined,
      }}
    />
  )
}
