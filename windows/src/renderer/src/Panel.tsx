// 트레이 아이콘을 누르면 뜨는 패널 (맥 MenuPanelView.swift 와 같은 구성).
// 무대(지금 캐릭터) → 업데이트 → 진행 중 → 최근 알림 → 빠른 칩 → 탭(친구·알림·연결·설정) → 하단
// 윈도우에만 있는 것: 연결 탭의 [확인] 진단, 친구 탭의 "폴더 열기" (맥의 "Dock 정확히"는 맥 전용이라 없음)
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import type { EventKind } from '../../shared/events'
import { timeAgo } from '../../shared/history'
import type { CheckResult, IntegrationKind, PanelAction, PanelState } from '../../shared/ipc'
import { LAYERS } from '../../shared/misc'
import { formatDuration } from '../../shared/notifications'
import { BUBBLE_RANGE, DEFAULT_PREFS, SIZE_RANGE, SPEED_RANGE } from '../../shared/prefs'
import { packUrl, Sprite } from './Sprite'

const act = (a: PanelAction) => window.termpet.panelAction(a)

export function Panel() {
  const [s, setS] = useState<PanelState | null>(null)
  const [now, setNow] = useState(Date.now())
  const [tab, setTab] = useState<PanelTab>(loadTab)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => window.termpet.onPanelState(setS), [])
  // 30초마다 다시 그려 "3분" 같은 시간 갱신 (≈ 맥 TimelineView)
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 30_000)
    return () => clearInterval(t)
  }, [])
  // 내용 높이를 main 에 알려 창 높이를 맞춘다
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const ro = new ResizeObserver(() => window.termpet.panelSize(el.offsetHeight + 16))
    ro.observe(el)
    return () => ro.disconnect()
  }, [s !== null])

  const selectTab = (t: PanelTab) => {
    setTab(t)
    saveTab(t)
  }

  if (!s) return null
  return (
    <div className="panel-outer">
      <div ref={ref} className="panel">
        <Stage s={s} />

        {(s.update.state === 'available' || s.update.state === 'updating') && (
          <div className="update-banner">
            <span className="spark">✨</span>
            <div className="grow">
              <div className="strong">{s.update.state === 'available' ? `새 버전 v${s.update.version}이 나왔어요` : '업데이트 중…'}</div>
              <div className="sub">{s.update.state === 'available' ? `지금 버전 v${s.version}` : '잠시 꺼졌다가 다시 켜져요'}</div>
            </div>
            {s.update.state === 'available' && (
              <button className="pill" onClick={() => act({ type: 'update' })}>
                업데이트
              </button>
            )}
          </div>
        )}

        {/* 진행 중인 AI 세션이 있을 때만 (누르면 그 프로젝트 창으로 이동) */}
        {s.sessions.length > 0 && (
          <>
            <Label icon="✦">진행 중</Label>
            <Card>
              {s.sessions.map((x) => (
                <button key={x.id} className="session-row" onClick={() => act({ type: 'focusSession', id: x.id })} title="이 프로젝트 창으로 이동">
                  <span className={`session-icon ${x.state}`}>{STATE_ICON[x.state]}</span>
                  <span className="grow">
                    <span className="strong">{x.title}</span>
                    <span className="sub">
                      {x.source === 'claude' ? 'Claude Code' : x.source === 'codex' ? 'Codex' : '터미널'} · {STATE_TEXT[x.state]} · {elapsed(now - x.since)}
                    </span>
                  </span>
                  <span className="go">↗</span>
                </button>
              ))}
            </Card>
          </>
        )}

        {/* 최근 알림: 말풍선을 놓쳤어도 여기서 다시 보고 그 창으로 이동 */}
        {s.recent.length > 0 && (
          <>
            <div className="label-row">
              <Label icon="🕘">최근 알림</Label>
              <button className="label-action" onClick={() => act({ type: 'clearRecent' })}>
                지우기
              </button>
            </div>
            <Card>
              {s.recent.map((r) => (
                <button key={r.id} className="session-row" onClick={() => act({ type: 'focusRecent', id: r.id })} title={r.hasTarget ? '이 프로젝트 창으로 이동' : r.body}>
                  <span className={`session-icon ${RECENT_STATE[r.kind] ?? 'done'}`}>{STATE_ICON[RECENT_STATE[r.kind] ?? 'done']}</span>
                  <span className="grow">
                    <span className="strong">{r.title}</span>
                    <span className="sub">{r.body}</span>
                  </span>
                  <span className="ago">{timeAgo(now - r.date)}</span>
                </button>
              ))}
            </Card>
          </>
        )}

        {/* 자주 쓰는 것만 한 줄로 */}
        <div className="chips three quick">
          <Chip icon={s.sleeping ? '☀️' : '🌙'} on={s.sleeping} hint={s.sleeping ? '깨워서 다시 놀게 해요' : '쿨쿨 재워요'} onClick={() => act({ type: 'toggleSleep' })}>
            {s.sleeping ? '깨우기' : '재우기'}
          </Chip>
          <Chip icon="💤" on={s.quiet.manualOn} hint="1시간 동안 알림을 모아뒀다 보여줘요" onClick={() => act({ type: 'quietManual' })}>
            1시간 조용히
          </Chip>
          <Chip icon="☁️" hint="하늘에서 뚝! 창 위에 떨어지면 거기서 놀아요" onClick={() => act({ type: 'dropFromTop' })}>
            떨어뜨리기
          </Chip>
        </div>

        {/* 나머지는 탭 안으로 (탭 상태 하나로 아래 내용을 조건부 렌더링) */}
        <div className="tabs">
          {TABS.map((t) => (
            <button key={t.id} className={`tab ${tab === t.id ? 'on' : ''}`} onClick={() => selectTab(t.id)}>
              <span className="tab-icon">{t.icon}</span>
              {t.title}
              {/* 연결 탭: 업데이트가 필요한 연결이 있으면 빨간 점 */}
              {t.id === 'connect' && s.integrations.some((i) => i.needsUpdate) && <span className="tab-dot" />}
            </button>
          ))}
        </div>
        <div className="tab-body">
          {tab === 'friends' && <FriendsTab s={s} />}
          {tab === 'alerts' && <AlertsTab s={s} />}
          {tab === 'connect' && <ConnectTab s={s} />}
          {tab === 'settings' && <SettingsTab s={s} />}
        </div>

        <div className="footer">
          <label className="check">
            <input type="checkbox" checked={s.launchAtLogin} onChange={(e) => act({ type: 'setLaunchAtLogin', on: e.target.checked })} />
            로그인 시 실행
          </label>
          <span className="grow" />
          <button className="version" title={versionHint(s)} onClick={() => act({ type: 'checkUpdate' })}>
            {versionLabel(s)}
          </button>
          <button className="quit" onClick={() => act({ type: 'quit' })}>
            ⏻ 종료
          </button>
        </div>
      </div>
    </div>
  )
}

