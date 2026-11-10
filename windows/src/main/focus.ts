// 말풍선 클릭 → 그 작업을 하던 에디터/터미널로 이동 (맥 ProjectFocuser.swift 의 윈도우판)
//  - VS Code / Cursor / Windsurf: 에디터 exe 에 프로젝트 폴더를 넘기면 이미 열린 창이면 그 창이 앞으로 온다
//  - Windows Terminal / WezTerm: 그 앱 창을 앞으로
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import type { PetEvent } from '../shared/events'
import { editorCandidates, findProjectRoot, planFocus, processNamesFor } from '../shared/hostApp'
import { focusProcessWindow } from './win32'

export function focusEvent(e: PetEvent) {
  const action = planFocus(e, (cwd) => findProjectRoot(cwd, homedir(), existsSync))
  if (action.type === 'none') return
  if (process.platform !== 'win32') {
    console.log('[TermPet] (윈도우 전용) 이동:', action)
    return
  }
  if (action.type === 'activate') {
    focusProcessWindow(processNamesFor(action.host.kind))
    return
  }
  const candidates = [action.host.exePath, ...editorCandidates(action.host.kind, process.env)].filter((p): p is string => !!p)
  const exe = candidates.find((p) => existsSync(p))
  if (!exe) {
    // 설치 위치를 모르면 창만이라도 앞으로
    focusProcessWindow(processNamesFor(action.host.kind))
    return
  }
  // 에디터도 Electron 앱이라, 우리 환경변수 중 ELECTRON_RUN_AS_NODE 가 넘어가면 node로 실행돼 버린다
  const env = { ...process.env }
  delete env.ELECTRON_RUN_AS_NODE
  try {
    const child = spawn(exe, [action.path], { detached: true, stdio: 'ignore', env, windowsHide: false })
    child.on('error', (err) => console.warn('[TermPet] 에디터 열기 실패', err))
    child.unref()
    // 단일 인스턴스 에디터가 창을 앞으로 못 가져오는 경우(포커스 제한) 대비: 잠시 뒤 그 앱 창을 앞으로
    setTimeout(() => focusProcessWindow(processNamesFor(action.host.kind)), 600)
  } catch (err) {
    console.warn('[TermPet] 에디터 열기 실패', err)
  }
}
