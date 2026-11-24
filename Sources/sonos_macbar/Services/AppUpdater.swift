import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater: NSObject, SPUUserDriver {
    static let shared = AppUpdater()

    enum Status {
        case idle, checking, installing, current
        case downloading(Double?)
        case extracting(Double?)
        case failed(String)
    }

    private(set) var status: Status = .idle
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var received: UInt64 = 0
    @ObservationIgnored private var expected: UInt64 = 0

    var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var isConfigured: Bool {
        guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let decoded = Data(base64Encoded: publicKey) else { return false }
        return decoded.count == 32 && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        if updater == nil {
            let engine = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
            do {
                try engine.start()
                updater = engine
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        }
        guard let updater, updater.canCheckForUpdates else { return }
        status = .checking
        updater.checkForUpdates()
    }

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        status = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        if appcastItem.isInformationOnlyUpdate {
            status = .current
            return .dismiss
        }
        status = .downloading(nil)
        return .install
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error) async {
        status = .current
    }

    func showUpdaterError(_ error: any Error) async {
        status = .failed(error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        received = 0
        expected = 0
        status = .downloading(nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expected = expectedContentLength
        updateDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        updateDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        status = .extracting(nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        status = .extracting(progress)
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        status = .installing
        return .install
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        status = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        status = .current
    }

    func dismissUpdateInstallation() {
        switch status {
        case .checking, .downloading, .extracting, .installing:
            status = .idle
        case .idle, .current, .failed:
            break
        }
    }

    private func updateDownloadProgress() {
        status = .downloading(expected == 0 ? nil : min(1, Double(received) / Double(expected)))
    }
}
