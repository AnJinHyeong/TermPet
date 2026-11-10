// 펫 그림: 스프라이트 시트(가로로 프레임이 이어진 PNG)를 background-position 으로 한 칸씩 보여준다.
import { useEffect, useState } from 'react'
import { frameIndex } from '../../shared/characterPack'
import type { PetFrameState, TermPetBridge } from '../../shared/ipc'

declare global {
  interface Window {
    termpet: TermPetBridge
  }
}

export function App() {
  const [state, setState] = useState<PetFrameState | null>(null)
  const [frame, setFrame] = useState(0)

  // main 이 보내는 모습 변경 구독 (useEffect cleanup = 구독 해제)
  useEffect(() => window.termpet.onState(setState), [])

  // 포즈가 바뀌면 처음 프레임부터, requestAnimationFrame 으로 프레임 번호 갱신
  useEffect(() => {
    if (!state) return
    const start = performance.now()
    let raf = 0
    const tick = () => {
      setFrame(frameIndex(state.anim, (performance.now() - start) / 1000))
      raf = requestAnimationFrame(tick)
    }
    tick()
    return () => cancelAnimationFrame(raf)
  }, [state?.packKey, state?.anim.file, state?.action])

  if (!state) return null
  const { anim, width, height } = state
  const src = `termpet://pack/${encodeURIComponent(state.packKey)}/${anim.file.split('/').map(encodeURIComponent).join('/')}`
  return (
    <div
      style={{
        width,
        height,
        backgroundImage: `url("${src}")`,
        backgroundRepeat: 'no-repeat',
        // 시트 높이를 창 높이에 맞춰 줄이고(가로는 비율대로), 프레임 칸만큼 왼쪽으로 민다
        backgroundSize: `auto ${height}px`,
        backgroundPosition: `${-frame * width}px 0`,
        imageRendering: state.pixelArt ? 'pixelated' : 'auto',
        transform: state.flip ? 'scaleX(-1)' : undefined,
      }}
    />
  )
}
