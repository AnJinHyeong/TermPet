# TermPet — macOS 데스크톱 펫 + AI CLI 완료 알림 앱 (Claude Code 개발 지시서)

너는 이 프로젝트의 시니어 macOS 엔지니어다. 나는 React+TypeScript 프론트엔드 개발자이고 Swift는 처음이다.
아래 명세를 기준으로 **Phase 단위로** 개발을 진행해라. 이 파일을 프로젝트 루트에 `SPEC.md`로 저장하고, 작업 규칙은 `CLAUDE.md`에 요약해 둬라.

---

## 0. 작업 규칙 (반드시 지킬 것)

1. **Phase 하나씩 진행**한다. 한 Phase가 끝나면 빌드 성공을 확인하고, 내가 직접 실행해서 확인할 체크리스트를 보여준 뒤 **멈추고 내 확인을 기다린다.** UI 동작은 CLI로 검증할 수 없으므로 내 피드백이 필수다.
2. Xcode 프로젝트 파일(.xcodeproj)을 직접 편집하지 않는다. **XcodeGen(`project.yml`)으로 프로젝트를 생성**한다. 파일을 추가/삭제하면 `xcodegen generate`를 다시 실행한다.
3. 매 Phase 끝에 `xcodebuild -project TermPet.xcodeproj -scheme TermPet -configuration Debug build` 로 빌드가 통과해야 한다. 경고도 가능한 한 없앤다.
4. 로직(상태 머신, 이벤트 파싱, 트랜스크립트 파싱, 설정 병합)은 UI와 분리하고 XCTest 단위 테스트를 작성한다.
5. 나는 Swift 초보다. 새로운 Swift/AppKit 개념이 나오면 **React/TS에 빗대어 1~2줄로 설명**하는 주석이나 요약을 남겨라. (예: `@State` ≈ `useState`, `@Observable` 클래스 ≈ Zustand 스토어)
6. Phase가 끝날 때마다 git commit 한다. (메시지: `phase-N: 요약`)
7. 외부 도구(Claude Code 훅, Codex 알림 설정)의 입력 형식은 **현재 공식 문서를 확인하고** 구현한다. 확인이 안 되면 방어적으로 파싱하고(필드 누락 허용) TODO로 남긴다.
8. 사용자의 기존 설정 파일(`~/.claude/settings.json`, `~/.zshrc`, `~/.codex/config.toml`)을 수정할 때는 **반드시 백업 후 병합**하고, 덮어쓰지 않는다. 자동 수정은 사용자가 설정 화면에서 버튼을 눌렀을 때만 한다.

---

## 1. 제품 개요

- 이름(가칭): **TermPet**
- 플랫폼: macOS 14 (Sonoma) 이상, Apple Silicon/Intel 모두
- 목적: Cursor/VSCode 터미널에서 AI CLI(우선 Claude Code)를 쓰다가 작업이 끝나면, 화면 하단을 돌아다니는 캐릭터가 말풍선으로 알려준다. 말풍선을 누르면 해당 프로젝트 창으로 이동한다.
- 확장판: 캐릭터를 클릭하면 AI CLI 세션의 대화 전체를 채팅 UI로 볼 수 있는 "터미널 확장판" 창이 열린다.
- 1차 대상: 개인 사용 (App Store 배포 안 함, App Sandbox 끔)

---

## 2. 기술 스택 / 구조

- Swift 5.10+ (Swift 6 언어 모드는 동시성 경고가 과하면 5 모드 사용), SwiftUI + AppKit 혼합
- 프로젝트 생성: XcodeGen (`brew install xcodegen`)
- 앱 형태: **메뉴바 앱** (`LSUIElement = YES` → Dock 아이콘 없음), SwiftUI `MenuBarExtra`
- App Sandbox: OFF (홈 디렉터리의 `~/.claude` 등 읽기 위해), Hardened Runtime ON
- 로컬 통신: Network.framework `NWListener`로 **127.0.0.1 전용 HTTP 서버** (기본 포트 47821, 설정에서 변경 가능)
- 상태 관리: `@Observable` 클래스 기반 스토어 (AppState, PetState, SessionStore)
- 로그인 시 자동 실행: `SMAppService.mainApp`