// MARK: - 탭 (맥 PanelTab 과 같은 순서·이름)

type PanelTab = 'friends' | 'alerts' | 'connect' | 'settings'
const TABS: { id: PanelTab; title: string; icon: string }[] = [
  { id: 'friends', title: '친구', icon: '♥' },
  { id: 'alerts', title: '알림', icon: '🔔' },
  { id: 'connect', title: '연결', icon: '🔗' },
  { id: 'settings', title: '설정', icon: '🎚' },
]

/** 마지막으로 연 탭 기억 (맥 @AppStorage("panelTab")). 저장소가 막혀 있어도 패널은 그대로 동작 */
function loadTab(): PanelTab {
  try {
    const t = localStorage.getItem('panelTab')
    if (TABS.some((x) => x.id === t)) return t as PanelTab
  } catch {
    /* 저장소를 못 쓰면 기본 탭 */
  }
  return 'friends'
}
function saveTab(t: PanelTab) {
  try {
    localStorage.setItem('panelTab', t)
  } catch {
    /* 기억 못 해도 괜찮음 */
  }
}

function FriendsTab({ s }: { s: PanelState }) {
  return (
    <Card>
      <div className="friends">
        {s.friends.map((f) => (
          <button
            key={f.key}
            className={`friend ${f.selected ? 'selected' : ''}`}
            title={f.key.startsWith('friend.') ? `${f.name} · 우클릭하면 삭제` : f.name}
            onClick={() => act({ type: 'selectFriend', key: f.key })}
            onContextMenu={(e) => {
              e.preventDefault()
              act({ type: 'friendMenu', key: f.key })
            }}
          >
            <span className="thumb" style={{ backgroundImage: `url("${packUrl(f.key, f.thumbnail)}")` }} />
            {f.selected && <span className="heart">♥</span>}
          </button>
        ))}
        <button className="friend add" title="친구 추가하기 (zip 파일 고르기)" onClick={() => act({ type: 'importFriends' })}>
          +
        </button>
      </div>
      <div className="friend-name">
        <span className="heart-sm">♥</span> {s.selectedName}
        <button className="link" onClick={() => act({ type: 'openFriendsFolder' })}>
          폴더 열기
        </button>
      </div>
    </Card>
  )
}

