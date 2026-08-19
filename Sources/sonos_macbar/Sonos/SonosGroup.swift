import Foundation

struct SonosGroup: Identifiable, Equatable, Sendable {
    let id: String
    var roomName: String
    var playerIDs: [SonosPlayer.ID]
}
