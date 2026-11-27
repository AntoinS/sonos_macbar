import Foundation
import Network
import UPnPCast

enum SonosLocalDiscovery {
    private static let zonePlayer = "urn:schemas-upnp-org:device:ZonePlayer:1"
    static let topologyService = "urn:schemas-upnp-org:service:ZoneGroupTopology:1"

    private struct Candidate: Hashable, Sendable {
        let id: String
        let url: URL
    }

    static func discover(session: URLSession) async throws -> [UPnPDevice] {
        let bonjour = await bonjourLocations(duration: .seconds(1))
        let devices = await loadDevices(bonjour, session: session)
        try Task.checkCancellation()
        if !devices.isEmpty { return devices }

        let responses = try await SSDP.discover(target: zonePlayer)
        try Task.checkCancellation()
        let candidates = responses.compactMap { response -> Candidate? in
            guard let uuid = response.uuid,
                  isLocalEndpoint(response.location, host: response.sourceAddress),
                  response.location.path == "/xml/device_description.xml" else { return nil }
            return Candidate(id: String(uuid.dropFirst("uuid:".count)), url: response.location)
        }
        return await loadDevices(candidates, session: session)
    }

    static func service(ofType type: String, on device: UPnPDevice) -> UPnPService? {
        guard let service = device.service(ofType: type),
              isLocalEndpoint(service.controlURL, host: device.descriptionURL.host) else { return nil }
        return service
    }

    private static func loadDevices(_ candidates: [Candidate], session: URLSession) async -> [UPnPDevice] {
        await withTaskGroup(of: UPnPDevice?.self) { group in
            for candidate in Set(candidates) where candidate.id.hasPrefix("RINCON_") {
                group.addTask {
                    try? await loadDevice(at: candidate.url, for: candidate.id, session: session)
                }
            }
            var devices: [String: UPnPDevice] = [:]
            for await device in group {
                if let device { devices[device.udn] = device }
            }
            return Array(devices.values)
        }
    }

    static func findDevice(for playerID: SonosPlayer.ID, session: URLSession) async throws -> UPnPDevice {
        if let location = await bonjourLocations(for: playerID, duration: .seconds(3)).first?.url,
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

    private static func bonjourLocations(for playerID: String? = nil, duration: Duration) async -> [Candidate] {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: "local."), using: .tcp)
        let (locations, continuation) = AsyncStream<[Candidate]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        browser.browseResultsChangedHandler = { results, _ in
            let candidates = results.compactMap { result -> Candidate? in
                guard case let .bonjour(record) = result.metadata,
                      let id = record["uuid"],
                      playerID.map({ id.caseInsensitiveCompare($0) == .orderedSame }) ?? true,
                      let location = bonjourLocation(in: record, for: id) else { return nil }
                return Candidate(id: id, url: location)
            }
            continuation.yield(candidates)
        }
        browser.stateUpdateHandler = { state in
            if case .failed = state { continuation.finish() }
        }
        browser.start(queue: .global(qos: .utility))

        let timeout = Task {
            try? await Task.sleep(for: duration)
            continuation.finish()
        }
        defer {
            timeout.cancel()
            browser.cancel()
            continuation.finish()
        }

        var latest: [Candidate] = []
        for await candidates in locations {
            if playerID != nil, !candidates.isEmpty { return candidates }
            latest = candidates
        }
        return latest
    }

    static func bonjourLocation(in record: NWTXTRecord, for playerID: SonosPlayer.ID) -> URL? {
        guard record["uuid"]?.caseInsensitiveCompare(playerID) == .orderedSame,
              let location = record["location"].flatMap(URL.init(string:)),
              isLocalEndpoint(location, host: location.host),
              location.path == "/xml/device_description.xml" else { return nil }
        return location
    }

    static func matches(_ response: SSDPResponse, playerID: SonosPlayer.ID) -> Bool {
        response.uuid?.caseInsensitiveCompare("uuid:\(playerID)") == .orderedSame
            && isLocalEndpoint(response.location, host: response.sourceAddress)
    }

    static func isLocalEndpoint(_ url: URL, host: String?) -> Bool {
        guard let host, let address = IPv4Address(host) else { return false }
        let octets = Array(address.rawValue)
        let local = octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
        return local && url.scheme == "http" && url.port == 1400 && url.host == host
            && url.user == nil && url.password == nil
    }

    static func localSession() -> URLSession {
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
