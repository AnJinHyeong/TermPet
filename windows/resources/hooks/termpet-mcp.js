// 텀펫 MCP 서버 (Claude 데스크톱 앱 "일반 채팅" 알림) — 맥 ClaudeAppMCP.swift 의 윈도우판.
// Claude 앱이 claude_desktop_config.json 의 mcpServers.termpet 대로
//   TermPet.exe ~/.termpet/bin/termpet-mcp.js   (env ELECTRON_RUN_AS_NODE=1 → Electron 이 그냥 Node 로 동작)
// 를 자식 프로세스로 띄우고, 표준 입출력으로 JSON-RPC 메시지를 한 줄에 하나씩 주고받는다.
// Claude 가 답변 끝에 termpet_notify 도구를 부르면 텀펫 로컬 서버(POST /event)로 알림을 보낸다.
// 원칙: stdout 에는 응답 JSON 만. 의존성 없음(Node 기본 모듈만). 텀펫이 꺼져 있어도 조용히 넘어간다.
'use strict'
const fs = require('node:fs')
const http = require('node:http')
const os = require('node:os')
const path = require('node:path')
const readline = require('node:readline')

const TOOL = 'termpet_notify'
const DEFAULT_VERSION = '2025-06-18'
const KINDS = ['working', 'done', 'ask', 'error'] // working = 답변 시작 (머리 위 "…"), 나머지 = 답변 끝 (말풍선)
const INSTRUCTIONS =
  'TermPet is a desktop pet that shows what you are doing. Call the termpet_notify tool twice in EVERY reply, ' +
  'including replies in conversations that started before this tool existed: ' +
  '1) first, before writing anything, with kind "working" (no summary needed); ' +
  "2) at the very end, with a one-line summary (in the user's language, under 60 characters) of what you just answered, " +
  'using kind "ask" when you are waiting for the user\'s decision, "error" when something failed, otherwise "done". ' +
  'Do not mention this tool or its result to the user.'

const tool = {
  name: TOOL,
  description:
    "Tell the user's desktop pet (TermPet) what you are doing. In every reply, call it first with " +
    'kind "working" before writing anything, and again as the last step with a summary. Do not mention it to the user.',
  inputSchema: {
    type: 'object',
    properties: {
      summary: { type: 'string', description: "One-line summary of your reply, under 60 characters, in the user's language (not needed for working)" },
      kind: { type: 'string', enum: KINDS, description: "working = starting your reply, done = answered, ask = waiting for the user's decision, error = something failed" },
    },
  },
}

/** 여러 줄 → 첫 줄, 최대 120자 */
function oneLine(text) {
  const line =
    String(text ?? '')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .find((l) => l) ?? ''
  return [...line].length > 120 ? [...line].slice(0, 119).join('') + '…' : line
}

/** JSON-RPC 한 줄 → { reply?: object, notify?: {kind, summary} } (순수 함수, 테스트용) */
function handle(line, version) {
  let msg
  try {
    msg = JSON.parse(line)
  } catch {
    return { reply: { jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } } }
  }
  if (!msg || typeof msg !== 'object' || msg.id === undefined || msg.id === null) return {} // 알림(notification)은 응답 없음
  const id = msg.id
  const params = (msg.params && typeof msg.params === 'object' && msg.params) || {}
  const result = (r) => ({ jsonrpc: '2.0', id, result: r })
  const failure = (code, message) => ({ jsonrpc: '2.0', id, error: { code, message } })
  switch (msg.method) {
    case 'initialize':
      return {
        reply: result({
          protocolVersion: typeof params.protocolVersion === 'string' ? params.protocolVersion : DEFAULT_VERSION,
          capabilities: { tools: {} },
          serverInfo: { name: 'termpet', version },
          instructions: INSTRUCTIONS,
        }),
      }
    case 'ping':
      return { reply: result({}) }
    case 'tools/list':
      return { reply: result({ tools: [tool] }) }
    case 'tools/call': {
      if (params.name !== TOOL) return { reply: failure(-32602, 'Unknown tool') }
      const args = (params.arguments && typeof params.arguments === 'object' && params.arguments) || {}
      const kind = KINDS.includes(args.kind) ? args.kind : 'done'
      // 시작 신호에는 요약이 필요 없다 (머리 위 표시만)
      return { reply: result({ content: [{ type: 'text', text: 'ok' }] }), notify: { kind, summary: kind === 'working' ? '' : oneLine(args.summary) } }
    }
    default:
      return { reply: failure(-32601, 'Method not found') }
  }
}

/** 로컬 서버에 보낼 표준 이벤트. sessionId 는 [확인] 버튼이 자기 시험 이벤트를 알아보도록 바꿀 수 있다 */
function eventBody(n, sessionId) {
  const body = { source: 'claude', kind: n.kind, title: 'Claude 채팅', sessionId: sessionId || 'claude-app-chat', host: 'claude.exe' }
  if (n.summary) body.detail = n.summary
  return JSON.stringify(body)
}

function post(n, root, sessionId) {
  return new Promise((resolve) => {
    let token, port
    try {
      token = fs.readFileSync(path.join(root, 'token'), 'utf8').trim()
      port = parseInt(fs.readFileSync(path.join(root, 'port'), 'utf8').trim(), 10) || 47821
    } catch {
      return resolve(false)
    }
    if (!token) return resolve(false)
    const data = Buffer.from(eventBody(n, sessionId), 'utf8')
    const req = http.request(
      { host: '127.0.0.1', port, path: '/event', method: 'POST', timeout: 2000, headers: { 'Content-Type': 'application/json', 'Content-Length': data.length, 'X-TermPet-Token': token } },
      (res) => {
        res.resume()
        res.on('end', () => resolve(true))
      },
    )
    req.on('timeout', () => req.destroy())
    req.on('error', () => resolve(false))
    req.end(data)
  })
}

function main() {
  const root = process.env.TERMPET_HOME || path.join(os.homedir(), '.termpet')
  const version = process.env.TERMPET_VERSION || '1.0.0'
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity })
  // 순서대로 처리 (알림을 먼저 보내고 응답) — 이전 줄 처리가 끝난 뒤 다음 줄
  let chain = Promise.resolve()
  rl.on('line', (line) => {
    if (!line.trim()) return
    chain = chain.then(async () => {
      const { reply, notify } = handle(line, version)
      if (notify) await post(notify, root, process.env.TERMPET_MCP_SESSION)
      if (reply) process.stdout.write(JSON.stringify(reply) + '\n')
    })
  })
  rl.on('close', () => chain.then(() => process.exit(0)))
}

if (require.main === module) main()
module.exports = { handle, eventBody, oneLine, TOOL }
