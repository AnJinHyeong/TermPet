// 127.0.0.1 전용 초소형 HTTP 서버 (맥 LocalHTTPServer.swift 대응). 라우팅은 shared/router.ts (순수 함수).
import { createServer, type Server } from 'node:http'
import type { PetEvent } from '../shared/events'
import { HEAD_ONLY_PATHS, logLine, route } from '../shared/router'
import { appendEventsLog } from './paths'

/** retryable = 다른 포트로 다시 시도하면 될 수 있는 실패 (사용 중 / 윈도우 예약 대역) */
export type ServerState = { type: 'stopped' } | { type: 'listening'; port: number } | { type: 'failed'; message: string; retryable?: boolean }

const MAX_BODY = 1_000_000
const HEAD_BYTES = 8192

export function startServer(port: number, token: string, onEvent: (e: PetEvent) => void, onState: (s: ServerState) => void): Server {
  const server = createServer((req, res) => {
    const path = (req.url ?? '/').split('?')[0]
    const headOnly = HEAD_ONLY_PATHS.includes(path)
    const chunks: Buffer[] = []
    let size = 0
    let tooLarge = false
    // 느린 클라이언트가 연결을 붙잡지 않게 5초 제한
    req.setTimeout(5000, () => req.destroy())
    req.on('data', (c: Buffer) => {
      size += c.length
      if (headOnly) {
        if (size - c.length < HEAD_BYTES) chunks.push(c) // 앞부분만 모으고 나머지는 버린다
      } else if (size > MAX_BODY) {
        tooLarge = true
      } else {
        chunks.push(c)
      }
    })
    req.on('end', () => {
      const send = (status: number, body: string) => {
        res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', Connection: 'close' })
        res.end(body)
      }
      if (tooLarge) return send(413, 'too large')
      const headers: Record<string, string | undefined> = {}
      for (const [k, v] of Object.entries(req.headers)) headers[k.toLowerCase()] = Array.isArray(v) ? v[0] : v
      const out = route({ method: req.method ?? 'GET', path, headers, body: Buffer.concat(chunks).toString('utf8') }, token)
      send(out.status, out.body)
      if (out.event) onEvent(out.event)
      if (path !== '/health') appendEventsLog(logLine(new Date(), req.method ?? '', path, out.status, out.body, out.event))
    })
  })
  server.on('listening', () => onState({ type: 'listening', port }))
  server.on('error', (e: NodeJS.ErrnoException) =>
    onState({
      type: 'failed',
      message: e.code === 'EADDRINUSE' ? `포트 ${port} 사용 중` : e.code === 'EACCES' ? `포트 ${port} 를 열 수 없음 (윈도우 예약 대역)` : e.message,
      retryable: e.code === 'EADDRINUSE' || e.code === 'EACCES',
    }),
  )
  server.on('close', () => onState({ type: 'stopped' }))
  // 루프백에만 바인딩 → 같은 네트워크의 다른 기기에서 접근 불가
  server.listen(port, '127.0.0.1')
  return server
}
