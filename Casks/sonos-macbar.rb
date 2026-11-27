cask "sonos-macbar" do
  version "0.2.4"
  sha256 "8305b0f9148fa1fe9b450db9419ab9f4745ed76fce496b67acc81c3640080409"

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