### 폴더 구조 (권장)
```
TermPet/
  project.yml
  SPEC.md
  CLAUDE.md
  Sources/
    App/            # TermPetApp.swift, AppDelegate, MenuBarExtra
    Pet/            # PetWindow(NSPanel), PetView, PetController, 상태 머신, 물리(이동/중력)
    Bubble/         # BubbleWindow, BubbleView, 알림 큐
    Character/      # CharacterPack 모델, 로더, 기본 캐릭터(코드로 그림)
    Server/         # LocalHTTPServer, 이벤트 디코딩, 토큰 인증
    Events/         # PetEvent 모델, 이벤트 → 감정 매핑
    Integrations/   # Claude Code / zsh / Codex 설치기(설정 병합), 앱 포커스(NSWorkspace)
    Viewer/         # (Phase 4) 트랜스크립트 파서, 세션 목록, 채팅 UI
    Settings/       # 설정 창
  Resources/
    Characters/default/   # 기본 캐릭터 팩 (있다면)
  Scripts/
    termpet-hook          # 훅에서 호출하는 bash 스크립트
    zsh-integration.zsh   # zsh 연동 스니펫
  Tests/
```

---

## 3. 기능 명세

### 3-1. 펫 창 (Phase 1)
- 캐릭터 1마리당 **캐릭터 크기만 한 작은 투명 창** 하나. 창 자체를 움직여서 이동시킨다. (전체화면 투명 오버레이 방식 금지 → 클릭 통과 문제 회피)
- `NSPanel` 서브클래스:
  - styleMask: `.borderless`, `.nonactivatingPanel`
  - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`
  - level: `.floating` (설정에서 "항상 맨 위" 강도 조정 가능하게 확장 여지)
  - collectionBehavior: `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, `.ignoresCycle`
  - 클릭해도 다른 앱의 포커스를 뺏지 않을 것
- SwiftUI 뷰를 `NSHostingView`로 올린다.
- 바닥: 화면 맨 아래(`NSScreen.frame.minY`) — 전체 화면 앱·Dock 숨김일 때도 맨 바닥까지. 아래에 Dock이 보이면 Dock 자리에 **발판**(창처럼 다룸)을 둬서 Dock 위에서 놀다 끝에서 떨어지고, 바닥에서 Dock 옆면을 기어 올라온다. Dock 폭은 접근성 권한이 있으면 실제 값, 없으면 Dock 설정(아이콘 수×크기)으로 추정.
- 창 벽 오르기: 벽 위쪽을 앞 창이 덮고 있으면 그 창 아랫변에서 머리가 막혀 손을 놓는다.
- 멀티 모니터에서 화면 경계를 넘으면 인접 화면으로 이동하거나 벽처럼 되돌아간다.

### 3-2. 움직임과 상태 머신 (Phase 1)
- 상태(enum `PetMood/PetAction`):
  - `idle`(가만히), `walk`(걷기), `talk`(말풍선 표시 중), `happy`(신남), `angry`(화남), `ask`(확인 요청/손 흔들기), `sleep`(졸기), `dragged`(잡혀 있음), `fall`(떨어짐)
