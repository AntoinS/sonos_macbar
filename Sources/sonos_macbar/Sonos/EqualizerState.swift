import Foundation
import Observation

@MainActor
@Observable
final class EqualizerState {
    struct Change: Equatable {
        let control: EqualizerControl
        let value: Int
    }

    enum Status: Equatable {
        case loading, ready, unavailable
    }

    private let playerID: SonosPlayer.ID
    private let connect: @Sendable (SonosPlayer.ID) async throws -> EqualizerConnection
    private var connection: EqualizerConnection?
    private var loadID = UUID()

    private(set) var status: Status = .loading
    private(set) var values: [EqualizerControl: Int] = [:]
    private(set) var isSaving = false
    private(set) var failedChange: Change?

    init(
        playerID: SonosPlayer.ID,
        connect: @escaping @Sendable (SonosPlayer.ID) async throws -> EqualizerConnection = SonosEqualizerService.connect
    ) {
        self.playerID = playerID
        self.connect = connect
    }

    func load() async {
        guard !isSaving else { return }
        let id = UUID()
        loadID = id
        status = .loading
        failedChange = nil
        connection = nil
        values = [:]

        do {
            let connection = try await connect(playerID)
            guard !Task.isCancelled, loadID == id else { return }
            self.connection = connection
            values = connection.values
            status = .ready
        } catch {
            guard !Task.isCancelled, loadID == id else { return }
            status = .unavailable
        }
    }

    func save(_ control: EqualizerControl, value: Int) async {
        let value = control.clamped(value)
        guard let connection, !isSaving, let previous = values[control], previous != value else { return }

        isSaving = true
        failedChange = nil
        defer { isSaving = false }
        do {
            try await connection.write(control, value)
            values[control] = value
        } catch {
            failedChange = Change(control: control, value: value)
        }
    }
}
