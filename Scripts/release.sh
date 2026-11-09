#!/bin/bash
# 새 버전 배포: Release 빌드 → zip → GitHub Release 업로드 → Homebrew tap(homebrew-tap 저장소)의 cask 갱신
#   Scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: Scripts/release.sh <version>  (예: 0.2.0)}"

sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
xcodegen generate >/dev/null

echo "▶ Release 빌드 중..."
xcodebuild -project TermPet.xcodeproj -scheme TermPet -configuration Release \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build -quiet build

ZIP="build/TermPet-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Build/Products/Release/TermPet.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

git add project.yml
git commit -m "release: v$VERSION" || true
git push
gh release create "v$VERSION" "$ZIP" --title "텀펫 v$VERSION" --notes "brew upgrade --cask termpet 로 업데이트"

# Homebrew tap 저장소의 cask 버전·체크섬 갱신 (설치 명령: brew install --cask anjinhyeong/tap/termpet)
TAP=build/homebrew-tap
[[ -d "$TAP/.git" ]] || gh repo clone AnJinHyeong/homebrew-tap "$TAP"
git -C "$TAP" pull -q
sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/termpet.rb"
git -C "$TAP" commit -am "termpet $VERSION"
git -C "$TAP" push -q
echo "▶ 배포 완료: v$VERSION (sha256 $SHA)"