- 기본 행동: idle ↔ walk 를 랜덤 타이머로 전환. 걷는 방향 랜덤, 화면 끝에서 방향 전환, 방향에 따라 좌우 반전.
- N분(기본 10분) 동안 이벤트가 없으면 `sleep`.
- 이벤트 상태(happy/angry/ask)는 일정 시간 후 idle로 복귀.
- 이동 루프: 30~60fps 타이머(또는 `CADisplayLink`/`CVDisplayLink`)로 위치 갱신. 상태 전이 로직은 순수 함수/구조체로 분리해 테스트 가능하게.
- **창 위 산책 (Phase 9)**: '프로그램 위' 표시일 때 다른 앱 창을 지형으로 쓴다 (`Terrain`, `WindowScanner`).
  - 창 윗변 = 선반(앞 창에 가린 부분·메뉴바에 닿는 부분 제외). 떨어지다 닿으면 그 위에 선다.
  - 걷다 창 옆면에 막히면 `climb`(창 75% / 화면 끝 30%)으로 기어올라 창 위로, 아니면 돌아선다. 낮은 턱은 그냥 올라선다.
  - 창 끝에 닿으면 40% 확률로 폴짝 뛰어내리고, 아니면 돌아선다. 오르다 가끔 미끄러진다.
  - 서 있는 창을 옮기면 같이 실려 가고, 창이 닫히면 떨어진다. 잡아서 휙 놓으면 던져진다(화면 끝에서 튕김).
  - 메뉴 '창 위 산책' 칩으로 끌 수 있다.

### 3-3. 드래그 앤 드롭 (Phase 1)
- 캐릭터를 마우스로 잡으면 `dragged` 상태, 마우스를 따라 창 이동 (잡은 지점 오프셋 유지).
- 놓으면 바닥까지 중력으로 `fall` → 착지 후 idle.
- 클릭(드래그 아님)과 드래그를 이동 거리 임계값(약 4px)으로 구분한다.
  - 단일 클릭: 말풍선이 있으면 말풍선 동작, 없으면 짧은 반응(happy 모션)
  - 더블 클릭: (Phase 4) 터미널 확장판 창 열기
- 우클릭: 컨텍스트 메뉴 (확장판 열기, 재우기, 설정, 종료)

### 3-4. 캐릭터 팩 (Phase 1 기본 + Phase 3 불러오기)
- **기본 캐릭터는 이미지 없이 SwiftUI 도형으로 그린다** (둥근 몸 + 눈 + 상태별 표정/모션). 에셋 없이도 앱이 완전히 동작해야 한다.
- 커스텀 캐릭터 팩 포맷:
  ```
  ~/Library/Application Support/TermPet/Characters/<id>/
    character.json
    idle.png, walk.png, talk.png, happy.png, angry.png, ask.png, sleep.png, dragged.png, fall.png
  ```
  - 각 png는 가로 1줄 스프라이트 시트
  - character.json 예:
    ```json
    {
      "id": "my-cat",
      "name": "냥이",
      "frameWidth": 64,
      "frameHeight": 64,
      "scale": 2,
      "walkSpeed": 40,
      "pixelArt": true,
      "states": {
        "idle":  { "file": "idle.png",  "frames": 4, "fps": 6,  "loop": true },
        "walk":  { "file": "walk.png",  "frames": 6, "fps": 10, "loop": true },
        "happy": { "file": "happy.png", "frames": 6, "fps": 12, "loop": true }
      },
      "messages": {
        "done":  ["끝났어!", "작업 완료~"],
        "error": ["에러 났어…", "빨간 줄 떴어!"],
        "ask":   ["확인해줘!", "허락이 필요해"]
      }
    }
    ```
  - 정의되지 않은 상태는 `idle`로 대체.
  - `pixelArt: true`면 확대 시 보간 끄기(nearest neighbor).
- 설정 화면에서: 캐릭터 목록, 선택, 폴더 열기, "캐릭터 팩 가져오기(폴더 선택)".

### 3-5. 이벤트 수신 서버 (Phase 2)
- `POST http://127.0.0.1:47821/event`
- 보안: 앱 첫 실행 시 랜덤 토큰 생성 → `~/.termpet/token` (권한 600). 요청 헤더 `X-TermPet-Token` 이 일치해야만 처리. (브라우저에서 localhost로 오는 요청 차단 목적)
- 요청 바디(JSON) — 앱 내부 표준 이벤트:
  ```json
  {
    "source": "claude" | "codex" | "shell",
    "kind": "done" | "error" | "ask",
    "message": "선택: 표시할 문구",
    "cwd": "/Users/me/project",
    "sessionId": "선택",
    "transcriptPath": "선택",
    "command": "선택: shell 명령어",
    "exitCode": 0,
    "durationSec": 42,
    "hostBundleId": "com.todesktop.230313mzl4w4u92",
    "termProgram": "vscode"
  }
  ```
