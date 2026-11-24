cask "sonos-macbar" do
  version "0.2.3"
  sha256 "f2c01be9fbe89910bece79fe5706abd7c0f4933b22da91a71bbd906de9e1574a"

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
