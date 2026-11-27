cask "sonos-macbar" do
  version "0.2.6"
  sha256 "2172b08dc1cf7d1345f3b46311fb99d27cfdd32c9441331ac66867cd3841250c"

  url "https://github.com/AntoinS/sonos_macbar/releases/download/v#{version}/Sonos-Macbar-#{version}.zip"
  name "Sonos Macbar"
  desc "Menu bar app for quick Sonos control"
  homepage "https://github.com/AntoinS/sonos_macbar"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Sonos Macbar.app"

  zap trash: [
    "~/Library/Preferences/de.alania-bonn.sonos-macbar.plist",
  ]
end
