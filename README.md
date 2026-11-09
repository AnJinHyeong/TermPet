<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="텀펫">
</p>

<h1 align="center">텀펫</h1>

<p align="center">Claude Code와 터미널 작업이 끝나면 알려주는 macOS 데스크톱 펫</p>

---

AI 에이전트나 빌드를 돌려 두고 다른 일을 하다 보면 끝난 걸 놓치기 쉽습니다.
텀펫은 화면 아래를 돌아다니다가 작업이 끝나면 말풍선으로 알려주고, 말풍선을 누르면 그 작업을 하던 에디터 창으로 데려다줍니다.

## 기능

- **AI 작업 알림** — Claude Code·Codex가 응답을 마치거나 권한을 물어보면 알림
- **진행 상황** — 작업 중이면 펫 머리 위에 `•••`, 권한을 기다리면 ✋. 메뉴에서 프로젝트별 진행 상황 확인
- **권한 요청 강조** — 소리와 함께 승인할 때까지 말풍선 유지, 터미널에서 승인하면 저절로 사라짐
- **조용한 시간** — 1시간 또는 회의 중(마이크 사용 중)엔 알림을 모아뒀다가 나중에 보여줌
- **긴 명령 알림** — 30초 넘게 걸린 터미널 명령이 끝나면 성공·실패를 펫의 표정으로 알림
- **바로 이동** — 말풍선을 누르면 해당 Cursor / VSCode 프로젝트 창으로 이동
- **놓친 알림 보관** — 펫 머리 위 `!`, 펫을 누르면 다시 보기
- **캐릭터** — 기본 캐릭터 4종, 그림 한 장으로 내 캐릭터 만들기 (배경 자동 제거)
- **표시 위치** — 항상 위 / 바탕화면에만 / 알림이 올 때만 앞으로

## 설치

```bash
brew install --cask anjinhyeong/tap/termpet
```

macOS 14 이상. 업데이트는 `brew upgrade --cask termpet`.

## 연결

메뉴바 아이콘 → **AI 연결**에서 **연결** 버튼을 누르면 끝입니다.

| 항목 | 바뀌는 파일 |
|---|---|
| Claude Code | `~/.claude/settings.json` (응답 완료·권한 요청·진행 상황 훅 추가) |
| Codex | `~/.codex/config.toml` (`notify` 추가, 기존 notify는 유지) |
| 터미널 명령 | `~/.zshrc` (한 줄 추가) |

기존 설정은 지우지 않고 텀펫 항목만 추가하며, 바꾸기 전에 `*.termpet-backup-<시간>` 으로 백업합니다. 다시 누르면 해제됩니다.
직접 설정하려면 [docs/SETUP.md](docs/SETUP.md)를 참고하세요.

## 지원 터미널

알림은 어떤 터미널에서든 옵니다. 말풍선을 눌렀을 때의 동작만 다릅니다.

| 앱 | 말풍선 클릭 시 |
|---|---|
| Cursor, VSCode, Windsurf, Zed | 해당 프로젝트 창으로 이동 |
| Terminal, iTerm2, Warp, Ghostty, WezTerm, kitty | 앱을 앞으로 |

## 문제 해결

- 받은 요청 기록: `tail -f ~/.termpet/events.log`
- 앱 상태 확인: `curl http://127.0.0.1:47821/health`
- 메뉴의 **알림 테스트**로 말풍선 표시 확인

## 개발

```bash
Scripts/run.sh             # 빌드 + 실행
Scripts/install.sh         # /Applications 에 설치
Scripts/release.sh <버전>   # GitHub Release + Homebrew 갱신
```

Swift · SwiftUI + AppKit · [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 라이선스

MIT
