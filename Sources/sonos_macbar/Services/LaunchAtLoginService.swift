import Foundation

enum LaunchAtLoginService {
    static var isPrepared: Bool {
        true
    }

    // TODO: Use ServiceManagement to register launch at login after the app has a bundle identifier and signing setup.
    static func setEnabled(_ isEnabled: Bool) async throws {
        _ = isEnabled
    }
}
