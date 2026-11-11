// "GPT 앱 채팅": ChatGPT 앱 로그 파일을 1.5초마다 훑어 새로 붙은 줄만 읽는다 (tail -F 비슷하게). 맥 ChatGPTAppWatcher 대응.
// 처음 켤 때 이미 있던 내용은 건너뛰고, 그 뒤에 생긴 파일은 처음부터 읽는다.
import { closeSync, existsSync, openSync, readdirSync, readSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { ChatGPTReducer, dayFolder, parseChatGPTLogLine } from '../shared/chatgptLog'
import type { PetEvent } from '../shared/events'

/**
 * 로그 루트 후보 (있는 것만).
 * - %LOCALAPPDATA%\Codex\Logs: 앱 코드가 쓰는 위치
 * - %LOCALAPPDATA%\Packages\<OpenAI 패키지>\LocalCache\Local\Codex\Logs: 스토어(MSIX) 설치판은 LOCALAPPDATA 쓰기가 여기로 바뀌어 들어간다
 * - 맥(개발 실행): ~/Library/Logs/com.openai.codex
 */
export function chatgptLogRoots(): string[] {
  const home = homedir()
  if (process.platform === 'darwin') return [join(home, 'Library', 'Logs', 'com.openai.codex')].filter(existsSync)
  const local = process.env.LOCALAPPDATA ?? join(home, 'AppData', 'Local')
  const roots = [join(local, 'Codex', 'Logs')]
  try {
    for (const d of readdirSync(join(local, 'Packages'))) {
      if (/openai|chatgpt|codex/i.test(d)) roots.push(join(local, 'Packages', d, 'LocalCache', 'Local', 'Codex', 'Logs'))
    }
  } catch {
    /* Packages 폴더 없음 */
  }
  return roots.filter(existsSync)
}

export class ChatGPTWatcher {
  private timer: ReturnType<typeof setInterval> | undefined
  private offsets = new Map<string, number>()
  private partial = new Map<string, string>()
  private reducer = new ChatGPTReducer()

  constructor(
    private onEvent: (e: PetEvent) => void,
    private roots: () => string[] = chatgptLogRoots,
  ) {}

  get running() {
    return this.timer !== undefined
  }

  start() {
    if (this.timer) return
    this.offsets.clear()
    this.partial.clear()
    for (const f of this.files()) this.offsets.set(f, sizeOf(f)) // 지난 내용은 건너뜀
    this.timer = setInterval(() => this.poll(), 1500)
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = undefined
  }

  /** 오늘·어제(UTC) 폴더의 .log (자정을 넘겨도 앱이 어제 폴더 파일에 계속 쓰므로) */
  files(now = new Date()): string[] {
    const days = [new Date(now.getTime() - 86_400_000), now]
    const out: string[] = []
    for (const root of this.roots()) {
      for (const day of days) {
        const dir = dayFolder(root, day, process.platform === 'win32' ? '\\' : '/')
        try {
          for (const n of readdirSync(dir)) if (n.endsWith('.log')) out.push(join(dir, n))
        } catch {
          /* 폴더 없음 */
        }
      }
    }
    return out
  }

  poll() {
    for (const f of this.files()) {
      const end = sizeOf(f)
      let start = this.offsets.get(f) ?? 0
      if (end < start) {
        start = 0 // 파일이 새로 써졌으면 처음부터
        this.partial.delete(f)
      }
      if (end <= start) continue
      const length = Math.min(end - start, 1 << 20) // 한꺼번에 쏟아질 때 너무 많이 읽지 않게
      let buf: Buffer
      try {
        const fd = openSync(f, 'r')
        try {
          buf = Buffer.alloc(length)
          readSync(fd, buf, 0, length, start)
        } finally {
          closeSync(fd)
        }
      } catch {
        continue
      }
      this.offsets.set(f, start + length)
      let text = (this.partial.get(f) ?? '') + buf.toString('utf8')
      const lastBreak = text.lastIndexOf('\n')
      if (lastBreak < 0) {
        this.partial.set(f, text)
        continue
      }
      this.partial.set(f, text.slice(lastBreak + 1))
      text = text.slice(0, lastBreak)
      for (const line of text.split(/\r?\n/)) {
        const signal = parseChatGPTLogLine(line)
        const event = signal && this.reducer.event(signal)
        if (event) this.onEvent(event)
      }
    }
  }
}

function sizeOf(f: string): number {
  try {
    return statSync(f).size
  } catch {
    return 0
  }
}
