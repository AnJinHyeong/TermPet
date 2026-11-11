---
name: make-character
description: 텀펫(TermPet) 친구 캐릭터 팩 만들기 — 캐릭터 이름·LINE 스티커 팩·사용자가 준 그림에서 원본 그림을 모아(크롤링) 포즈를 고르고, 배경·글씨를 지우고 크기를 맞춰 움직이는 스프라이트 팩(character.json + PNG)을 만들어 Friends 폴더에 설치한다. "캐릭터 만들어줘", "친구 추가해줘", "○○로 펫 만들어줘", "이 그림으로 캐릭터", "LINE 스티커로 캐릭터" 같은 요청에 사용.
---

# 텀펫 친구 캐릭터 만들기

원본 그림을 **잘라서** 쓴다. 코드로 다시 그리지 않는다 (직접 그린 캐릭터는 사용자가 "완전 이상하다"고 거절했음).
결과물은 개인용이라 **그림은 절대 저장소에 넣지 않는다** (GitHub 저장소가 공개). 작업은 scratchpad, 설치는 Friends 폴더.

스크립트: `.claude/skills/make-character/scripts/` (Pillow 필요, `python3` 그대로 실행 — `-I` 붙이면 사용자 site-packages 의 PIL 을 못 찾음)

| 스크립트 | 하는 일 |
|---|---|
| `fetch_line.py PKG OUT` | LINE 스티커 팩을 공개 CDN 에서 받기 (`<pkg>_<id>.png`, 움직이는 팩은 APNG) |
| `sheet.py sources OUT.png DIR...` | 후보 그림 격자 + 파일 이름 → Read 로 보고 포즈 고르기 |
| `build_pack.py recipe.json OUT` | 레시피대로 팩 만들기 (배경·조각 지우기, 크기 통일, 8프레임 움직임) |
| `sheet.py pack OUT.png PACKDIR` | 만든 팩을 상태별로, **어두운 배경**에서 확인 |

## 1. 무엇을 만들지 정하기

- 캐릭터 이름과 그림 출처를 확인한다. 출처가 정해져 있지 않으면 순서대로 찾는다:
  1. 사용자가 준 그림이나 스프라이트 시트 (경로)
  2. LINE 스티커: WebSearch 로 `<캐릭터 이름> LINE スタンプ` 또는 `LINE sticker <name>` 을 찾아 `store.line.me/stickershop/product/<숫자>` 의 숫자(팩 ID)를 얻는다. 여러 팩을 받으면 포즈 선택지가 넓어진다.
  3. 공식 사이트 이미지 (캐릭터 소개 페이지의 일러스트)
- **막혔던 것 (다시 시도하지 말 것):** zip 통째 다운로드, fandom 위키(Cloudflare). 권한 검사에 막히면 우회하지 말고 사용자에게 그림 파일을 달라고 한다.
- 이미 있는 친구와 id 가 겹치지 않는지 확인: `ls ~/Library/Application\ Support/TermPet/Friends/`

## 2. 원본 모으기 · 포즈 고르기

```bash
W=<scratchpad>/char-<id>            # 작업 폴더 (저장소 밖)
S=.claude/skills/make-character/scripts
python3 $S/fetch_line.py <팩ID> $W/src
python3 $S/sheet.py sources $W/sources.png $W/src
```
`sources.png` 를 Read 로 보고 상태마다 포즈를 고른다. 같은 상태에 여러 포즈를 주면(`happy.2`) 들어갈 때마다 하나를 고른다.

| 상태 | 언제 | 고를 그림 |
|---|---|---|
| `idle` (필수) | 가만히 (대부분의 시간) | **몸 전체**가 보이는 서 있는 그림. 썸네일로도 쓰임 |
| `walk` | 걷기 | 몸 전체, 옆을 보거나 걷는 그림. 오른쪽을 보면 `"facing": "right"` |
| `talk` | 말풍선 띄울 때 | 말하거나 손 흔드는 그림 |
| `happy` | 작업 성공 | 기뻐하는 그림 (움직이는 APNG 좋음) |
| `angry` | 에러 | 화나거나 우는 그림 |
| `ask` | 권한 요청 | 묻거나 부르는 그림 |
| `sleep` | 오래 조용할 때 | 자는 그림 |
| `dragged` | 마우스로 잡았을 때 | 매달리거나 놀란 그림 |
| `fall` | 떨어질 때 | 넘어지거나 날아가는 그림 |
| `climb` | 창 벽 오르기 | 매달리거나 엿보는 그림. 없으면 idle 그림에 `"motion": "lean"` |

