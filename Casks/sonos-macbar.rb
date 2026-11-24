cask "sonos-macbar" do
  version "0.2.2"
  sha256 "db11e5be13ca2151a864ac6a489c604757f4915b1624b13c64ceac81c3892f6f"

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
