import Foundation

struct SonosAuthConfiguration: Sendable {
    let baseURL: URL
    let developmentAccessTokenEnvironmentKey: String
    let callbackURLScheme: String

    static let production = SonosAuthConfiguration(
        baseURL: URL(string: "https://sonos-auth.alania-bonn.de")!,
        developmentAccessTokenEnvironmentKey: "SONOS_ACCESS_TOKEN",
        callbackURLScheme: "sonos-macbar"
    )
}
