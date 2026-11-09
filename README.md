<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="텀펫 아이콘">
</p>

<h1 align="center">텀펫 (TermPet)</h1>

<p align="center">
  Claude Code 작업이나 오래 걸리는 터미널 명령이 끝나면<br>
  화면 위 작은 펫이 말풍선으로 알려주는 macOS 메뉴바 앱
</p>

---

## 이런 앱이에요

- 화면 아래를 돌아다니는 데스크톱 펫. 걷고, 졸고, 잡아서 던지면 떨어집니다.
- **Claude Code**가 답변을 끝내거나 권한을 물어보면 → 펫이 신나서 "끝났어!" 말풍선
- **30초 이상 걸린 터미널 명령**(`npm run build` 등)이 끝나면 → 성공은 신남, 실패는 화남
- 말풍선을 누르면 **그 작업을 하던 Cursor / VSCode 프로젝트 창으로 바로 이동**
- 놓친 알림은 펫 머리 위 `!`로 남아 있고, 펫을 누르면 다시 보여줍니다
- 기본 캐릭터 4종(말랑이·냥이·토끼·새싹이) + **그림 한 장으로 내 캐릭터 만들기**

## 설치

### Homebrew (추천)

```bash
brew tap anjinhyeong/termpet https://github.com/AnJinHyeong/TermPet
brew trust anjinhyeong/termpet          # 처음 한 번: 공식 저장소가 아닌 tap 허용
brew install --cask termpet
open /Applications/TermPet.app
```

- 업데이트: `brew upgrade --cask termpet`
- 삭제: `brew uninstall --cask termpet` (설정·캐릭터까지 지우려면 `--zap`)

> 개인용 앱이라 Apple 공증을 받지 않았습니다. 설치 과정에서 격리 표시를 지워서 바로 열리게 해 둡니다.

### 소스에서 직접

```bash
brew install xcodegen
git clone https://github.com/AnJinHyeong/TermPet.git && cd TermPet
Scripts/install.sh        # Release 빌드 → /Applications/TermPet.app 설치·실행 (업데이트도 같은 명령)
```

필요: macOS 14 (Sonoma) 이상, Xcode.

설치 후 Finder·Spotlight에서는 **텀펫**으로 보입니다. 로그인할 때 자동 실행하려면
시스템 설정 → 일반 → 로그인 항목 → `+` → 텀펫.

## 알림 연결하기

앱을 한 번 실행하면 `~/.termpet/` 아래에 훅 스크립트와 토큰이 자동으로 생깁니다. 그다음 두 가지를 연결합니다.

### 1. Claude Code