- `GET /health` → 200 (훅 스크립트가 앱 실행 여부 확인용)
- 이벤트 → 감정 매핑: done→happy, error→angry, ask→ask. 말풍선 문구는 `message`가 있으면 사용, 없으면 캐릭터 팩의 messages에서 랜덤 + 프로젝트 이름(cwd의 마지막 폴더명) 표시. 예: "fitin 작업 끝났어!"

### 3-6. 연동 스크립트 (Phase 2)
`Scripts/termpet-hook` (bash, 앱이 `~/.termpet/bin/`에 설치):
- 사용법: `termpet-hook claude` (stdin으로 Claude Code 훅 JSON 수신), `termpet-hook shell ...인자`, `termpet-hook codex '<json>'`
- 환경변수 `__CFBundleIdentifier`(통합 터미널이 상속한 호스트 앱 번들 ID), `TERM_PROGRAM`을 함께 전송 → 어떤 앱(Cursor/VSCode/iTerm/Terminal)에서 실행됐는지 판별
- `jq`가 없을 수 있으니 의존하지 말 것 (필요하면 `/usr/bin/python3` 없이도 동작하게, 원본 JSON을 `raw` 필드로 그대로 넘기고 파싱은 앱에서)
- `curl --max-time 1` + 백그라운드 실행. **앱이 꺼져 있어도 AI CLI/쉘이 절대 느려지거나 에러를 내지 않을 것.**

