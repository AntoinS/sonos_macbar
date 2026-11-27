cask "sonos-macbar" do
  version "0.2.7"
  sha256 "cf50c39636f5ff352eaaa71fba77688eff625d56e5d55370724be6501bddf328"

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