function AlertsTab({ s }: { s: PanelState }) {
  return (
    <>
      <div className="chips three">
        <Chip icon="🎥" on={s.quiet.duringMeetings} hint="마이크 사용 중(회의)엔 알림을 모아둬요" onClick={() => act({ type: 'quietMeetings' })}>
          회의 중
        </Chip>
        <Chip icon={s.quiet.soundOnAsk ? '🔊' : '🔇'} on={s.quiet.soundOnAsk} hint="Claude가 권한을 물으면 소리로 알려줘요" onClick={() => act({ type: 'soundOnAsk' })}>
          권한 소리
        </Chip>
        <Chip icon="💬" hint="말풍선을 한 번 띄워 봐요" onClick={() => act({ type: 'testNotification' })}>
          알림 테스트
        </Chip>
      </div>
      {s.quiet.isQuiet && <div className="note">{s.quiet.manualOn ? '조용한 시간' : '회의 중이라 조용히'} · 알림은 펫 머리 위 !에 모여요</div>}
      <div className="card spaced">
        <PrefSlider icon="⏱" title="말풍선 유지" value={s.prefs.bubbleSeconds} range={BUBBLE_RANGE} step={1} defaultValue={DEFAULT_PREFS.bubbleSeconds} label={(v) => `${Math.round(v)}초`} onCommit={(v) => act({ type: 'setPrefs', prefs: { bubbleSeconds: v } })} />
      </div>
    </>
  )
}

function ConnectTab({ s }: { s: PanelState }) {
  return (
    <Card>
      {s.integrations.map((i) => (
        <div key={i.kind}>
          <div className={`integration ${i.available ? '' : 'disabled'}`}>
            <span className={`int-icon ${i.kind}`} title={`${i.subtitle} 알림`}>
              {i.kind === 'claude' ? '✳' : i.kind === 'claudeApp' ? '💬' : i.kind === 'codex' ? '</>' : i.kind === 'chatgptApp' ? '🗨' : '>_'}
            </span>
            <span className="grow">
              <span className="strong">{i.title}</span>
              <span className="sub">{i.subtitle}</span>
            </span>
            {!i.available ? (
              <span className="sub">설치 안 됨</span>
            ) : (
              <>
                <button
                  className="diag-btn"
                  title="이 PC에서 알림이 실제로 오는지 처음부터 끝까지 확인"
                  disabled={i.check?.running}
                  onClick={() => act({ type: 'checkIntegration', kind: i.kind })}
                >
                  {i.check?.running ? '…' : '확인'}
                </button>
                <button
                  className={`connect ${i.installed ? 'on' : ''}`}
                  title={i.needsUpdate ? '이 PC에 맞는 형식으로 바꾸기 (백업 후)' : i.installed ? '누르면 연결 해제 (설정 파일 백업 후)' : '누르면 연결 (설정 파일 백업 후)'}
                  onClick={() => act({ type: 'toggleIntegration', kind: i.kind, remove: i.installed && !i.needsUpdate })}
                >
                  {i.needsUpdate ? '⟳ 업데이트' : i.installed ? '✓ 연결됨' : '연결'}
                </button>
              </>
            )}
          </div>
          {i.check && <CheckView kind={i.kind} check={i.check} />}
        </div>
      ))}
    </Card>
  )
}