`~/.claude/settings.json`의 `"hooks"`에 아래 두 항목을 **추가**합니다 (기존 내용은 그대로 두고 합치기).

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "$HOME/.termpet/bin/termpet-hook claude", "timeout": 5 }] }
    ],
    "Notification": [
      { "hooks": [{ "type": "command", "command": "$HOME/.termpet/bin/termpet-hook claude", "timeout": 5 }] }
    ]
  }
}
```

- `Stop` → 답변이 끝났을 때 (말풍선에 마지막 답변 첫 줄이 같이 나옴)
- `Notification` → 권한 요청 / 입력 기다림
- Claude Code가 설정 변경을 자동으로 읽습니다. `/hooks`로 등록 상태를 볼 수 있어요.

### 2. zsh (오래 걸린 명령 알림)

`~/.zshrc` 맨 아래에 한 줄:

```zsh
[[ -f ~/.termpet/zsh-integration.zsh ]] && source ~/.termpet/zsh-integration.zsh
```

- 기준 시간 바꾸기: source 줄 **위**에 `TERMPET_MIN_SECONDS=10`
- 알림 제외 명령 추가: `TERMPET_IGNORE+=(mycmd)` (`claude`, `vim`, `ssh`, `less`, `top` 등은 기본 제외)
- `Ctrl+C`로 멈춘 명령은 알리지 않습니다.

자세한 설명·직접 테스트 방법은 [docs/SETUP.md](docs/SETUP.md).

## 어떤 터미널에서 되나요?

알림은 **터미널 종류와 상관없이** 옵니다. Claude Code 훅과 zsh 연동은 터미널이 아니라 Claude Code / zsh 자체에서 실행되기 때문입니다.
차이는 **말풍선을 눌렀을 때 어디로 이동하느냐**뿐입니다.

| 어디서 실행했나 | 알림 | 말풍선 클릭 시 |
|---|---|---|
| Cursor 통합 터미널 | ✅ | 해당 **프로젝트 창**으로 이동 |
| VSCode / VSCode Insiders 통합 터미널 | ✅ | 해당 **프로젝트 창**으로 이동 |
| Windsurf, Zed | ✅ | 해당 프로젝트 창으로 이동 |
| macOS 기본 터미널, iTerm2, Warp, Ghostty, WezTerm, kitty | ✅ | 그 **터미널 앱을 앞으로** (특정 탭 선택은 안 됨) |
| 그 밖의 앱 | ✅ | 이동 없음 (말풍선만 닫힘) |

확인한 방법: 기본 터미널에서 실제로 훅을 실행했고, iTerm2·VSCode·Warp는 각 앱이 설정하는 환경값으로 훅을 보내 모두 수신되는 것을 `~/.termpet/events.log`로 확인했습니다.

## 사용법

메뉴바의 말랑이 아이콘을 누르면 패널이 열립니다.

- **맨 위 스위치**: 펫 보이기 / 숨기기. 초록 점 = 알림 받는 중
- **캐릭터**: 눌러서 바꾸기. 선택된 캐릭터는 주황 테두리와 ✓
- **이미지로 캐릭터 만들기**: 그림을 고르면 배경을 지우고 걷기·점프·잠자기 같은 움직임을 입혀 줍니다
  - 내 캐릭터는 **하나만** 보관합니다. 새로 만들면 이전 것은 휴지통으로 (되살릴 수 있음)
  - 뒤로 걷는 것처럼 보이면 **방향 바꾸기**
  - 흰 배경 그림, 투명 PNG, 게임 도트 이미지처럼 배경이 단순할수록 잘 됩니다
- **표시 위치**
  - 항상 위: 모든 창 위에 보임
  - 바탕화면: 창이 없는 바탕화면에서만 보임 (알림도 창 뒤에 가려짐)
  - 알림 때만 위: 평소엔 바탕화면에, 알림이 오면 3초 동안 앞으로 나왔다가 다시 숨음
- **놀기**: 재우기 · 위에서 떨어뜨리기 · 알림 테스트

펫에게 직접:
- 클릭 → 놓친 알림 다시 보기 (없으면 기뻐함)
- 드래그 → 들고 다니기, 놓으면 떨어짐
- 오른쪽 클릭 → 메뉴

## 계속 켜 둬도 괜찮나요?

하루 종일 켜 두는 앱이라 이 부분을 따로 확인했습니다.

| 항목 | 결과 |
|---|---|
| CPU | 가만히 있을 때 약 2~5% (걷거나 떨어질 때만 60fps, 평소 20fps, 잘 때 10fps) |
| 메모리 | 약 70MB에서 늘지 않음 |
| 앱이 꺼져 있을 때 | 훅은 약 0.04초 만에 조용히 끝나고 항상 성공(종료 코드 0)으로 끝남 → Claude Code·쉘이 느려지거나 에러 나지 않음 |
| 로그 파일 | `~/.termpet/events.log`는 256KB가 넘으면 자동으로 정리 |
| 쌓이는 알림 | 최대 20개까지만 보관, 같은 세션 알림은 새것으로 교체 |
| 보안 | `127.0.0.1`(내 컴퓨터)에서만 받고, 토큰(`~/.termpet/token`, 권한 600)이 맞아야 처리. 브라우저에서 온 요청은 거부 |

## 알림이 안 올 때

1. `tail -f ~/.termpet/events.log` 를 켜 두고 다시 시도
   - 아무 줄도 안 생김 → 훅이 실행되지 않음 (Claude Code에서 `/hooks` 확인, 새 세션에서 재시도)
   - `401` → 토큰 불일치 → 텀펫 다시 실행
   - `202` → 정상 수신. 화면 표시 문제 → 표시 위치가 "바탕화면"이면 창 뒤에 가려짐
2. 앱 실행 확인: `curl http://127.0.0.1:47821/health` → `ok`
3. 패널의 **알림 테스트**로 말풍선이 뜨는지 확인

