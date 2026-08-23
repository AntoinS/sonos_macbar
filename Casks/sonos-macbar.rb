cask "sonos-macbar" do
  version "0.1.1"
  sha256 :no_check

  url "https://github.com/AntoinS/sonos_macbar/releases/download/v#{version}/Sonos-Macbar-#{version}.zip",
      verified: "github.com/AntoinS/sonos_macbar/"
  name "Sonos Macbar"
  desc "Menu bar app for quick Sonos control"
  homepage "https://github.com/AntoinS/sonos_macbar"

  depends_on macos: ">= :sonoma"

  app "Sonos Macbar.app"

  zap trash: [
    "~/Library/Preferences/de.alania-bonn.sonos-macbar.plist",
  ]
end
