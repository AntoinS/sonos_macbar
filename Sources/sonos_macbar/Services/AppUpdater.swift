import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    enum Status {
        case idle, checking, installing, current
        case downloading(Double?)
        case extracting(Double?)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var availableVersion: String?
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

    func start() {
        guard isConfigured, updater == nil else { return }
        let engine = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try engine.start()
            updater = engine
            if engine.automaticallyChecksForUpdates {
                engine.checkForUpdatesInBackground()
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func performUpdateAction() {
        start()
        guard let updater else { return }
        status = .checking

        // An active background check can provide the result without starting a second check.
        guard updater.canCheckForUpdates else { return }
        if availableVersion == nil {
            updater.checkForUpdateInformation()
        } else {
            updater.checkForUpdates()
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.isInformationOnlyUpdate ? nil : item.displayVersionString
        if case .failed = status {
            status = .idle
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        status = .current
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard case .checking = status else { return }
        if let error {
            status = .failed(error.localizedDescription)
        } else {
            status = .idle
        }
    }

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        status = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        guard state.userInitiated, !appcastItem.isInformationOnlyUpdate else { return .dismiss }
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
        availableVersion = nil
        status = .current
    }

    func dismissUpdateInstallation() {
        switch status {
        case .downloading, .extracting, .installing:
            status = .idle
        case .idle, .checking, .current, .failed:
            break
        }
    }

    private func updateDownloadProgress() {
        status = .downloading(expected == 0 ? nil : min(1, Double(received) / Double(expected)))
    }
}
