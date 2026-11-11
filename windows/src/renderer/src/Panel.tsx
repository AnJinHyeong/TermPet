// 트레이 아이콘을 누르면 뜨는 패널 (맥 MenuPanelView.swift 와 같은 구성).
// 무대(지금 캐릭터) → 업데이트 → 진행 중 → 친구 고르기 → 놀기 → AI 연결 → 알림 → 표시 위치 → 하단
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import type { CheckResult, IntegrationKind, PanelAction, PanelState } from '../../shared/ipc'
import { LAYERS } from '../../shared/misc'
import { formatDuration } from '../../shared/notifications'
import { packUrl, Sprite } from './Sprite'

const act = (a: PanelAction) => window.termpet.panelAction(a)

export function Panel() {
  const [s, setS] = useState<PanelState | null>(null)
  const [now, setNow] = useState(Date.now())
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

        <Label icon="♥">친구 고르기</Label>
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

        <Label icon="🥕">놀기</Label>
        <div className="chips two">
          <Chip icon={s.sleeping ? '☀️' : '🌙'} on={s.sleeping} hint={s.sleeping ? '깨워서 다시 놀게 해요' : '쿨쿨 재워요'} onClick={() => act({ type: 'toggleSleep' })}>
            {s.sleeping ? '깨우기' : '재우기'}
          </Chip>
          <Chip
            icon="🧗"
            on={s.walkOnWindows}
            disabled={!s.walkOnWindowsAvailable}
            hint={!s.walkOnWindowsAvailable ? '이 환경에선 창 목록을 읽을 수 없어요' : s.layer === 'aboveApps' ? '창 위를 걷고, 창을 기어올라요' : "'항상 위' 표시일 때만 창 위로 다녀요"}
            onClick={() => act({ type: 'toggleWalkOnWindows' })}
          >
            창 위 산책
          </Chip>
          <Chip icon="☁️" hint="하늘에서 뚝! 창 위에 떨어지면 거기서 놀아요" onClick={() => act({ type: 'dropFromTop' })}>
            떨어뜨리기
          </Chip>
          <Chip icon="💬" hint="말풍선을 한 번 띄워 봐요" onClick={() => act({ type: 'testNotification' })}>
            알림 테스트
          </Chip>
        </div>
        <div className="note">펫을 잡아서 휙 던져 보세요</div>

        <Label icon="🔗">AI 연결</Label>
        <Card>
          {s.integrations.map((i) => (
            <div key={i.kind}>
              <div className={`integration ${i.available ? '' : 'disabled'}`}>
                <span className={`int-icon ${i.kind}`} title={`${i.subtitle} 알림`}>
                  {i.kind === 'claude' ? '✳' : i.kind === 'codex' ? '</>' : '>_'}
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

        <Label icon="🔔">알림</Label>
        <div className="chips three">
          <Chip icon="🌙" on={s.quiet.manualOn} hint="1시간 동안 알림을 모아뒀다 보여줘요" onClick={() => act({ type: 'quietManual' })}>
            1시간 조용히
          </Chip>
          <Chip icon="🎥" on={s.quiet.duringMeetings} hint="마이크 사용 중(회의)엔 알림을 모아둬요" onClick={() => act({ type: 'quietMeetings' })}>
            회의 중
          </Chip>
          <Chip icon={s.quiet.soundOnAsk ? '🔔' : '🔕'} on={s.quiet.soundOnAsk} hint="Claude가 권한을 물으면 소리로 알려줘요" onClick={() => act({ type: 'soundOnAsk' })}>
            권한 소리
          </Chip>
        </div>
        {s.quiet.isQuiet && <div className="note">{s.quiet.manualOn ? '조용한 시간' : '회의 중이라 조용히'} · 알림은 펫 머리 위 !에 모여요</div>}

        <Label icon="🪟">표시 위치</Label>
        <div className="chips three">
          {LAYERS.map((l) => (
            <Chip key={l.id} icon={l.id === 'aboveApps' ? '⬆️' : l.id === 'desktop' ? '🖥️' : '🔔'} on={s.layer === l.id} hint={l.title} onClick={() => act({ type: 'setLayer', layer: l.id })}>
              {l.short}
            </Chip>
          ))}
        </div>

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

        <div className="footer">
          <label className="check">
            <input type="checkbox" checked={s.launchAtLogin} onChange={(e) => act({ type: 'setLaunchAtLogin', on: e.target.checked })} />
            로그인 시 실행
          </label>
          <span className="grow" />
          <button className="version" title="눌러서 새 버전 확인" onClick={() => act({ type: 'checkUpdate' })}>
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

function Stage({ s }: { s: PanelState }) {
  return (
    <div className="stage">
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

function elapsed(ms: number) {
  const s = Math.max(0, ms / 1000)
  return s < 60 ? '방금' : formatDuration(Math.floor(s / 60) * 60)
}

function versionLabel(s: PanelState) {
  switch (s.update.state) {
    case 'checking':
      return '확인 중…'
    case 'upToDate':
      return `v${s.version} · 최신`
    case 'failed':
      return s.update.message ?? '확인 실패'
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
