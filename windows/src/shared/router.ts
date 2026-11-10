// HTTP 요청 → (응답, 이벤트) 라우팅. 맥 앱 EventRouter.swift 이식. 네트워크와 무관한 순수 함수.
// Express 비유: app.get('/health'), app.post('/event') 핸들러 모음.
//   GET  /health            → 200 ok (토큰 불필요)
//   POST /event             → 표준 JSON 이벤트
//   POST /hook/claude       → Claude Code 훅 stdin 원본
//   POST /hook/claude-tool  → PostToolUse 원본 (앞부분만 읽음)
//   POST /hook/codex        → Codex notify 원본
import { timingSafeEqual } from 'node:crypto'
import { decodeClaudeHook, decodeClaudeTool, decodeCodexNotify, decodeStandard, DecodeError, type DecodeContext, type PetEvent } from './events'

export interface RouteRequest {
  method: string
  path: string
  /** 소문자 이름 */
  headers: Record<string, string | undefined>
  body: string
}
export interface RouteOutcome {
  status: number
  body: string
  event?: PetEvent
}

const EVENT_PATHS = ['/event', '/hook/claude', '/hook/claude-tool', '/hook/codex']
/** 이 경로는 본문이 커도 앞부분만 읽는다 (서버가 잘라서 넘김) */
export const HEAD_ONLY_PATHS = ['/hook/claude-tool']

export function route(req: RouteRequest, token: string): RouteOutcome {
  const path = req.path.split('?')[0]
  if (path === '/health') return req.method === 'GET' ? { status: 200, body: 'ok' } : { status: 405, body: 'method not allowed' }
  if (!EVENT_PATHS.includes(path)) return { status: 404, body: 'not found' }
  if (req.method !== 'POST') return { status: 405, body: 'method not allowed' }
  // 브라우저가 보낸 요청은 Origin 헤더가 붙는다 → 웹페이지의 localhost 공격 차단
  if (req.headers['origin'] !== undefined) return { status: 403, body: 'forbidden' }
  const given = req.headers['x-termpet-token']
  if (!given || !constantTimeEquals(given, token)) return { status: 401, body: 'unauthorized' }

  const h = (k: string) => {
    const v = req.headers[k]?.trim()
    return v ? v : undefined
  }
  const ctx: DecodeContext = {
    // 윈도우 훅: 에디터 exe 경로 / 맥 훅: 번들 ID
    host: h('x-termpet-host-exe') ?? h('x-termpet-host-bundle') ?? (h('x-termpet-wt') ? 'WindowsTerminal' : undefined),
    termProgram: h('x-termpet-term-program'),
    terminal: h('x-termpet-wt') ?? h('x-termpet-tty'),
  }
  try {
    let event: PetEvent
    switch (path) {
      case '/hook/claude':
        event = decodeClaudeHook(req.body, ctx)
        break
      case '/hook/claude-tool':
        event = decodeClaudeTool(req.body, ctx)
        break
      case '/hook/codex':
        event = decodeCodexNotify(req.body, ctx)
        break
      default:
        event = decodeStandard(req.body, ctx)
    }
    return { status: 202, body: 'accepted', event }
  } catch (e) {
    if (e instanceof DecodeError && e.ignored) return { status: 200, body: `ignored: ${e.message}` }
    return { status: 400, body: `bad request: ${(e as Error).message}` }
  }
}

/** 타이밍 공격 방지용 비교 */
export function constantTimeEquals(a: string, b: string): boolean {
  const x = Buffer.from(a)
  const y = Buffer.from(b)
  return x.length === y.length && timingSafeEqual(x, y)
}

/** 받은 요청 기록 한 줄 (~/.termpet/events.log) */
export function logLine(date: Date, method: string, path: string, status: number, body: string, event?: PetEvent): string {
  const p = (n: number) => String(n).padStart(2, '0')
  const stamp = `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())} ${p(date.getHours())}:${p(date.getMinutes())}:${p(date.getSeconds())}`
  const parts = [stamp, `${method} ${path}`, String(status)]
  if (event) {
    parts.push(`${event.source}/${event.kind}`)
    parts.push(event.cwd?.split(/[\\/]+/).filter(Boolean).pop() ?? '-')
    const host = event.host ?? event.termProgram
    if (host) parts.push(`host=${host}`)
  } else if (status !== 200 || path !== '/health') {
    parts.push(body)
  }
  return parts.join('  ')
}
