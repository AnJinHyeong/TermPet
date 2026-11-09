# Homebrew cask (이 저장소 자체가 tap)
#   brew tap anjinhyeong/termpet https://github.com/AnJinHyeong/TermPet
#   brew install --cask termpet
# version / sha256 은 Scripts/release.sh 가 자동으로 갱신한다.
cask "termpet" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/AnJinHyeong/TermPet/releases/download/v#{version}/TermPet-#{version}.zip"
  name "텀펫"
  name "TermPet"
  desc "Menu bar desktop pet that tells you when Claude Code or long terminal commands finish"
  homepage "https://github.com/AnJinHyeong/TermPet"

  depends_on macos: ">= :sonoma"

  app "TermPet.app"

  # 개인용 ad-hoc 서명 앱이라 Apple 공증이 없다 → 다운로드 격리 표시를 지워야 "손상됨" 경고 없이 열린다
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/TermPet.app"]
  end

  uninstall quit: "com.termpet.TermPet"

  zap trash: [
    "~/.termpet",
    "~/Library/Application Support/TermPet",
    "~/Library/Preferences/com.termpet.TermPet.plist",
  ]
end
