// 같은 React 앱을 창마다 ?view= 로 나눠 쓴다 (펫 / 말풍선 / 트레이 패널) — 라우터 대신 간단한 분기
import { createRoot } from 'react-dom/client'
import { Bubble } from './Bubble'
import { Panel } from './Panel'
import { Pet } from './Pet'
import './styles.css'

const view = window.termpet.view
document.body.dataset.view = view
createRoot(document.getElementById('root')!).render(view === 'bubble' ? <Bubble /> : view === 'panel' ? <Panel /> : <Pet />)
