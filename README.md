<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="텀펫">
</p>

<h1 align="center">텀펫</h1>

<p align="center">Claude Code·Codex·터미널 작업이 끝나면 알려주는 데스크톱 펫 (macOS · Windows)</p>

<p align="center">
  <b>macOS</b> <code>brew install --cask anjinhyeong/tap/termpet</code><br>
  <b>Windows</b> <a href="https://github.com/AnJinHyeong/TermPet/releases/latest">최신 릴리스</a>에서 <code>TermPet-Setup-&lt;버전&gt;.exe</code>
</p>

---

AI 에이전트나 빌드를 돌려 두고 다른 일을 하다 보면 끝난 걸 놓치기 쉽습니다.
텀펫은 화면 위를 돌아다니며 놀다가, 작업이 끝나거나 권한이 필요하면 말풍선으로 알려줍니다.
말풍선을 누르면 그 작업을 하던 에디터·터미널 창으로 바로 이동합니다.

## 목차

- [기능](#기능) — 알림 · 놀이 · 메뉴 패널
- [설치 · 업데이트](#설치--업데이트) — [macOS](#macos) · [Windows](#windows)
- [AI 연결](#ai-연결)
- [캐릭터](#캐릭터) — 추가 · 삭제 · [캐릭터 만들기 (Claude Code 스킬)](#캐릭터-만들기-claude-code-스킬)
- [지금까지 개발된 내용](#지금까지-개발된-내용)
- [문제 해결](#문제-해결) · [개발](#개발)

## 기능

### 알림

| | |
|---|---|
| **작업 완료** | Claude Code(터미널·데스크톱 앱·IDE)·Codex가 응답을 마치면 알림 |
| **권한 요청** | 소리와 함께 승인할 때까지 말풍선 유지. 터미널에서 승인하면 저절로 사라짐 |
| **한국어 안내** | "입력을 기다리고 있어요", "Bash 사용을 허락해 줄래요?"처럼 Claude Code 알림을 한국어로 |
| **긴 명령** | 30초 넘게 걸린 터미널 명령(zsh / PowerShell)이 끝나면 성공·실패를 표정으로 |
| **진행 상황** | 작업 중이면 머리 위 `•••`, 권한 대기 중이면 ✋. 메뉴에서 프로젝트별 상태 확인 |
| **최근 알림** | 말풍선을 놓쳐도 메뉴의 **최근 알림**에서 다시 보고, 누르면 그 창으로 이동 (맥) |
| **놓친 알림** | 머리 위 `!` — 펫을 누르면 다시 보기 |
| **조용한 시간** | 1시간 동안, 또는 회의 중(마이크 사용 중)엔 알림을 모아 뒀다가 나중에 |

### 놀이

- **창 위 산책** — 다른 앱 창 윗면을 걸어 다니고, 창 옆면을 기어올라 위로 올라섭니다. 창을 움직이면 같이 실려 갑니다
- **가려진 벽은 막힘** — 오르던 벽 위를 다른 창이 덮고 있으면 거기서 멈추고 뛰어내립니다
- **Dock / 작업 표시줄 위에서 놀기** — 끝에서 뛰어내리고, 바닥에서 옆면을 기어 올라옵니다
- **전체 화면** — 전체 화면 앱에서는 화면 맨 아래로 내려갑니다
- **잡아서 던지기** — 펫을 끌어서 휙 던지면 날아가서 떨어집니다
- **하루 기록 · 기분** — 펫을 누르면 오늘 끝낸 작업 수. 성공이 이어지면 신나고(✨), 에러가 이어지면 시무룩(🌧)
- **표시 위치** — 항상 위 / 바탕화면에만 / 알림이 올 때만 앞으로

### 메뉴 패널

맥은 메뉴바의 토끼 아이콘, 윈도우는 작업 표시줄 트레이의 텀펫 아이콘을 누르면 열립니다.

**macOS** (위에서부터)

| 영역 | 내용 |
|---|---|
| 무대 | 지금 친구 · 알림 서버 상태 · 오늘 기록 · 보이기/숨기기 스위치 |
| 진행 중 · 최근 알림 | 작업 중인 세션과 최근 알림 4개 (누르면 그 창으로) |
| 빠른 칩 | 재우기 · 1시간 조용히 · 떨어뜨리기 |
| 탭 **친구** | 친구 고르기 · ＋ 추가 · 우클릭 삭제 |
| 탭 **알림** | 회의 중 · 권한 소리 · 알림 테스트 · 말풍선 유지 시간(2~10초) |
| 탭 **연결** | Claude Code · Codex · 터미널 명령 연결 (업데이트가 필요하면 탭에 빨간 점) |
| 탭 **설정** | 크기(60~160%) · 걷기 속도 · 표시 위치 · 창 위 산책 · Dock 정확히 |

**Windows**: 한 화면에 무대 → 진행 중 → 친구 고르기 → 놀기 → AI 연결(＋ **확인** 버튼) → 알림 → 표시 위치 순서입니다. 트레이 아이콘을 오른쪽 클릭하면 빠른 메뉴(친구 추가·폴더 열기·새로고침·종료)가 나옵니다.

## 설치 · 업데이트

### macOS

macOS 14 이상.

```bash
brew trust anjinhyeong/tap                     # 처음 한 번 (Homebrew 7+: 공식 아닌 tap 허용)
brew install --cask anjinhyeong/tap/termpet   # 설치
brew update && brew upgrade --cask termpet     # 업데이트
```

- 새 버전이 나오면 메뉴 위쪽에 **업데이트** 버튼이 뜹니다. 누르면 Homebrew로 업데이트한 뒤 다시 켜집니다.
- 메뉴 아래쪽 버전 글씨를 누르면 바로 새 버전을 확인합니다.
- `Warning: Not upgrading termpet, the latest version is already installed`가 나오면 이미 최신입니다. 패널이 예전 모습이면 텀펫을 **종료 후 다시 켜** 주세요.

### Windows

Windows 10(1803+) / 11, x64.

**설치**

1. [최신 릴리스](https://github.com/AnJinHyeong/TermPet/releases/latest)에서 `TermPet-Setup-<버전>.exe`를 받습니다.
   설치 파일은 릴리스 후 몇 분 뒤 붙습니다. 아직 없으면 잠시 후 새로고침해 주세요.
2. 실행합니다. 서명이 없는 앱이라 "Windows의 PC 보호" 창이 뜨면 **추가 정보 → 실행**을 누릅니다.
3. 설치가 끝나면 텀펫이 켜지고, 작업 표시줄 오른쪽 트레이(^ 안쪽일 수 있음)에 아이콘이 생깁니다. 바탕화면 바로가기도 만들어집니다.
4. 트레이 아이콘 → **AI 연결**에서 Claude Code를 **연결**합니다. 연결 직후 자동으로 [확인](#연결-확인-windows)이 돌아갑니다.

**업데이트**

- 시작할 때와 6시간마다 새 버전을 확인합니다. 새 버전이 있으면 메뉴 위쪽에 **업데이트** 버튼이 뜹니다.
- 누르면 설치 파일을 받아 **조용히 설치한 뒤 다시 켜집니다**. 설정과 친구들은 그대로 유지됩니다.
- 메뉴 아래쪽 버전 글씨를 누르면 바로 확인합니다.
- 자동 업데이트가 안 되면 릴리스 페이지에서 새 `.exe`를 받아 실행하면 그 위에 덮어 설치됩니다.
- 업데이트 후 AI 연결에 **⟳ 업데이트**가 보이면 한 번 눌러 주세요. 새 버전에 맞게 연결 형식을 바꿉니다 (백업 후).

**삭제**: 설정 → 앱 → 설치된 앱 → 텀펫 → 제거. 연결했던 설정 파일 항목은 먼저 메뉴에서 연결 해제해 두면 깔끔합니다.

## AI 연결

메뉴 → **연결**(윈도우: **AI 연결**)에서 **연결**을 누르면 끝입니다. 다시 누르면 해제됩니다.

| 항목 | macOS | Windows |
|---|---|---|
| Claude Code | `~/.claude/settings.json` 훅 | `%USERPROFILE%\.claude\settings.json` 훅 (PowerShell로 실행) |
| Codex | `~/.codex/config.toml`의 `notify` (기존 notify는 유지) | 같음 |
| 터미널 명령 | `~/.zshrc` 한 줄 | PowerShell 프로필 한 줄 (5.1 · 7) |

- 기존 설정은 지우지 않고 텀펫 항목만 더하며, 바꾸기 전에 `*.termpet-backup-<시간>`으로 백업합니다.
- 텀펫이 꺼져 있어도 훅은 조용히 바로 끝나서 CLI·쉘을 느리게 하지 않습니다.
- 직접 설정하려면 [docs/SETUP.md](docs/SETUP.md)를 참고하세요.

### 연결 확인 (Windows)

윈도우는 PC마다 환경(Git 설치 여부, PowerShell 실행 정책, 회사 보안 정책)이 달라서, 연결 줄마다 **확인** 버튼이 있습니다.
누르면 훅을 Claude Code가 실행하는 방식 그대로 직접 실행해 보고, 앱까지 도착하는지(한글 포함) 단계별 ✓ / ✗와 해결 방법을 보여줍니다.

| 단계 | 문제가 있으면 |
|---|---|
| 설정 파일 | [연결] 또는 [⟳ 업데이트] |
| 훅 허용 | 회사 정책(`allowManagedHooksOnly` 등)이나 `disableAllHooks`가 막고 있음 |
| 알림 서버 | 포트가 막히면 자동으로 다음 포트를 씀. 그래도 실패하면 메시지 확인 |
| 훅 실행 → 앱 도착 | 백신·보안 프로그램이 PowerShell을 막는지 확인 |
| 스크립트 실행 허용 (터미널 명령) | 실행 정책이 Restricted → [허용] (내 계정만 RemoteSigned) |

### 지원 앱

알림은 어떤 터미널에서든 옵니다. 말풍선을 눌렀을 때의 동작만 다릅니다.

| 앱 | 말풍선 클릭 시 |
|---|---|
| Cursor, VSCode, Windsurf, Zed | 해당 프로젝트 창으로 이동 |
| Terminal, iTerm2, Warp, Ghostty, WezTerm, kitty, Windows Terminal | 앱을 앞으로 |
| Claude 데스크톱 앱 · 일반 콘솔 (Windows) | 프롬프트를 보냈던 그 창으로 |

## 캐릭터

### 추가 · 삭제

- **추가**: 메뉴 → 친구의 **＋(친구 추가하기)** 에서 캐릭터 팩 zip(또는 폴더)을 고릅니다.
  **지금 친구들은 모두 지워지고** zip 안의 친구들로 바뀝니다 (잘못된 zip이면 기존 친구 유지).
  하나만 더하려면 팩 폴더를 친구 폴더에 직접 복사하세요. 메뉴를 다시 열면 나타납니다.
- **삭제**: 친구 타일을 **우클릭 → 지우기**. 휴지통으로 옮겨지므로 실수해도 되살릴 수 있습니다.
- 친구 폴더: 맥 `~/Library/Application Support/TermPet/Friends/<id>/`, 윈도우 `%APPDATA%\TermPet\Friends\<id>\`
- 팩 형식(동작별 포즈 여러 장, 바라보는 방향, 벽 타기 포즈 등): [docs/CHARACTER_PACK.md](docs/CHARACTER_PACK.md)
- 팩이 하나도 없으면 내장 캐릭터 '말랑이'가 나옵니다.

### 캐릭터 만들기 (Claude Code 스킬)

이 저장소에는 Claude Code용 **`make-character` 스킬**이 들어 있습니다 (`.claude/skills/make-character/`).
저장소 폴더에서 Claude Code를 열고 말로 부탁하면 됩니다.

1. 원본 그림 모으기: LINE 스티커, 직접 준 그림, 공식 사이트 그림
2. 포즈 고르기
3. 배경·글씨 조각 지우기
4. 다른 친구들과 크기 맞추기
5. 움직임 입히기
6. 어두운 배경에서 확인
7. 친구 폴더에 설치

**이렇게 부탁하세요**

```text
나메코로 캐릭터 만들어줘
```
```text
LINE 스티커 팩 1263048 로 친구 하나 만들어줘. 이름은 '나메코', 말투는 느긋하게
```
```text
~/Downloads/토코몬.png 스프라이트 시트로 캐릭터 만들어줘. 4×7 칸이고 첫 줄이 가만히, 둘째 줄이 걷기야
```
```text
쿠리만쥬 idle 포즈를 다른 그림으로 바꿔줘 / 걷기가 너무 커 보여, 조금 작게
```

**잘 만드는 요령**

- 출처를 알려 주면 빠릅니다. LINE 스토어 주소(`store.line.me/stickershop/product/<숫자>`)나 그림 파일 경로를 주세요.
- **몸 전체가 보이는 그림**이 있어야 가만히·걷기가 자연스럽습니다. 얼굴만 있는 팩이면 다른 팩을 더 알려 주세요.
- 상태별로 원하는 포즈가 있으면 말해 주세요 (예: "자는 건 이불 덮은 그림으로").
- 결과 미리보기를 보고 "이건 다른 그림으로", "더 작게" 같이 고쳐 달라고 하면 됩니다.
- 그림은 개인용입니다. 저작권 그림은 저장소에 넣지 않고 친구 폴더에만 둡니다.
- 친구가 너무 많아지면 패널에서 우클릭으로 정리하세요.

**스크립트만 직접 쓰기** (Python 3 + Pillow)

```bash
S=.claude/skills/make-character/scripts
python3 $S/fetch_line.py 1263048 work/src                 # LINE 팩 받기
python3 $S/sheet.py sources work/sources.png work/src      # 후보 그림 한 장으로 보기
python3 $S/build_pack.py work/recipe.json work/out         # 레시피대로 팩 만들기
python3 $S/sheet.py pack work/pack.png work/out/<id>       # 결과 확인 (어두운 배경)
```
레시피 형식과 옵션은 [SKILL.md](.claude/skills/make-character/SKILL.md)에 있습니다.

## 지금까지 개발된 내용

| 버전 | 날짜 | 내용 |
|---|---|---|
| 0.1 | 2026-11-09 | 메뉴바 앱, 펫 창(걷기·중력·드래그), 로컬 알림 서버(토큰), Claude Code·zsh 훅, 말풍선 큐, 프로젝트 창으로 이동, 표시 위치, 메뉴에서 연결(백업 후 병합) |
| 0.1.x | 2026-11-09 | 작업 중·권한 대기 표시, 진행 중 세션 목록, 조용한 시간·회의 중, 권한 요청 소리, 하루 기록·기분, 여러 장 애니메이션 |
| 0.2 | 2026-11-10 | 창 위 산책(착지·벽 오르기·뛰어내리기·던지기·창 따라가기), Dock 발판, 전체 화면 맨 바닥, 친구 팩(포즈 변형) 기본 캐릭터, 파스텔 메뉴 패널, Claude 알림 한국어 |
| 0.3 | 2026-11-10 | 친구 추가하기(zip·폴더), 메뉴에서 바로 앱 업데이트(Homebrew) |
| 0.4 | 2026-11-10 | **윈도우판** (Electron): 같은 놀이·알림·연결(PowerShell 프로필), 트레이 패널, 설치 파일·자동 업데이트, Claude 데스크톱 앱 창으로 이동 |
| 0.5 | 2026-11-11 | 맥 메뉴 패널 정리(빠른 칩 + 탭), 최근 알림, 크기·걷기 속도·말풍선 시간 설정, 작은 앱 아이콘 정리 |
| 다음 버전 | — | 윈도우 연결 보완(Git·실행 정책과 상관없이 동작, **확인** 버튼, 포트 자동 재시도), 친구 삭제(맥·윈도우), `make-character` 스킬 |

자세한 개발 단계는 [SPEC.md](SPEC.md)의 Phase 표에 있습니다.

## 권한

| 권한 | 필요 여부 | 용도 |
|---|---|---|
| 없음 | 기본 | 창 위치·크기만 읽습니다 (창 제목·내용은 읽지 않음) |
| 손쉬운 사용 (맥) | 선택 | 메뉴 → 설정 → **Dock 정확히**. Dock 폭을 정확히 읽어 끝에서 딱 맞게 뛰어내림 (끄면 Dock 설정으로 추정) |

## 문제 해결

| | macOS | Windows |
|---|---|---|
| 받은 요청 기록 | `tail -f ~/.termpet/events.log` | `Get-Content $HOME\.termpet\events.log -Tail 20 -Wait` |
| 앱 상태 | `curl http://127.0.0.1:47821/health` | 메뉴 무대의 "알림 받는 중" (포트가 바뀌면 함께 표시) |
| 말풍선 확인 | 메뉴 → 알림 → **알림 테스트** | 메뉴 → 놀기 → **알림 테스트** |
| 연결 점검 | 연결 탭의 상태 | AI 연결의 **확인** 버튼 |

- Claude 알림이 전혀 안 오면, 먼저 이벤트 기록에 `/hook/claude` 줄이 찍히는지 보세요. 없으면 훅이 앱까지 오지 못한 것입니다. 윈도우는 **확인** 버튼이 원인을 알려줍니다.

## 개발

**macOS** — Swift · SwiftUI + AppKit · [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`만 수정, `.xcodeproj`는 생성물)

```bash
Scripts/run.sh               # 빌드 + 실행 (--logs: 로그 보기, --gen: 프로젝트 재생성)
Scripts/install.sh           # Release 빌드 → /Applications
Scripts/release.sh <버전>     # GitHub Release + Homebrew cask 갱신 + 윈도우 설치 파일 빌드(Actions) 시작
xcodebuild -project TermPet.xcodeproj -scheme TermPet test   # 테스트
```

**Windows** — `windows/` 폴더, Electron + React + TypeScript

```bash
cd windows
npm install
npm run dev        # 개발 실행 (맥에서도 실행되지만 포트 47831 · ~/.termpet-electron-dev 를 써서 맥 앱과 안 겹침)
npm test           # 로직 테스트 (vitest). 훅 실제 실행 테스트는 윈도우에서만 돈다
npm run dist:win   # Windows 설치 파일 → windows/dist/TermPet-Setup-<버전>.exe
```

- `windows/`가 바뀐 커밋을 푸시하면 GitHub Actions(**Windows tests**)가 실제 윈도우에서 테스트합니다 (PowerShell 5.1·7로 훅 실행 포함).
- 릴리스의 윈도우 설치 파일은 **Windows installer** 워크플로가 빌드해서 붙입니다.

## 라이선스

MIT