function SettingsTab({ s }: { s: PanelState }) {
  return (
    <>
      <div className="card prefs">
        <PrefSlider icon="↔" title="크기" value={s.prefs.sizeScale} range={SIZE_RANGE} step={0.1} defaultValue={DEFAULT_PREFS.sizeScale} label={(v) => `${Math.round(v * 100)}%`} onCommit={(v) => act({ type: 'setPrefs', prefs: { sizeScale: v } })} />
        <PrefSlider icon="🐇" title="걷기 속도" value={s.prefs.speedScale} range={SPEED_RANGE} step={0.1} defaultValue={DEFAULT_PREFS.speedScale} label={(v) => `×${v.toFixed(1)}`} onCommit={(v) => act({ type: 'setPrefs', prefs: { speedScale: v } })} />
      </div>

      <Label icon="🪟">표시 위치</Label>
      <div className="chips three">
        {LAYERS.map((l) => (
          <Chip key={l.id} icon={l.id === 'aboveApps' ? '⬆️' : l.id === 'desktop' ? '🖥️' : '🔔'} on={s.layer === l.id} hint={l.title} onClick={() => act({ type: 'setLayer', layer: l.id })}>
            {l.short}
          </Chip>
        ))}
      </div>

      <Label icon="🚶">움직임</Label>
      <div className="chips two">
        <Chip
          icon="🧗"
          on={s.walkOnWindows}
          disabled={!s.walkOnWindowsAvailable}
          hint={!s.walkOnWindowsAvailable ? '이 환경에선 창 목록을 읽을 수 없어요' : s.layer === 'aboveApps' ? '창 위를 걷고, 창을 기어올라요' : "'항상 위' 표시일 때만 창 위로 다녀요"}
          onClick={() => act({ type: 'toggleWalkOnWindows' })}
        >
          창 위 산책
        </Chip>
        <Chip icon="🖱️" on={s.mischief} disabled={!s.walkOnWindowsAvailable} hint="마우스 포인터를 쫓아와 물고 흔들다 휙 던져요 (클릭하면 놓아줘요)" onClick={() => act({ type: 'toggleMischief' })}>
          장난꾸러기
        </Chip>
      </div>
      <div className="note">펫을 잡아서 휙 던져 보세요</div>

      {s.isDev && (
        <>
          <Label icon="🔨">개발용</Label>
          <div className="chips three">
            <Chip icon="😊" onClick={() => act({ type: 'debug', kind: 'happy' })}>
              신남
            </Chip>
            <Chip icon="🔥" onClick={() => act({ type: 'debug', kind: 'angry' })}>
              화남
            </Chip>
            <Chip icon="✋" onClick={() => act({ type: 'debug', kind: 'ask' })}>
              확인 요청
            </Chip>
          </div>
        </>
      )}
    </>
  )
}

/**
 * 설정 슬라이더 한 줄: 아이콘 · 이름 · 값 · 기본값으로 / 슬라이더 (맥 PrefSlider)
 * 끄는 동안은 화면 값만 바꾸고, 손을 뗐을 때 한 번 저장 (크기처럼 창을 다시 맞추는 값이 덜컹거리지 않게)
 */
function PrefSlider(props: { icon: string; title: string; value: number; range: [number, number]; step: number; defaultValue: number; label: (v: number) => string; onCommit: (v: number) => void }) {
  const [v, setV] = useState(props.value)
  const dragging = useRef(false)
  // 밖에서 값이 바뀌면(다른 곳에서 저장) 따라간다. 끄는 중에는 손 위치가 우선
  useEffect(() => {
    if (!dragging.current) setV(props.value)
  }, [props.value])
  const commit = (x: number) => {
    dragging.current = false
    if (x !== props.value) props.onCommit(x)
  }
  return (
    <div className="pref">
      <div className="pref-head">
        <span className="pref-icon">{props.icon}</span>
        <span className="pref-title">{props.title}</span>
        <span className="pref-value">{props.label(v)}</span>
        <button
          className="pref-reset"
          title="기본값으로"
          onClick={() => {
            setV(props.defaultValue)
            commit(props.defaultValue)
          }}
        >
          ↺
        </button>
      </div>
      <input
        type="range"
        min={props.range[0]}
        max={props.range[1]}
        step={props.step}
        value={v}
        style={{ '--pct': `${((v - props.range[0]) / (props.range[1] - props.range[0])) * 100}%` } as CSSProperties}
        onPointerDown={() => (dragging.current = true)}
        onChange={(e) => setV(Number(e.target.value))}
        onPointerUp={(e) => commit(Number(e.currentTarget.value))}
        onKeyUp={(e) => commit(Number(e.currentTarget.value))}
      />
    </div>
  )
}

