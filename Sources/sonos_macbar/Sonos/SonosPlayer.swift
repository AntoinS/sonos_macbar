import Foundation

struct SonosPlayer: Identifiable, Equatable, Sendable {
    let id: String
    var roomName: String
    var deviceName: String
    var volume: Int
    var muted: Bool
    var enhanceDialog: Bool
    var nightMode: Bool
    var supportsEnhanceDialog: Bool
    var supportsNightMode: Bool

    static let mockArc = SonosPlayer(
        id: "mock-living-room-arc",
        roomName: "Living Room",
        deviceName: "Sonos Arc",
        volume: 35,
        muted: false,
        enhanceDialog: true,
        nightMode: false,
        supportsEnhanceDialog: true,
        supportsNightMode: true
    )
}
