# TermPet 연동 설정 (수동)

> 메뉴바 아이콘 → **AI 연결**의 [연결] 버튼으로 자동 설정할 수 있다 (백업 후 병합). 아래는 직접 설정하는 방법.

TermPet 앱을 한 번 실행하면 다음이 자동 생성된다:

| 경로 | 내용 |
|---|---|
| `~/.termpet/token` | 인증 토큰 (권한 600) |
| `~/.termpet/port` | 서버 포트 (기본 47821) |
| `~/.termpet/bin/termpet-hook` | 훅 스크립트 (앱 실행 시마다 최신본으로 갱신) |
| `~/.termpet/zsh-integration.zsh` | zsh 연동 스니펫 |

동작 확인:
```bash
curl http://127.0.0.1:47821/health      # → ok
```

---

## 1. Claude Code

`~/.claude/settings.json`의 `"hooks"`에 아래 `Stop`, `Notification` 항목을 **추가**한다.
(기존 내용을 지우지 말고 합칠 것. 이미 `"hooks"`가 있으면 그 안에 두 키만 넣는다. 같은 이벤트 키가 이미 있으면 배열에 객체를 하나 더 추가.)

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.termpet/bin/termpet-hook claude", "timeout": 5 }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.termpet/bin/termpet-hook claude", "timeout": 5 }
        ]
      }
    ]
  }
}
```

- `Stop`: Claude가 응답을 마칠 때 → 캐릭터 신남 + "끝났어!" (보조 설명: 마지막 답변 첫 줄)
- `Notification`: 권한 요청 / 입력 대기 → 캐릭터 손 흔들기 + 메시지
- 설정 파일 변경은 Claude Code가 자동 감지한다. `/hooks` 명령으로 등록 상태를 볼 수 있다.
- 훅 스크립트는 항상 즉시 `exit 0` 하고 아무것도 출력하지 않으므로 Claude 동작에 영향을 주지 않는다.

제거: 위에서 추가한 두 객체를 지우면 된다.

## 2. zsh (오래 걸린 명령 알림)

`~/.zshrc` 맨 아래에 한 줄 추가:

```zsh
[[ -f ~/.termpet/zsh-integration.zsh ]] && source ~/.termpet/zsh-integration.zsh
```

새 터미널을 열면 적용된다.
- 30초 이상 걸린 명령이 끝나면 알림: 종료 코드 0 → 신남, 그 외 → 화남. Ctrl+C로 중단한 건 알리지 않는다.
- `claude`, `vim`, `ssh`, `less`, `top` 같은 대화형 명령은 제외.
- 조정 (source 줄 **위**에 작성):
  ```zsh
  TERMPET_MIN_SECONDS=10          # 기준 시간 변경
  TERMPET_IGNORE=(mycmd)          # 제외 명령 추가 (기본 목록에 더해짐)
  ```

제거: 추가한 한 줄을 지운다.

## 3. Codex

`~/.codex/config.toml` 맨 위(첫 `[테이블]` 앞)에:

```toml
notify = ["/Users/<나>/.termpet/bin/termpet-hook", "codex"]
```

이미 다른 `notify`가 있으면 Codex는 하나만 받으므로 연결(chain) 형태로 바꾼다. 원래 명령은 그대로 먼저 실행된다.

```toml
notify = ["/Users/<나>/.termpet/bin/termpet-hook", "codex-chain", "<원래 명령>", "<원래 인자>"]
```

## 4. 직접 테스트

```bash
TOKEN=$(cat ~/.termpet/token)

# 표준 이벤트
curl -X POST http://127.0.0.1:47821/event -H "X-TermPet-Token: $TOKEN" \
  -d '{"source":"shell","kind":"done","message":"테스트 알림!","cwd":"'"$PWD"'"}'

# Claude Code 훅 흉내 (훅 스크립트 경유 — 현재 터미널 앱 정보가 같이 전송됨)
echo '{"hook_event_name":"Stop","cwd":"'"$PWD"'","session_id":"test","last_assistant_message":"테스트 완료"}' \
  | ~/.termpet/bin/termpet-hook claude

# 긴 명령 흉내 (exitCode 1, 95초)
~/.termpet/bin/termpet-hook shell 1 95 "$PWD" "npm run build"
```

## 알림이 안 올 때

1. 받은 요청 기록 확인: `tail -f ~/.termpet/events.log`
   - 아무 줄도 안 생기면 → 훅이 실행되지 않음 (Claude Code에서 `/hooks`로 등록 확인, 새 세션에서 다시 시도)
   - `401` → 토큰 불일치 (앱 재실행), `202` → 정상 수신 (화면 표시 문제)
2. 표시 위치가 **"바탕화면에만 표시"**면 캐릭터와 말풍선이 앱 창 뒤에 있어 알림이 가려진다.
   알림을 보고 싶으면 **"바탕화면에만 + 알림 시 앞으로"**를 선택 — 말풍선이 떠 있는 동안만 앞으로 올라왔다가
   (기본 3초, 또는 말풍선 클릭/닫기 시) 다시 바탕화면 층으로 내려간다.
3. 앱 실행 확인: `curl http://127.0.0.1:47821/health` → `ok`

## 엔드포인트 요약

| 메서드 | 경로 | 인증 | 설명 |
|---|---|---|---|
| GET | `/health` | 없음 | 200 `ok` |
| POST | `/event` | `X-TermPet-Token` | 표준 이벤트 JSON (SPEC 3-5) |
| POST | `/hook/claude` | `X-TermPet-Token` | Claude Code 훅 stdin 원본 |
| POST | `/hook/codex` | `X-TermPet-Token` | Codex notify 원본 (Phase 5에서 보강) |

추가 헤더(선택): `X-TermPet-Host-Bundle`(=`$__CFBundleIdentifier`), `X-TermPet-Term-Program`(=`$TERM_PROGRAM`).
`Origin` 헤더가 붙은 요청(브라우저)은 403으로 거부한다.
