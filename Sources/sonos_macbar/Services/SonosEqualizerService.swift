import Foundation
import UPnPCast

enum EqualizerControl: CaseIterable, Sendable {
    case bass, treble, loudness, subLevel

    var range: ClosedRange<Int> {
        switch self {
        case .bass, .treble: -10...10
        case .loudness: 0...1
        case .subLevel: -15...15
        }
    }

    func clamped(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    var readAction: String {
        switch self {
        case .bass: "GetBass"
        case .treble: "GetTreble"
        case .loudness: "GetLoudness"
        case .subLevel: "GetEQ"
        }
    }

    var readArguments: [(String, String)] {
        [("InstanceID", "0"), self == .subLevel ? ("EQType", "SubGain") : ("Channel", "Master")]
    }

    func readValue(_ response: [String: String]) throws -> Int {
        let key = switch self {
        case .bass: "CurrentBass"
        case .treble: "CurrentTreble"
        case .loudness: "CurrentLoudness"
        case .subLevel: "CurrentValue"
        }
        let raw = response[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .loudness {
            if raw?.lowercased() == "true" { return 1 }
            if raw?.lowercased() == "false" { return 0 }
        }
        guard let raw, let value = Int(raw), range.contains(value) else {
            throw SonosAPIError.invalidResponse
        }
        return value
    }

    func writeCommand(_ value: Int) -> (action: String, arguments: [(String, String)]) {
        let value = String(clamped(value))
        let instance = [("InstanceID", "0")]
        switch self {
        case .bass:
            return ("SetBass", instance + [("DesiredBass", value)])
        case .treble:
            return ("SetTreble", instance + [("DesiredTreble", value)])
        case .loudness:
            return ("SetLoudness", instance + [("Channel", "Master"), ("DesiredLoudness", value)])
        case .subLevel:
            return ("SetEQ", instance + [("EQType", "SubGain"), ("DesiredValue", value)])
        }
    }
}

struct EqualizerConnection: Sendable {
    let values: [EqualizerControl: Int]
    let write: @Sendable (EqualizerControl, Int) async throws -> Void
}

enum SonosEqualizerService {
    static func connect(to playerID: SonosPlayer.ID) async throws -> EqualizerConnection {
        let session = SonosLocalDiscovery.localSession()
        let device = try await SonosLocalDiscovery.findDevice(for: playerID, session: session)
        guard let rendering = SonosLocalDiscovery.service(ofType: UPnPServiceType.renderingControl, on: device) else {
            throw SonosAPIError.playerNotFound
        }

        let client = SOAPClient(session: session, timeout: 4)
        async let bass = read(.bass, client: client, service: rendering)
        async let treble = read(.treble, client: client, service: rendering)
        async let loudness = read(.loudness, client: client, service: rendering)
        async let subLevel = readSubLevel(for: playerID, device: device, client: client, rendering: rendering)

        var values: [EqualizerControl: Int] = try await [.bass: bass, .treble: treble, .loudness: loudness]
        values[.subLevel] = await subLevel
        try Task.checkCancellation()

        return EqualizerConnection(values: values) { control, value in
            let command = control.writeCommand(value)
            _ = try await client.invoke(command.action, on: rendering, orderedArguments: command.arguments)
        }
    }

    private static func read(
        _ control: EqualizerControl, client: SOAPClient, service: UPnPService
    ) async throws -> Int {
        let response = try await client.invoke(control.readAction, on: service, orderedArguments: control.readArguments)
        return try control.readValue(response)
    }

    private static func readSubLevel(
        for playerID: SonosPlayer.ID, device: UPnPDevice, client: SOAPClient, rendering: UPnPService
    ) async -> Int? {
        guard let topology = SonosLocalDiscovery.service(ofType: SonosLocalDiscovery.topologyService, on: device),
              let response = try? await client.invoke("GetZoneGroupState", on: topology),
              let xml = response["ZoneGroupState"],
              hasBondedSub(in: xml, for: playerID) else { return nil }

        return try? await read(.subLevel, client: client, service: rendering)
    }

    static func hasBondedSub(in xml: String, for playerID: SonosPlayer.ID) -> Bool {
        guard let document = try? XMLDocument(xmlString: xml, options: .nodeLoadExternalEntitiesNever),
              let members = try? document.nodes(forXPath: "//ZoneGroupMember") else { return false }
        return members.compactMap { $0 as? XMLElement }.contains { member in
            guard member.attribute(forName: "UUID")?.stringValue == playerID else { return false }
            return ["HTSatChanMapSet", "ChannelMapSet"].contains { attribute in
                let channelMap = member.attribute(forName: attribute)?.stringValue ?? ""
                return channelMap.split(separator: ";").contains { entry in
                    entry.split(separator: ":", maxSplits: 1).last?
                        .split(separator: ",").contains("SW") == true
                }
            }
        }
    }

}
