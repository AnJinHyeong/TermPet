#!/bin/bash
# 새 버전 배포: Release 빌드 → zip → GitHub Release 업로드 → Casks/termpet.rb 의 version/sha256 갱신 → 커밋·푸시
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

sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/termpet.rb
git add project.yml Casks/termpet.rb
git commit -m "release: v$VERSION"
git push
gh release create "v$VERSION" "$ZIP" --title "텀펫 v$VERSION" --notes "brew upgrade --cask termpet 로 업데이트"
echo "▶ 배포 완료: v$VERSION (sha256 $SHA)"
