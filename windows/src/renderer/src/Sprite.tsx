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

  // requestAnimationFrame 으로 프레임 번호 갱신 (useEffect cleanup = 루프 정지)
  useEffect(() => {
    const start = performance.now()
    let raf = 0
    let last = -1
    const tick = () => {
      const f = frameIndex({ frames, fps, loop }, (performance.now() - start) / 1000)
      if (f !== last) setFrame((last = f))
      raf = requestAnimationFrame(tick)
    }
    tick()
    return () => cancelAnimationFrame(raf)
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
