<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="텀펫">
</p>

<h1 align="center">텀펫</h1>

<p align="center">Claude Code·Codex·터미널 작업이 끝나면 알려주는 macOS 데스크톱 펫</p>

<p align="center">
  <code>brew install --cask anjinhyeong/tap/termpet</code>
</p>

---

AI 에이전트나 빌드를 돌려 두고 다른 일을 하다 보면 끝난 걸 놓치기 쉽습니다.
텀펫은 화면 위를 돌아다니며 놀다가, 작업이 끝나거나 권한이 필요하면 말풍선으로 알려줍니다.
말풍선을 누르면 그 작업을 하던 에디터·터미널 창으로 바로 이동합니다.

## 알림

| | |
|---|---|
| **작업 완료** | Claude Code·Codex가 응답을 마치면 알림 |
| **권한 요청** | 소리와 함께 승인할 때까지 말풍선 유지. 터미널에서 승인하면 저절로 사라짐 |
| **한국어 안내** | "입력을 기다리고 있어요", "Bash 사용을 허락해 줄래요?"처럼 Claude Code 알림을 한국어로 |
| **긴 명령** | 30초 넘게 걸린 터미널 명령이 끝나면 성공·실패를 표정으로 |
| **진행 상황** | 작업 중이면 머리 위 `•••`, 권한 대기 중이면 ✋. 메뉴에서 프로젝트별 상태 확인 |
| **놓친 알림** | 머리 위 `!` — 펫을 누르면 다시 보기 |
| **조용한 시간** | 1시간 동안, 또는 회의 중(마이크 사용 중)엔 알림을 모아 뒀다가 나중에 |

## 놀이

- **창 위 산책** — 다른 앱 창 윗면을 걸어 다니고, 창 옆면을 기어올라 위로 올라섭니다. 창을 움직이면 같이 실려 갑니다
- **가려진 벽은 막힘** — 오르던 벽 위를 다른 창이 덮고 있으면 거기서 멈추고 뛰어내립니다
- **Dock 위에서 놀기** — Dock 위를 걷다가 끝에서 뛰어내리고, 바닥에서 Dock 옆면을 기어 올라옵니다
- **전체 화면** — 전체 화면 앱에서는 화면 맨 아래로 내려갑니다
- **잡아서 던지기** — 펫을 끌어서 휙 던지면 날아가서 떨어집니다
- **하루 기록 · 기분** — 펫을 누르면 오늘 끝낸 작업 수. 성공이 이어지면 신나고(✨), 에러가 이어지면 시무룩(🌧)
- **표시 위치** — 항상 위 / 바탕화면에만 / 알림이 올 때만 앞으로

## 설치

```bash
brew trust anjinhyeong/tap                     # 처음 한 번 (Homebrew 7+: 공식 아닌 tap 허용)
brew install --cask anjinhyeong/tap/termpet   # 설치
brew update && brew upgrade --cask termpet     # 업데이트
```

새 버전이 나오면 메뉴 위쪽에 **업데이트** 버튼이 뜹니다. 누르면 Homebrew로 업데이트한 뒤 다시 켜집니다 (메뉴 아래 버전 글씨를 누르면 바로 확인).

macOS 14 이상.

## 연결

메뉴바 아이콘 → **AI 연결**에서 **연결**을 누르면 끝입니다. 다시 누르면 해제됩니다.

| 항목 | 바뀌는 파일 |
|---|---|
| Claude Code | `~/.claude/settings.json` — 응답 완료·권한 요청·진행 상황 훅 추가 |
| Codex | `~/.codex/config.toml` — `notify` 추가 (기존 notify는 유지) |
| 터미널 명령 | `~/.zshrc` — 한 줄 추가 |

기존 설정은 지우지 않고 텀펫 항목만 더하며, 바꾸기 전에 `*.termpet-backup-<시간>`으로 백업합니다.
텀펫이 꺼져 있어도 훅은 1초 안에 조용히 끝나서 CLI·쉘을 느리게 하지 않습니다.
직접 설정하려면 [docs/SETUP.md](docs/SETUP.md)를 참고하세요.

## 지원 앱

알림은 어떤 터미널에서든 옵니다. 말풍선을 눌렀을 때의 동작만 다릅니다.

| 앱 | 말풍선 클릭 시 |
|---|---|
| Cursor, VSCode, Windsurf, Zed | 해당 프로젝트 창으로 이동 |
| Terminal, iTerm2, Warp, Ghostty, WezTerm, kitty | 앱을 앞으로 |

## 캐릭터

메뉴 → **친구 고르기**의 **＋(친구 추가하기)** 를 누르고 캐릭터 팩 zip(또는 폴더)을 고르면 바로 추가됩니다.
zip 하나에 여러 친구가 들어 있어도 모두 한 번에 등록되고, 같은 id의 친구는 새것으로 바뀝니다.
팩은 `~/Library/Application Support/TermPet/Friends/<id>/`에 저장됩니다 (직접 넣어도 됩니다).
동작별 포즈 여러 장, 바라보는 방향, 벽 타기 포즈 등을 지정할 수 있습니다. 형식은 [docs/CHARACTER_PACK.md](docs/CHARACTER_PACK.md)를 참고하세요.
팩이 하나도 없으면 내장 캐릭터 '말랑이'가 나옵니다.

## 권한

| 권한 | 필요 여부 | 용도 |
|---|---|---|
| 없음 | 기본 | 창 위치·크기만 읽습니다 (창 제목·내용은 읽지 않음) |
| 손쉬운 사용 | 선택 | 메뉴 → 놀기 → **Dock 정확히**. Dock 폭을 정확히 읽어 끝에서 딱 맞게 뛰어내림 (끄면 Dock 설정으로 추정) |

## 문제 해결

- 받은 요청 기록: `tail -f ~/.termpet/events.log`
- 앱 상태: `curl http://127.0.0.1:47821/health`
- 메뉴의 **알림 테스트**로 말풍선 표시 확인

## 개발

```bash
Scripts/run.sh               # 빌드 + 실행 (--logs: 로그 보기, --gen: 프로젝트 재생성)
Scripts/install.sh           # Release 빌드 → /Applications
Scripts/release.sh <버전>     # GitHub Release + Homebrew cask 갱신
xcodebuild -project TermPet.xcodeproj -scheme TermPet test   # 테스트
```

Swift · SwiftUI + AppKit · [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`만 수정, `.xcodeproj`는 생성물)

## 라이선스

MIT