## 삭제

1. `~/.claude/settings.json`에서 추가한 `termpet-hook` 항목 2개 제거
2. `~/.zshrc`에서 `zsh-integration.zsh` 줄 제거
3. `brew uninstall --cask --zap termpet` (또는 `/Applications/TermPet.app`, `~/.termpet`, `~/Library/Application Support/TermPet` 삭제)

> 1·2를 먼저 하지 않으면 훅이 없는 파일을 부르게 됩니다. 에러로 멈추지는 않지만 정리해 두는 게 깔끔합니다.

## 개발

```bash
Scripts/run.sh            # 디버그 빌드 + 실행 (--logs: 로그 보기, --gen: 프로젝트 재생성)
xcodebuild -project TermPet.xcodeproj -scheme TermPet test   # 단위 테스트
swift Scripts/make-icons.swift                               # 앱·메뉴바 아이콘 다시 그리기
Scripts/release.sh 0.2.0  # 새 버전 배포: 빌드 → GitHub Release → Homebrew cask 갱신
```

- Swift 5 · SwiftUI + AppKit · macOS 14+. 프로젝트 파일은 [XcodeGen](https://github.com/yonaskolb/XcodeGen)의 `project.yml`에서 생성합니다 (`.xcodeproj`는 커밋하지 않음).
- 구조

  | 폴더 | 내용 |
  |---|---|
  | `Sources/App` | 앱 시작, 메뉴바 패널, 명령줄 모드 |
  | `Sources/Pet` | 펫 창, 상태 머신(PetBrain), 물리(걷기·낙하), 멀티 모니터 |
  | `Sources/Bubble` | 말풍선 창, 알림 큐, 위치 계산 |
  | `Sources/Events` | Claude Code 훅·Codex·쉘 이벤트 해석 |
  | `Sources/Server` | 로컬 HTTP 서버(토큰 인증), 요청 로그 |
  | `Sources/Integrations` | 말풍선 클릭 → 에디터/터미널 창 이동 |
  | `Sources/Character` | 기본 캐릭터, 스프라이트 팩, 이미지 → 캐릭터 변환(배경 제거) |
  | `Scripts` | 훅 스크립트, zsh 연동, 실행·설치·배포 스크립트 |
  | `Tests` | XCTest 단위 테스트 |

- 명령줄로 캐릭터 만들기:
  ```bash
  /Applications/TermPet.app/Contents/MacOS/TermPet --make-character 그림.png --name 이름 --facing left
  /Applications/TermPet.app/Contents/MacOS/TermPet --state-image 다른그림.png --states dragged,fall
  ```
- 캐릭터 팩 형식: [docs/CHARACTER_PACK.md](docs/CHARACTER_PACK.md) · 전체 명세: [SPEC.md](SPEC.md)

## 참고

- 개인용으로 만든 앱입니다. 다른 사람이 만든 캐릭터 그림(게임 캐릭터 등)으로 내 캐릭터를 만들었다면 개인적으로만 쓰고 배포하지 마세요.
- 이 저장소의 `.claude/skills/ponytail*`은 코드 리뷰용 Claude Code 스킬 [ponytail](https://github.com/DietrichGebert/ponytail) (MIT)입니다.
