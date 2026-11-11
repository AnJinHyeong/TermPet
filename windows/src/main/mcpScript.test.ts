// Claude 앱 일반 채팅용 MCP 스크립트(resources/hooks/termpet-mcp.js) 테스트.
// 순수 함수(handle) + 실제로 Node 프로세스로 띄워 가짜 텀펫 서버에 알림이 도착하는지까지.
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import type { AddressInfo } from 'node:net'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { decodeStandard, projectName } from '../shared/events'
import { planFocus } from '../shared/hostApp'

const script = resolve(__dirname, '../../resources/hooks/termpet-mcp.js')
// eslint-disable-next-line @typescript-eslint/no-require-imports
const mcp = require(script) as {
  handle: (line: string, version: string) => { reply?: Record<string, any>; notify?: { kind: string; summary: string } }
  eventBody: (n: { kind: string; summary: string }, sessionId?: string) => string
}

const dirs: string[] = []
afterEach(() => dirs.splice(0).forEach((d) => rmSync(d, { recursive: true, force: true })))

describe('termpet-mcp.js', () => {
  it('initialize 는 클라이언트 버전을 그대로, tools/list 에 termpet_notify', () => {
    const init = mcp.handle(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25' } }), '1')
    expect(init.reply?.result.protocolVersion).toBe('2025-11-25')
    expect(init.reply?.result.capabilities.tools).toEqual({})
    const list = mcp.handle(JSON.stringify({ jsonrpc: '2.0', id: 'x', method: 'tools/list' }), '1')
    expect(list.reply?.id).toBe('x')
    expect(list.reply?.result.tools[0].name).toBe('termpet_notify')
  })

  it('알림(notification)엔 응답 없음, 모르는 메서드·도구·깨진 JSON 은 에러', () => {
    expect(mcp.handle('{"jsonrpc":"2.0","method":"notifications/initialized"}', '1')).toEqual({})
    expect(mcp.handle('{"jsonrpc":"2.0","id":2,"method":"server/discover"}', '1').reply?.error.code).toBe(-32601)
    expect(mcp.handle('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"nope"}}', '1').reply?.error.code).toBe(-32602)
    expect(mcp.handle('oops', '1').reply?.error.code).toBe(-32700)
    expect(mcp.handle('{"jsonrpc":"2.0","id":4,"method":"ping"}', '1').reply?.result).toEqual({})
  })

  it('tools/call → ok 응답 + 알림 (첫 줄만, 모르는 kind 는 done)', () => {
    const r = mcp.handle(JSON.stringify({ jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'termpet_notify', arguments: { summary: '요약\n둘째', kind: 'zzz' } } }), '1')
    expect(r.reply?.result.content[0]).toEqual({ type: 'text', text: 'ok' })
    expect(r.notify).toEqual({ kind: 'done', summary: '요약' })
  })

  it('답변 시작 신호(working) → 요약 없이 작업 중 이벤트', () => {
    const r = mcp.handle(JSON.stringify({ jsonrpc: '2.0', id: 6, method: 'tools/call', params: { name: 'termpet_notify', arguments: { kind: 'working', summary: '생각 중' } } }), '1')
    expect(r.notify).toEqual({ kind: 'working', summary: '' })
    const e = decodeStandard(mcp.eventBody(r.notify!))
    expect(e.kind).toBe('working')
    expect(e.detail).toBeUndefined()
  })

  it('보내는 이벤트 → "Claude 채팅" 제목, 누르면 Claude 앱 창으로', () => {
    const e = decodeStandard(mcp.eventBody({ kind: 'ask', summary: '골라 줘' }))
    expect(e.kind).toBe('ask')
    expect(e.detail).toBe('골라 줘')
    expect(projectName(e)).toBe('Claude 채팅')
    expect(planFocus(e, (c) => c)).toEqual({ type: 'activate', host: { kind: 'claudeApp' } })
  })

  it('실제 실행: stdin 으로 도구 호출 → 텀펫 서버에 한글 그대로 도착, stdout 엔 응답 JSON 만', async () => {
    let received = ''
    let token = ''
    const server = createServer((req, res) => {
      token = String(req.headers['x-termpet-token'])
      let body = ''
      req.setEncoding('utf8')
      req.on('data', (c) => (body += c))
      req.on('end', () => {
        received = body
        res.end('accepted')
      })
    })
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', r))
    const root = mkdtempSync(join(tmpdir(), 'termpet-mcp-'))
    dirs.push(root)
    writeFileSync(join(root, 'token'), 'secret')
    writeFileSync(join(root, 'port'), String((server.address() as AddressInfo).port))

    const child = spawn(process.execPath, [script], { env: { ...process.env, TERMPET_HOME: root } })
    let out = ''
    child.stdout.setEncoding('utf8')
    child.stdout.on('data', (c) => (out += c))
    child.stdin.end(
      [
        { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } },
        { jsonrpc: '2.0', method: 'notifications/initialized' },
        { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'termpet_notify', arguments: { summary: '한글 요약 ✓' } } },
      ]
        .map((m) => JSON.stringify(m))
        .join('\n') + '\n',
    )
    const code = await new Promise((r) => child.on('close', r))
    server.close()
    expect(code).toBe(0)
    const lines = out.trim().split('\n').map((l) => JSON.parse(l))
    expect(lines.map((l) => l.id)).toEqual([1, 2])
    expect(token).toBe('secret')
    expect(JSON.parse(received)).toMatchObject({ source: 'claude', kind: 'done', detail: '한글 요약 ✓', title: 'Claude 채팅' })
  })
})