피할 것: 몸이 스티커 가장자리에서 잘린 그림(빌더가 ⚠ 경고), 글씨가 몸에 붙은 그림, 다른 캐릭터와 겹친 그림.

## 3. 레시피 쓰고 만들기

`$W/recipe.json`:
```json
{
  "id": "nameko", "name": "나메코", "order": 8, "walkSpeed": 40, "facing": "front", "area": 9800,
  "messages": {
    "done": ["다 했어~", "끝! 칭찬해 줘", "완료다 완료"],
    "error": ["으앙… 에러야", "빨간 줄 떴어…"],
    "ask": ["이거 봐 줄래?", "허락이 필요해~"]
  },
  "states": {
    "idle":  {"src": "src/1263048_10665715.png", "crop": [60, 0, 310, 320]},
    "walk":  {"src": "src/1263048_10665717.png", "islands": "largest", "facing": "right"},
    "happy": {"src": "src/32367501_123.png"},
    "angry": {"src": "src/1263048_10665704.png", "islands": "largest"}
  }
}
```
- `order`: 패널 순서. 지금 친구들의 최댓값 + 1 (`grep -h '"order"' Friends/*/character.json`)
- `area`: 크기 통일 기준 (불투명 면적, 220 프레임 기준). 참고값은 우사기 8400, 치이카와 9800, 하치와레 10500, 모몽가 10600. 다른 친구들과 나란히 봤을 때 비슷해 보이게 정한다.
- `messages`: 캐릭터 말투의 한국어 (done 3개, error·ask 2개씩)
- 상태별 옵션:
  - `crop [x,y,w,h]`, `erase [[x,y,w,h]...]`: 글씨·소품 지우기
  - `islands`: `"largest"`(제일 큰 덩어리만 남겨서 글씨·효과선 제거) 또는 면적 숫자. 몸에서 떨어진 소품(컵·부채)이 있으면 `"largest"` 쓰지 말 것
  - `flip`, `size`(면적 배율, 소품 때문에 작아 보이면 1.1~1.3), `motion`, `fps`
  - `bg`: `"auto"` / `"white"` / `"keep"`, `tolerance`: 배경 색 허용치
- `motion` 종류: still / breathe / sleepy / hop / hopfwd / sway / shake / wobble / float / lean. 생략하면 상태에 맞는 기본값이고, 움직이는 원본(APNG·GIF)은 원래 프레임을 그대로 쓴다.

```bash
python3 $S/build_pack.py $W/recipe.json $W/out
python3 $S/sheet.py pack $W/pack.png $W/out/<id>
```
`pack.png` 를 Read 로 **반드시** 확인하고, 문제가 없어질 때까지 레시피를 고쳐 다시 만든다:
- 어두운 배경에서 흰 테두리(헤일로)나 배경 찌꺼기가 보이면 → `tolerance` 를 올리거나 `bg: "white"`
- 글씨나 효과 조각이 남아 있으면 → `islands: "largest"` 또는 `erase`
- 몸이 잘렸으면 → 다른 그림이나 `crop` 조정
- 포즈마다 크기가 들쭉날쭉하면 → `size`

## 4. 설치

```bash
F=~/Library/Application\ Support/TermPet/Friends
ditto "$W/out/<id>" "$F/<id>"
```
- 같은 id 폴더가 이미 있으면 덮어쓰기 전에 사용자에게 묻는다.
- 앱은 메뉴바 패널을 열 때 친구 목록을 다시 읽는다. 사용자에게 "패널을 열고 새 친구를 눌러 보세요"라고 안내한다.
- 사용자에게 `pack.png` 미리보기를 보여 주고 포즈 피드백을 받는다 (예: "idle 은 다른 그림으로").

## 5. 정리 · 공유

- 친구가 너무 많아지면: 메뉴 패널에서 친구 타일을 **우클릭 → 지우기** (휴지통으로 옮겨져서 되살릴 수 있음).
- 다른 PC나 윈도우판에 보내려면 zip 으로 묶는다:
  ```bash
  ditto -c -k --norsrc --noextattr --keepParent "$F/<id>" ~/Desktop/<id>.zip
  ```
  주의: 앱의 "친구 추가하기(zip)"는 **기존 친구를 모두 지우고** zip 안의 친구들로 바꾼다. 하나만 더하려면 받는 쪽 Friends 폴더(윈도우: `%APPDATA%\TermPet\Friends`)에 폴더를 복사한다.
- 어떤 출처의 어떤 스티커를 썼는지 프로젝트 메모리(friend-packs)에 한 줄 남긴다 (나중에 포즈를 다시 고를 때 필요).