**Claude Code 연동** (`~/.claude/settings.json`에 병합):
- `Stop` 훅 → kind `done`
- `Notification` 훅 → kind `ask` (권한 요청/입력 대기 메시지)
- 훅 입력의 `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `message` 를 활용
- 형식은 현재 Claude Code 훅 문서를 확인해서 맞출 것. 기존 hooks 배열에 추가(중복 설치 방지), 제거 기능도 제공.

**zsh 연동** (`~/.zshrc`에 source 한 줄 추가):
- `preexec`/`precmd` 로 명령 시작 시각·명령어·종료 코드 측정
- 실행 시간이 임계값(기본 30초) 이상인 명령만 전송. 종료 코드 0 → done, 그 외 → error
- 대화형 명령(`claude`, `codex`, `vim`, `nvim`, `less`, `ssh`, `top` 등)은 제외 목록으로 무시

**Codex CLI 연동** (Phase 5, 선택): `~/.codex/config.toml`의 notify 설정. 형식은 현재 문서 확인 후 구현.

### 3-7. 말풍선 (Phase 2)
- 캐릭터 머리 위에 별도 투명 패널. 캐릭터를 따라 움직인다. 화면 위/옆 경계에서 잘리지 않게 위치 보정.
- 여러 알림이 오면 큐로 쌓고, 말풍선에 "+2" 같은 배지 표시. 클릭할 때마다 다음 알림.
- 일정 시간(기본 15초, 설정 가능) 후 사라지지만, 미확인 알림이 있으면 캐릭터 머리 위에 작은 "!" 표시 유지.
- 선택 옵션: 효과음, macOS 시스템 알림 동시 발송.

### 3-8. 말풍선 클릭 → 해당 화면으로 이동 (Phase 2)
- `hostBundleId`로 앱 판별 (Cursor, VSCode, iTerm2, Terminal, Warp 등). 없으면 `termProgram`으로 추정.
- Cursor/VSCode: `NSWorkspace.shared.open([cwd 폴더 URL], withApplicationAt: 앱URL, configuration:)` 로 해당 프로젝트 창을 앞으로 가져온다 (이미 열려 있으면 그 창이 포커스됨).
- 그 외 터미널 앱: 해당 앱 활성화만.
- 정확한 터미널 탭 포커스는 Phase 5의 VSCode/Cursor 확장으로 처리.

### 3-9. 메뉴바 & 설정 (Phase 3)
- 메뉴바 아이콘 메뉴: 캐릭터 보이기/숨기기, 재우기/깨우기, 최근 알림 5개(클릭 시 이동), 터미널 확장판 열기, 설정, 종료
- 설정 창 탭:
  - 일반: 로그인 시 실행, 걷기 속도, 크기, 말풍선 유지 시간, 효과음
  - 캐릭터: 목록/선택/가져오기
  - 연동: Claude Code / zsh / Codex 각각 [설치] [제거] 버튼 + 상태 표시, "테스트 알림 보내기" 버튼, 포트 설정
- 설정 저장: `UserDefaults` (또는 `@AppStorage`)

### 3-10. 터미널 확장판 — 세션 뷰어 (Phase 4)
- 캐릭터 더블클릭 / 메뉴에서 열리는 일반 창 (좌측 세션 목록, 우측 채팅)
- 세션 목록: `~/.claude/projects/` 아래 `.jsonl` 파일들을 수정 시각순으로. 프로젝트(cwd)별 그룹. 알림으로 받은 `transcriptPath`가 있으면 그 세션을 바로 연다.
- 트랜스크립트 파싱 (JSONL, 한 줄 = 한 이벤트):
  - user 메시지 → 오른쪽 말풍선
  - assistant 텍스트 → 왼쪽 말풍선 (마크다운 렌더링)
  - tool 사용(명령 실행, 파일 읽기/수정 등) → 접을 수 있는 카드 (도구 이름 + 요약, 펼치면 상세)
  - tool 결과 → 해당 카드 안에 표시, 길면 잘라서 "더보기"
  - 알 수 없는 타입은 조용히 건너뛴다. 형식이 공식 문서화되어 있지 않으므로 **모든 필드를 옵셔널로 방어적 디코딩**.
- 실시간 갱신: 파일 변경 감시(`DispatchSource.makeFileSystemObjectSource`)로 새 줄이 추가되면 append, 맨 아래로 자동 스크롤(사용자가 위로 스크롤 중이면 유지).
- 검색(세션 내 텍스트 검색), "이 프로젝트 열기" 버튼.
- 읽기 전용. (입력 기능은 Phase 6)

### 3-11. 이후 확장 (Phase 5~6, 지금은 설계만 고려)
- Phase 5: Cursor/VSCode 확장 프로그램(TypeScript) — TermPet에서 요청이 오면 해당 PID/세션의 터미널 탭에 포커스. Codex 연동. 여러 세션 동시 진행 시 프로젝트별 알림 구분.
- Phase 6: 앱 내장 터미널(PTY, 예: SwiftTerm)로 AI CLI를 직접 실행하고 채팅창에서 입력 전송.

---

## 4. Phase 계획

| Phase | 목표 | 완료 기준 (내가 직접 확인) |
|---|---|---|
| 0 | 프로젝트 셋업 | XcodeGen 프로젝트 생성, 메뉴바 아이콘만 뜨는 빈 앱 빌드/실행, Dock 아이콘 없음, git init |
| 1 | 펫 | 기본 캐릭터가 Dock 위를 걸어다님, 상태 전환, 모든 Space/전체화면 앱 위에 보임, 드래그 후 떨어짐, 클릭 시 포커스 안 뺏음 |
| 2 | 알림 | 로컬 서버 + 토큰, termpet-hook, Claude Code/zsh 연동(수동 설치 안내 먼저), 말풍선 + 큐, 클릭 시 Cursor/VSCode 해당 프로젝트로 이동 |
| 3 | 메뉴바·설정·캐릭터 팩 | 설정 창, 연동 자동 설치/제거(백업 포함), 테스트 알림, 커스텀 캐릭터 팩 불러오기, 로그인 시 실행 |
| 4 | 터미널 확장판 | 세션 목록, 채팅 UI, 도구 카드, 실시간 갱신, 알림에서 바로 해당 세션 열기 |
| 5 | 확장 | VSCode/Cursor 확장으로 정확한 탭 포커스, Codex 연동, 다중 세션 |
| 6 | 내장 터미널 | 앱 안에서 AI CLI 실행 + 입력 |
| 9 | 놀이 업데이트 | 창 위 산책·벽 오르기·던지기, 친구 팩(여러 포즈) 기본 캐릭터, 파스텔 메뉴 패널·아이콘 |
| 10 | 다듬기 | Dock 발판·전체 화면 맨 바닥, 가려진 벽 막힘, 친구 팩 크기 통일·잘림 제거·벽 타기 포즈, 기본 캐릭터 목록·캐릭터 만들기 기능 제거 |
| 15 | 메뉴 패널 정리 | 빠른 칩 + 탭(친구·알림·연결·설정), 최근 알림 목록(누르면 이동), 크기·걷기 속도·말풍선 시간 슬라이더, 우클릭 메뉴의 죽은 항목 제거·숨기기 추가, 16/32px 앱 아이콘 단순화 |
| 16 | 윈도우 연결 보완 | Claude 훅을 `shell: powershell` + 실행 정책 무관 스크립트로(Git 유무 상관없이 동작), 예전 형식은 [업데이트], 포트 자동 재시도, [확인] 버튼으로 PC별 단계 진단(설정·정책·서버·실제 훅 실행·한글)·실행 정책 [허용], 윈도우 서버 실제 동작 테스트(Actions) |
| 17 | 캐릭터 만들기·삭제 | `make-character` 스킬(LINE 스티커 수집·포즈 시트·레시피 빌더·어두운 배경 미리보기), 패널 친구 타일 우클릭 → 지우기(휴지통, 맥·윈도우), 패널 열 때 친구 목록 다시 읽기 |
| 18 | 친구 더하기 | "친구 추가하기"가 기존 친구를 지우지 않고 더함(같은 id만 교체, 폴더 이름이 달라도), 맥·윈도우. 업데이트 후 실행 중이던 앱 경로로 다시 열기(다른 TermPet.app이 열리던 문제) |
| 19 | Claude 앱 채팅 알림 | Claude 데스크톱 앱 일반 채팅(훅 없음)을 MCP 도구 `termpet_notify`로 연결: 맥 `TermPet --mcp`(stdio JSON-RPC), 윈도우 `TermPet.exe` + `ELECTRON_RUN_AS_NODE` + `termpet-mcp.js`, `claude_desktop_config.json`의 `mcpServers.termpet` 백업 후 병합(윈도우 스토어판 경로 포함), 말풍선 제목 "Claude 채팅"·누르면 Claude 앱으로, 윈도우 [확인] 실제 실행 점검. 업데이트 후 '업데이트 중' 표시가 남던 문제 수정 |

각 Phase 시작 전에 해당 Phase의 세부 작업 목록을 먼저 보여주고 진행하라.

---

## 5. 빌드·실행·배포

- 개발 중 실행: Xcode에서 `TermPet.xcodeproj` 열고 ⌘R, 또는 `xcodebuild ... build` 후 `open build/.../TermPet.app`
- 개인 사용은 서명 없이(또는 개인 팀 서명) 실행.
- 나중에 배포 시: Developer ID 서명 + 공증(notarytool) 스크립트를 `Scripts/release.sh`로 추가.

---

## 6. 시작 명령

지금 바로 **Phase 0**을 시작해라:
1. 필요한 도구 확인 (`xcodebuild -version`, `xcodegen --version`; 없으면 설치 방법 안내 후 대기)
2. `SPEC.md`(이 문서), `CLAUDE.md`(작업 규칙 요약) 작성
3. `project.yml` 작성 → `xcodegen generate` → 빌드
4. 내가 확인할 체크리스트를 보여주고 멈춰라.
