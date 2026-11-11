// 설정 병합 · 호스트 판별 · 기타 순수 로직 테스트 (맥 IntegrationTests / AppUpdaterTests 대응)
import { describe, expect, it } from 'vitest'
import { findProjectRoot, planFocus, resolveHost } from './hostApp'
import { claudeHookCommands, ClaudeDesktop, ClaudeHooks, CodexNotify, executionPolicyBlocksProfile, hooksBlockedBy, parseStringArray, PowerShellProfile, PROFILE_LINE, psQuote, rootNotify } from './integrations'
import { decodeClaudeHook, SELF_TEST_CWD, SELF_TEST_EVENT } from './events'
import { effectiveLayer, isNewer, isQuiet, micInUseFromRegQuery, parseRelease, placeBubble, safeFolderName } from './misc'

const cmds = claudeHookCommands('C:\\Users\\me\\.termpet\\bin\\termpet-claude.ps1')

describe('Claude 훅 병합', () => {
  it('명령은 PowerShell 로 스크립트 내용을 실행 (실행 정책 무관), 항목에 shell: powershell', () => {
    expect(cmds.command).toBe("& ([scriptblock]::Create([IO.File]::ReadAllText('C:\\Users\\me\\.termpet\\bin\\termpet-claude.ps1'))) claude")
    expect(cmds.toolCommand.endsWith(' claude-tool')).toBe(true)
    expect(ClaudeHooks.entry('Stop', cmds)).toMatchObject({ type: 'command', shell: 'powershell', async: true })
  })
  it("경로의 작은따옴표는 '' 로 (사용자 이름에 ' 가 있어도)", () => {
    expect(psQuote("C:\\Users\\O'Neil")).toBe("'C:\\Users\\O''Neil'")
  })
  it('예전 형식(.cmd 명령)은 업데이트 필요 → 설치하면 새 형식으로 바뀌고 다른 훅은 유지', () => {
    const oldCmds = { command: '"C:/Users/me/.termpet/bin/termpet-hook.cmd" claude', toolCommand: '"C:/Users/me/.termpet/bin/termpet-hook.cmd" claude-tool' }
    const oldEntry = (e: string) => ({ type: 'command', command: e === 'PostToolUse' ? oldCmds.toolCommand : oldCmds.command, timeout: 5 })
    const hooks: Record<string, unknown> = { Stop: [{ hooks: [{ type: 'command', command: 'echo hi' }, oldEntry('Stop')] }] }
    for (const e of ['Notification', 'UserPromptSubmit', 'PostToolUse', 'StopFailure', 'SessionEnd']) hooks[e] = [{ hooks: [oldEntry(e)] }]
    const before = JSON.stringify({ hooks })
    expect(ClaudeHooks.isInstalled(before)).toBe(true)
    expect(ClaudeHooks.needsUpdate(before, cmds)).toBe(true)
    const after = ClaudeHooks.install(before, cmds)
    expect(ClaudeHooks.needsUpdate(after, cmds)).toBe(false)
    expect(ClaudeHooks.install(after, cmds)).toBe(after)
    const obj = JSON.parse(after)
    expect(after).not.toContain('termpet-hook.cmd')
    expect(obj.hooks.Stop[0].hooks).toEqual([{ type: 'command', command: 'echo hi' }])
    expect(obj.hooks.Stop[1].hooks[0]).toEqual(ClaudeHooks.entry('Stop', cmds))
  })
  it('훅을 막는 설정 찾기', () => {
    expect(hooksBlockedBy('{}', undefined)).toBeUndefined()
    expect(hooksBlockedBy('{"disableAllHooks": true}', undefined)).toContain('disableAllHooks')
    expect(hooksBlockedBy('{}', '{"allowManagedHooksOnly": true}')).toContain('allowManagedHooksOnly')
    expect(hooksBlockedBy('{oops', '{oops')).toBeUndefined()
  })
  it('[연결 확인] 가짜 훅 이벤트는 완료 알림 + 한글 경로 그대로', () => {
    const e = decodeClaudeHook(JSON.stringify({ hook_event_name: SELF_TEST_EVENT, session_id: 'termpet-selftest-1', cwd: SELF_TEST_CWD }))
    expect(e.kind).toBe('done')
    expect(e.cwd).toBe(SELF_TEST_CWD)
    expect(e.message).toBeTruthy()
  })
  it('기존 설정·다른 훅은 그대로 두고 추가, 두 번 해도 한 번만', () => {
    const before = JSON.stringify({ model: 'opus', hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo hi' }] }] } })
    const once = ClaudeHooks.install(before, cmds)
    const twice = ClaudeHooks.install(once, cmds)
    expect(twice).toBe(once)
    const obj = JSON.parse(once)
    expect(obj.model).toBe('opus')
    expect(obj.hooks.Stop).toHaveLength(2)
    expect(obj.hooks.PostToolUse[0].hooks[0]).toMatchObject({ command: cmds.toolCommand, async: true, shell: 'powershell' })
    expect(ClaudeHooks.isInstalled(once)).toBe(true)
    expect(ClaudeHooks.missingEvents(once)).toEqual([])
  })
  it('해제하면 우리 것만 빠진다', () => {
    const before = JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo hi' }] }] } })
    const out = JSON.parse(ClaudeHooks.uninstall(ClaudeHooks.install(before, cmds)))
    expect(out).toEqual({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo hi' }] }] } })
  })
  it('깨진 JSON 은 에러 (덮어쓰지 않음), BOM 은 허용', () => {
    expect(() => ClaudeHooks.install('{oops', cmds)).toThrow()
    expect(() => ClaudeHooks.install('\uFEFF{}', cmds)).not.toThrow()
  })
})

describe('PowerShell 실행 정책', () => {
  it('Restricted · AllSigned · Undefined 면 프로필이 막힌다', () => {
    expect(executionPolicyBlocksProfile('Restricted\r\n')).toBe(true)
    expect(executionPolicyBlocksProfile('AllSigned')).toBe(true)
    expect(executionPolicyBlocksProfile('Undefined')).toBe(true)
    expect(executionPolicyBlocksProfile('RemoteSigned\r\n')).toBe(false)
    expect(executionPolicyBlocksProfile('Bypass')).toBe(false)
  })
})

describe('PowerShell 프로필', () => {
  it('한 줄 추가/제거, CRLF 유지', () => {
    const before = 'Set-Alias ll ls\r\n'
    const on = PowerShellProfile.install(before)
    expect(on).toContain(PROFILE_LINE)
    expect(on.startsWith('Set-Alias ll ls\r\n')).toBe(true)
    expect(PowerShellProfile.install(on)).toBe(on)
    expect(PowerShellProfile.isInstalled(on)).toBe(true)
    const off = PowerShellProfile.uninstall(on)
    expect(PowerShellProfile.isInstalled(off)).toBe(false)
    expect(off).toContain('Set-Alias ll ls')
  })
  it('주석 처리된 줄은 연결로 안 본다', () => {
    expect(PowerShellProfile.isInstalled('# ' + PROFILE_LINE)).toBe(false)
  })
})

/** 테스트용 notify 줄 (TOML 기본 문자열) */
const renderLine = (args: string[]) => `notify = [${args.map((a) => JSON.stringify(a)).join(', ')}]\n`

describe('Codex notify', () => {
  const ps1 = 'C:\\Users\\me\\.termpet\\bin\\termpet-hook.ps1'
  it('없으면 첫 테이블 앞에 추가, 해제하면 제거', () => {
    const before = 'model = "o3"\n[profiles.x]\nfoo = 1\n'
    const on = CodexNotify.install(before, ps1)
    const [line, args] = rootNotify(on)!
    expect(line).toBe(1)
    expect(args.slice(-2)).toEqual([ps1, 'codex'])
    expect(CodexNotify.isInstalled(on)).toBe(true)
    expect(CodexNotify.uninstall(on)).toBe(before)
  })
  it('기존 notify 는 연결(chain) 후 해제 시 복원', () => {
    const before = 'notify = ["notify-send.exe", "done"]\n'
    const on = CodexNotify.install(before, ps1)
    expect(rootNotify(on)![1].slice(-3)).toEqual(['codex-chain', 'notify-send.exe', 'done'])
    expect(CodexNotify.uninstall(on)).toBe(before)
  })
  it('다른 도구(Computer Use)가 --previous-notify 로 다시 감싸도 연결됨, 해제하면 그 도구 원래 줄로', () => {
    const sky = 'C:\\Sky\\SkyComputerUseClient.exe'
    const before = renderLine([sky, 'turn-ended'])
    const ours = CodexNotify.install(before, ps1)
    const inner = rootNotify(ours)![1]
    const wrapped = renderLine([sky, 'turn-ended', '--previous-notify', JSON.stringify(inner)])
    expect(CodexNotify.isInstalled(wrapped)).toBe(true)
    expect(CodexNotify.install(wrapped, ps1)).toBe(wrapped) // 또 감싸지 않는다 (알림 두 번 방지)
    expect(rootNotify(CodexNotify.uninstall(wrapped))![1]).toEqual([sky, 'turn-ended'])
    // 감싼 도구 앞에 원래 다른 notify 가 있었으면 그건 남긴다
    const other = renderLine([sky, 'turn-ended', '--previous-notify', JSON.stringify([...CodexNotify.hookPrefix(ps1), 'codex-chain', 'beep.exe'])])
    expect(rootNotify(CodexNotify.uninstall(other))![1]).toEqual([sky, 'turn-ended', '--previous-notify', '["beep.exe"]'])
  })
  it('TOML 문자열 배열 (리터럴 문자열·이스케이프)', () => {
    expect(parseStringArray(`['C:\\x', "a\\"b"] # c`)).toEqual(['C:\\x', 'a"b'])
    expect(parseStringArray('"x"')).toBeUndefined()
  })
  it('여러 줄 notify 는 에러', () => {
    expect(() => CodexNotify.install('notify = [\n "a"\n]\n', ps1)).toThrow()
  })
})

describe('호스트 판별', () => {
  it('exe 경로로 에디터 구분', () => {
    expect(resolveHost('C:\\Users\\me\\AppData\\Local\\Programs\\cursor\\Cursor.exe', 'vscode')).toEqual({
      kind: 'cursor',
      exePath: 'C:\\Users\\me\\AppData\\Local\\Programs\\cursor\\Cursor.exe',
    })
    expect(resolveHost(undefined, 'vscode')).toEqual({ kind: 'vscode' })
    expect(resolveHost('WindowsTerminal', undefined)).toEqual({ kind: 'windowsTerminal' })
    expect(resolveHost(undefined, undefined)).toBeUndefined()
  })
  it('에디터는 프로젝트 루트 폴더 열기, 터미널은 앞으로', () => {
    const root = (cwd: string) => findProjectRoot(cwd, 'C:\\Users\\me', (p) => p === 'C:\\Users\\me\\proj\\.git')
    expect(planFocus({ termProgram: 'vscode', cwd: 'C:\\Users\\me\\proj\\src\\a' }, root)).toMatchObject({ type: 'openFolder', path: 'C:\\Users\\me\\proj' })
    expect(planFocus({ host: 'WindowsTerminal', cwd: 'C:\\x' }, root)).toMatchObject({ type: 'activate' })
    expect(planFocus({}, root)).toEqual({ type: 'none' })
  })
  it('.git 이 없으면 cwd 그대로 (홈에서 멈춤)', () => {
    expect(findProjectRoot('C:\\Users\\me\\a\\b', 'C:\\Users\\me', () => false)).toBe('C:\\Users\\me\\a\\b')
  })
})

describe('기타', () => {
  it('조용한 시간', () => {
    expect(isQuiet(0, 10, false, false)).toBe(true)
    expect(isQuiet(20, 10, true, true)).toBe(true)
    expect(isQuiet(20, 10, true, false)).toBe(false)
  })
  it('마이크 사용 중 (레지스트리 결과)', () => {
    const inUse = 'HKEY_CURRENT_USER\\...\\zoom.exe\r\n    LastUsedTimeStop    REG_QWORD    0x0\r\n'
    const idle = '    LastUsedTimeStop    REG_QWORD    0x1db2c3a4b5c6d7e\r\n'
    expect(micInUseFromRegQuery(inUse)).toBe(true)
    expect(micInUseFromRegQuery(idle)).toBe(false)
  })
  it('알림 때만 위', () => {
    expect(effectiveLayer('desktopPopUp', true)).toBe('aboveApps')
    expect(effectiveLayer('desktop', true)).toBe('desktop')
  })
  it('말풍선은 펫 위, 공간이 없으면 아래', () => {
    const screen = { x: 0, y: 0, width: 1000, height: 800 }
    expect(placeBubble({ width: 200, height: 80 }, { x: 400, y: 700, width: 80, height: 80 }, screen)).toMatchObject({ x: 340, y: 634, below: false })
    expect(placeBubble({ width: 200, height: 80 }, { x: 0, y: 0, width: 80, height: 80 }, screen)).toMatchObject({ x: 4, below: true })
  })
  it('버전 비교·릴리스 해석', () => {
    expect(isNewer('v0.10.0', '0.9.9')).toBe(true)
    expect(isNewer('0.4.0', '0.4.0')).toBe(false)
    expect(isNewer('v1.0', 'dev')).toBe(false)
    expect(parseRelease({ tag_name: 'v0.5.0', assets: [{ name: 'TermPet-0.5.0.zip' }, { name: 'TermPet-Setup-0.5.0.exe', browser_download_url: 'https://x/y.exe' }] })).toEqual({
      tag: 'v0.5.0',
      installerUrl: 'https://x/y.exe',
    })
  })
  it('친구 폴더 이름', () => {
    expect(safeFolderName('../a\\b:c')).toBe('_a_b_c')
    expect(safeFolderName('..')).toBe('friend')
  })
})

describe('ClaudeDesktop (claude_desktop_config.json)', () => {
  const l = { command: 'C:\\Users\\me\\AppData\\Local\\Programs\\TermPet\\TermPet.exe', script: 'C:\\Users\\me\\.termpet\\bin\\termpet-mcp.js' }

  it('다른 설정·MCP 서버는 그대로 두고 termpet 만 넣고 뺀다', () => {
    const original = JSON.stringify({ preferences: { a: 1 }, mcpServers: { other: { command: 'x' } } })
    const out = ClaudeDesktop.install(original, l)
    const root = JSON.parse(out)
    expect(root.preferences).toEqual({ a: 1 })
    expect(root.mcpServers.other).toEqual({ command: 'x' })
    expect(root.mcpServers.termpet).toEqual({ command: l.command, args: [l.script], env: { ELECTRON_RUN_AS_NODE: '1' } })
    expect(ClaudeDesktop.isInstalled(out)).toBe(true)
    expect(ClaudeDesktop.needsUpdate(out, l)).toBe(false)
    expect(ClaudeDesktop.needsUpdate(out, { ...l, command: 'D:\\TermPet.exe' })).toBe(true)
    const removed = JSON.parse(ClaudeDesktop.uninstall(out))
    expect(removed.mcpServers).toEqual({ other: { command: 'x' } })
    expect(removed.preferences).toEqual({ a: 1 })
  })

  it('파일이 없으면 새로, 깨진 JSON 은 손대지 않고 에러', () => {
    expect(ClaudeDesktop.isInstalled(ClaudeDesktop.install(undefined, l))).toBe(true)
    expect(() => ClaudeDesktop.install('{oops', l)).toThrow()
    expect(ClaudeDesktop.isInstalled('{oops')).toBe(false)
  })
})