function Stage({ s }: { s: PanelState }) {
  return (
    <div className="stage">
      {/* 장식: 작은 하트·별 (패널이 덜 딱딱해 보이게) */}
      <span className="stage-deco">
        <i>♥</i>✦
      </span>
      <div className="stage-pet">
        {s.stage && (
          <div className="stage-sprite">
            <Sprite
              packKey={s.stage.packKey}
              file={s.stage.file}
              frames={s.stage.frames}
              fps={s.stage.fps}
              pixelArt={s.stage.pixelArt}
              width={58}
              height={Math.round((58 * s.stage.frameHeight) / s.stage.frameWidth)}
            />
          </div>
        )}
      </div>
      <div className="grow">
        <div className="stage-name">
          {s.selectedName} <small>텀펫 v{s.version}</small>
        </div>
        <div className="stage-status">
          <span className={`dot ${s.server.ok ? 'ok' : 'bad'}`} />
          {s.server.text}
          {s.mood === 'cheerful' && <span title="최근 계속 성공했어요"> · ✨ 신남</span>}
          {s.mood === 'gloomy' && <span title="최근 에러가 많았어요"> · 🌧 시무룩</span>}
        </div>
        {s.statsLine && <div className="stage-stats">오늘 {s.statsLine}</div>}
      </div>
      <button className={`switch ${s.visible ? 'on' : ''}`} title={s.visible ? '펫 숨기기' : '펫 보이기'} onClick={() => act({ type: 'setVisible', visible: !s.visible })}>
        <span className="knob">{s.visible ? '👁' : '–'}</span>
      </button>
    </div>
  )
}

const STATE_ICON = { working: '…', waiting: '✋', done: '✔', error: '⚠' }
const STATE_TEXT = { working: '작업 중', waiting: '권한 대기', done: '끝남', error: '에러' }
/** 최근 알림 종류 → 아이콘·색 (맥 RecentRow: 에러 ⚠ / 권한 ✋ / 나머지 ✔) */
const RECENT_STATE: Partial<Record<EventKind, 'done' | 'error' | 'waiting'>> = { done: 'done', error: 'error', ask: 'waiting' }

function elapsed(ms: number) {
  const s = Math.max(0, ms / 1000)
  return s < 60 ? '방금' : formatDuration(Math.floor(s / 60) * 60)
}

/** 버전 글씨에 마우스를 올리면: 실패 이유, 또는 GitHub 이 알려 준 최신 버전과 확인 시각 */
function versionHint(s: PanelState) {
  if (s.update.state === 'failed') return `${s.update.message} · 눌러서 다시 확인`
  if (s.update.latest && s.update.checkedAt) {
    const t = new Date(s.update.checkedAt).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' })
    return `GitHub 최신 v${s.update.latest} · ${t} 확인 · 눌러서 다시 확인`
  }
  return '눌러서 새 버전 확인'
}

function versionLabel(s: PanelState) {
  switch (s.update.state) {
    case 'checking':
      return '확인 중…'
    case 'upToDate':
      return `v${s.version} · 최신`
    case 'failed':
      // 확인이 실패해도 지금 버전은 항상 보여 준다 (이유는 마우스를 올리면)
      return `v${s.version} · 확인 실패`
    default:
      return `v${s.version}`
  }
}

function Label({ icon, children }: { icon: string; children: ReactNode }) {
  return (
    <div className="label">
      <span className="label-icon">{icon}</span>
      {children}
    </div>
  )
}

function Card({ children }: { children: ReactNode }) {
  return <div className="card">{children}</div>
}

function Chip(props: { icon: string; on?: boolean; disabled?: boolean; hint?: string; onClick: () => void; children: ReactNode }) {
  return (
    <button className={`chip ${props.on ? 'on' : ''}`} disabled={props.disabled} title={props.hint} onClick={props.onClick}>
      <span className="chip-icon">{props.icon}</span>
      {props.children}
    </button>
  )
}

/** [연결 확인] 결과: 단계별 ✓ / ✗ / ℹ + 설명, 바로 고칠 수 있으면 버튼 */
function CheckView({ kind, check }: { kind: IntegrationKind; check: CheckResult }) {
  return (
    <div className={`diag ${check.running ? 'running' : check.ok ? 'ok' : 'bad'}`}>
      {check.running && <div className="diag-title">확인하는 중… (최대 15초)</div>}
      {!check.running && <div className="diag-title">{check.ok ? '이 PC에서 잘 동작해요' : '문제를 찾았어요'}</div>}
      {check.steps.map((st) => (
        <div key={st.label} className="diag-step">
          <span className={`mark ${st.ok === true ? 'ok' : st.ok === false ? 'bad' : 'info'}`}>{st.ok === true ? '✓' : st.ok === false ? '✗' : 'i'}</span>
          <span className="grow">
            <span className="diag-label">{st.label}</span>
            {st.detail && <span className="diag-detail">{st.detail}</span>}
          </span>
        </div>
      ))}
      {check.fix && !check.running && (
        <button className="connect on diag-fix" onClick={() => act({ type: 'fixIntegration', kind, action: check.fix!.action })}>
          {check.fix.label}
        </button>
      )}
    </div>
  )
}
