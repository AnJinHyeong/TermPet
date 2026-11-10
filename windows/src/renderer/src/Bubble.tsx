// 말풍선 창: 제목(프로젝트) · 본문 · 보조 설명 · +N 배지 · × 닫기. 크기를 재서 main 에 알려 창을 맞춘다.
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { BubbleState } from '../../shared/ipc'

const ICON: Record<string, string> = { done: '✔', error: '⚠', ask: '✋', working: '💬', ended: '💬' }

export function Bubble() {
  const [s, setS] = useState<BubbleState | null>(null)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => window.termpet.onBubbleState(setS), [])
  useEffect(() => window.termpet.onChime(chime), [])

  // 그린 뒤 실제 크기를 재서 창 크기를 맞춘다 (ResizeObserver ≈ 크기 변화 구독)
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const report = () => window.termpet.bubbleSize(el.offsetWidth, el.offsetHeight)
    report()
    const ro = new ResizeObserver(report)
    ro.observe(el)
    return () => ro.disconnect()
  }, [s !== null])

  if (!s) return null
  return (
    <div ref={ref} className={`bubble-wrap ${s.below ? 'below' : 'above'}`}>
      <div className={`bubble kind-${s.kind}`} onClick={() => window.termpet.bubbleClick('body')}>
        <div className="bubble-title">
          <span className="icon">{ICON[s.kind]}</span>
          <span className="title">{s.content.title}</span>
          {s.badge > 0 && <span className="count">+{s.badge}</span>}
          <button
            className="close"
            title="닫기"
            onClick={(e) => {
              e.stopPropagation()
              window.termpet.bubbleClick('close')
            }}
          >
            ×
          </button>
        </div>
        <div className="bubble-body">{s.content.body}</div>
        {s.content.detail && <div className="bubble-detail">{s.content.detail}</div>}
        <span className="tail" style={{ left: s.tailX - 8 - 7 }} />
      </div>
    </div>
  )
}

/** 권한 요청 알림음: 유리잔 같은 두 음 (Web Audio 로 직접 합성 → 소리 파일 불필요) */
function chime() {
  try {
    const ctx = new AudioContext()
    const play = (freq: number, at: number) => {
      const o = ctx.createOscillator()
      const g = ctx.createGain()
      o.type = 'sine'
      o.frequency.value = freq
      g.gain.setValueAtTime(0.0001, ctx.currentTime + at)
      g.gain.exponentialRampToValueAtTime(0.25, ctx.currentTime + at + 0.01)
      g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + at + 0.6)
      o.connect(g).connect(ctx.destination)
      o.start(ctx.currentTime + at)
      o.stop(ctx.currentTime + at + 0.65)
    }
    play(1318.5, 0)
    play(1760, 0.12)
    setTimeout(() => void ctx.close(), 1200)
  } catch {
    /* 소리 장치가 없으면 무시 */
  }
}
