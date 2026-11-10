# 캐릭터 팩 만들기

## 가장 쉬운 시작: 샘플 팩 복사

메뉴바 🐾 → 캐릭터 → **샘플 스프라이트 팩 만들기**
→ 현재 선택된 기본 캐릭터가 PNG 스프라이트 팩으로 만들어지고 Finder에서 열린다.
PNG를 원하는 그림으로 바꾸고 `character.json`의 `id`/`name`을 고친 뒤
캐릭터 → **목록 새로고침** 하면 목록에 나타난다.

## 폴더 구조

```
~/Library/Application Support/TermPet/Characters/<id>/
  character.json
  idle.png  walk.png  talk.png  happy.png  angry.png  ask.png  sleep.png  dragged.png  fall.png
```

다른 곳에 만든 폴더는 캐릭터 → **캐릭터 팩 가져오기…** 로 선택하면 검증 후 위 위치로 복사된다
(같은 id가 이미 있으면 교체).

## 스프라이트 시트

- 상태별 PNG 1장 = **가로 한 줄**로 프레임을 이어 붙인 이미지
- 프레임 크기는 모두 `frameWidth × frameHeight`
- 투명 배경 권장. 캐릭터의 **발이 프레임 아래쪽 끝**에 닿게 그린다 (펫 창 바닥 = 화면 바닥)
- 기본은 **오른쪽을 보는** 그림. 왼쪽으로 걸을 때는 앱이 자동으로 좌우 반전한다
  (왼쪽을 보게 그렸다면 `"facing": "left"`)

## character.json

```json
{
  "id": "my-cat",
  "name": "냥이",
  "frameWidth": 64,
  "frameHeight": 64,
  "scale": 2,
  "walkSpeed": 40,
  "pixelArt": true,
  "facing": "right",
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

| 필드 | 필수 | 설명 |
|---|---|---|
| `id` | ✅ | 영문/숫자/`-`/`_`, 1~64자. 폴더 이름으로도 쓰인다 |
| `name` | | 메뉴에 보일 이름 (없으면 id) |
| `frameWidth`, `frameHeight` | ✅ | 프레임 한 칸 크기(px), 1~1024 |
| `scale` | | 화면 표시 배율 (기본 1, 0.1~8). 표시 크기 = 프레임 × scale (최대 512pt) |
| `walkSpeed` | | 걷기 속도 pt/초 (기본 40) |
| `pixelArt` | | `true`면 확대할 때 보간 없이(도트 유지) |
| `facing` | | 그림이 보는 방향 `right`(기본) / `left` |
| `states` | ✅ | 상태별 애니메이션. **`idle`은 필수**, 나머지는 없으면 idle로 대체 |
| `states.*.file` | ✅ | 팩 폴더 안의 PNG 파일명 |
| `states.*.frames` | | 프레임 수 (생략하면 이미지 너비 ÷ frameWidth) |
| `states.*.fps` | | 초당 프레임 (기본 8) |
| `states.*.loop` | | 반복 여부 (기본 true, false면 마지막 프레임에서 멈춤) |
| `messages` | | 말풍선 기본 문구. 비어 있으면 앱 기본 문구 |
| `order` | | 캐릭터 목록 순서 (작을수록 앞, 친구 팩용) |
| `states.*.facing` | | 이 동작 그림만 방향이 다를 때 (`right`/`left`/`front`) |

상태 이름: `idle` `walk` `talk` `happy`(작업 완료) `angry`(에러) `ask`(확인 요청) `sleep` `dragged`(잡힘) `fall`(떨어짐·점프·던져짐) `climb`(창/화면 벽 오르기)

- **포즈 여러 개**: `idle.2`, `walk.2`, `happy.3` …처럼 번호를 붙이면 그 동작에 들어갈 때마다 하나를 골라 보여준다.
  `walk.2`가 있으면 그 포즈가 뽑혔을 때 더 빨리 달린다.
- **대체 규칙**: 없는 동작은 `idle`로, `climb`가 없으면 `dragged` → `idle` 순으로 대신한다.
- `sleep`일 때는 앱이 머리 위에 z z z 를 그려 준다.

## 친구 팩 (여러 개)

`~/Library/Application Support/TermPet/Friends/<id>/` 에 팩 폴더를 두면 캐릭터 목록 맨 앞에 나오고,
선택 기록이 없으면 첫 친구(`order`가 가장 작은)가 기본 캐릭터가 된다.
저작권 그림으로 만든 팩은 이 폴더에만 두고 저장소에는 넣지 않는다.

읽지 못한 팩은 캐릭터 메뉴 아래 "읽지 못한 팩"에 이유와 함께 표시된다.
