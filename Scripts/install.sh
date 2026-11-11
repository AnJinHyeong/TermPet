#!/bin/bash
# 텀펫을 Release로 빌드해서 /Applications 에 설치하고 실행한다. (업데이트도 같은 명령)
#   Scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen 필요: brew install xcodegen"; exit 1; }
[[ -d TermPet.xcodeproj ]] || xcodegen generate

echo "▶ Release 빌드 중..."
xcodebuild -project TermPet.xcodeproj -scheme TermPet -configuration Release \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build -quiet build

APP=build/Build/Products/Release/TermPet.app
DEST=/Applications/TermPet.app

# 화면 있는 텀펫만 종료 (Claude 앱이 띄운 `TermPet --mcp` 는 그대로)
pkill -xf '.*/TermPet\.app/Contents/MacOS/TermPet' 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
echo "▶ 설치 완료: $DEST (Finder에는 '텀펫'으로 보여요)"
echo "  로그인 시 자동 실행: 시스템 설정 → 일반 → 로그인 항목 → + → 텀펫"
