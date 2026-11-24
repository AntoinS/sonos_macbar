import Foundation
import Network
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
    private static let zonePlayer = "urn:schemas-upnp-org:device:ZonePlayer:1"
    private static let topologyService = "urn:schemas-upnp-org:service:ZoneGroupTopology:1"

    static func connect(to playerID: SonosPlayer.ID) async throws -> EqualizerConnection {
        let session = localSession()
        let device = try await findDevice(for: playerID, session: session)
        guard let rendering = device.service(ofType: UPnPServiceType.renderingControl),
              isLocalEndpoint(rendering.controlURL, host: device.descriptionURL.host) else {
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
        guard let topology = device.service(ofType: topologyService),
              isLocalEndpoint(topology.controlURL, host: device.descriptionURL.host),
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

    private static func findDevice(for playerID: SonosPlayer.ID, session: URLSession) async throws -> UPnPDevice {
        if let location = await bonjourLocation(for: playerID),
           let device = try? await loadDevice(at: location, for: playerID, session: session) {
            return device
        }

        for try await response in SSDP.search(target: zonePlayer) {
            try Task.checkCancellation()
            guard matches(response, playerID: playerID),
                  let device = try? await loadDevice(at: response.location, for: playerID, session: session) else { continue }
            return device
        }
        try Task.checkCancellation()
        throw SonosAPIError.playerNotFound
    }

    private static func loadDevice(at url: URL, for playerID: SonosPlayer.ID, session: URLSession) async throws -> UPnPDevice {
        let device = try await UPnPDevice.load(from: url, session: session)
        guard device.udn.caseInsensitiveCompare("uuid:\(playerID)") == .orderedSame else {
            throw SonosAPIError.playerNotFound
        }
        return device
    }

    private static func bonjourLocation(for playerID: SonosPlayer.ID) async -> URL? {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: "local."), using: .tcp)
        let (locations, continuation) = AsyncStream<URL>.makeStream(bufferingPolicy: .bufferingNewest(1))
        browser.browseResultsChangedHandler = { results, _ in
            for result in results {
                guard case let .bonjour(record) = result.metadata,
                      let location = bonjourLocation(in: record, for: playerID) else { continue }
                continuation.yield(location)
                return
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed = state { continuation.finish() }
        }
        browser.start(queue: .global(qos: .utility))

        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            continuation.finish()
        }
        defer {
            timeout.cancel()
            browser.cancel()
            continuation.finish()
        }
        for await location in locations { return location }
        return nil
    }

    static func bonjourLocation(in record: NWTXTRecord, for playerID: SonosPlayer.ID) -> URL? {
        guard record["uuid"]?.caseInsensitiveCompare(playerID) == .orderedSame,
              let location = record["location"].flatMap(URL.init(string:)),
              let host = location.host,
              IPv4Address(host) != nil,
              isLocalEndpoint(location, host: host),
              location.path == "/xml/device_description.xml" else { return nil }
        return location
    }

    static func matches(_ response: SSDPResponse, playerID: SonosPlayer.ID) -> Bool {
        response.uuid?.caseInsensitiveCompare("uuid:\(playerID)") == .orderedSame
            && isLocalEndpoint(response.location, host: response.sourceAddress)
    }

    private static func isLocalEndpoint(_ url: URL, host: String?) -> Bool {
        url.scheme == "http" && url.port == 1400 && url.host == host
            && url.user == nil && url.password == nil
    }

    private static func localSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 10
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
