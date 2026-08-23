import Foundation

struct SonosPlayer: Identifiable, Equatable, Sendable {
    let id: String
    var groupID: String?
    var roomName: String
    var deviceName: String
    var playbackSource: String?
    var volume: Int
    var muted: Bool
    var enhanceDialog: Bool
    var nightMode: Bool
    var supportsEnhanceDialog: Bool
    var supportsNightMode: Bool

    static let mockArc = SonosPlayer(
        id: "mock-living-room-arc",
        groupID: "mock-living-room-group",
        roomName: "Living Room",
        deviceName: "Sonos Arc",
        playbackSource: "TV",
        volume: 35,
        muted: false,
        enhanceDialog: true,
        nightMode: false,
        supportsEnhanceDialog: true,
        supportsNightMode: true
    )
}
