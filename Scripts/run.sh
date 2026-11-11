#!/usr/bin/env bash
# 개발용 실행 스크립트 (npm run dev 같은 역할)
#   Scripts/run.sh          빌드 → 기존 앱 종료 → 실행 (백그라운드)
#   Scripts/run.sh --logs   빌드 → 기존 앱 종료 → 터미널에 붙여 실행 (print 로그 보임, Ctrl+C 종료)
#   Scripts/run.sh --gen    xcodegen generate 먼저 실행 (파일 추가/삭제 후)
set -euo pipefail

cd "$(dirname "$0")/.."

LOGS=0
GEN=0
for arg in "$@"; do
  case "$arg" in
    --logs) LOGS=1 ;;
    --gen)  GEN=1 ;;
    *) echo "알 수 없는 옵션: $arg" >&2; exit 1 ;;
  esac
done

# 프로젝트 파일이 없거나 --gen이면 생성
if [[ $GEN -eq 1 || ! -d TermPet.xcodeproj ]]; then
  xcodegen generate --quiet
fi

echo "▶ 빌드 중..."
xcodebuild -project TermPet.xcodeproj -scheme TermPet -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build build -quiet

APP="build/Build/Products/Debug/TermPet.app"

# 이미 실행 중이면 종료 (메뉴바 아이콘 중복 방지)
# 화면 있는 텀펫만 종료 (Claude 앱이 띄운 `TermPet --mcp` 는 인자가 붙어 있어서 -xf 에 안 걸린다)
pkill -xf '.*/TermPet\.app/Contents/MacOS/TermPet' 2>/dev/null && sleep 0.5 || true

if [[ $LOGS -eq 1 ]]; then
  echo "▶ 실행 (로그 모드, Ctrl+C로 종료)"
  exec "$APP/Contents/MacOS/TermPet"
else
  open "$APP"
  echo "▶ 실행됨. 종료: 메뉴의 [종료]"
fi
