// 펫 창: 캐릭터 그림 + 머리 위 표시(! / ••• / ✋) + 기분(✨/🌧) + 잠잘 때 zzz.
// 마우스: 누르면 main 에 알리고(드래그·던지기·클릭 판정은 main 이 커서를 읽어서 한다), 우클릭은 메뉴.
import { useEffect, useState } from 'react'
import type { PetFrameState } from '../../shared/ipc'
import { Sprite } from './Sprite'

export function Pet() {
  const [s, setS] = useState<PetFrameState | null>(null)
  useEffect(() => window.termpet.onPetState(setS), []) // main 이 보내는 모습 구독

  if (!s) return null
  return (
    <div
      className="pet"
      style={{ width: s.width, height: s.height }}
      onPointerDown={(e) => {
        if (e.button !== 0) return
        // 포인터 캡처: 마우스가 작은 펫 창 밖으로 나가도 놓는 순간(pointerup)을 받는다
        e.currentTarget.setPointerCapture(e.pointerId)
        window.termpet.petPointer('down')
      }}
      onPointerUp={(e) => e.button === 0 && window.termpet.petPointer('up')}
      onContextMenu={(e) => {
        e.preventDefault()
        window.termpet.petPointer('context')
      }}
    >
      <Sprite
        packKey={s.packKey}
        file={s.anim.file}
        frames={s.anim.frames}
        fps={s.anim.fps}
        loop={s.anim.loop}
        width={s.width}
        height={s.height}
        pixelArt={s.pixelArt}
        flip={s.flip}
        restartKey={s.actionSerial}
      />
      <Badge s={s} />
      {s.mood === 'cheerful' && <span className="mood cheerful">✨</span>}
      {s.mood === 'gloomy' && <span className="mood gloomy">🌧</span>}
      {s.action === 'sleep' && (
        <span className="zzz">
          <i>z</i>
          <i>z</i>
          <i>z</i>
        </span>
      )}
    </div>
  )
}

function Badge({ s }: { s: PetFrameState }) {
  const b = s.badge
  if (b.type === 'unread') return <span className="badge unread">!</span>
  if (b.type === 'working')
    return (
      <span className="badge working">
        <i />
        <i />
        <i />
        {b.count > 1 && <b>{b.count}</b>}
      </span>
    )
  if (b.type === 'waiting')
    return (
      <span className="badge waiting">
        ✋{b.count > 1 && <b>{b.count}</b>}
      </span>
    )
  return null
}
