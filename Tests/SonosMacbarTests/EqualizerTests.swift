import Foundation
import Network
import Testing
import UPnPCast
@testable import sonos_macbar

struct EqualizerTests {
    @Test func discoveryMatchesPlayerIDAndReplyAddress() throws {
        let message = """
            HTTP/1.1 200 OK
            LOCATION: http://192.168.1.12:1400/xml/device_description.xml
            USN: uuid:RINCON_BEAM::urn:schemas-upnp-org:device:ZonePlayer:1
            """
        let response = try #require(SSDPResponse(message: message, sourceAddress: "192.168.1.12"))
        #expect(SonosLocalDiscovery.matches(response, playerID: "RINCON_BEAM"))
        #expect(!SonosLocalDiscovery.matches(response, playerID: "RINCON_OTHER"))

        let mismatchedAddress = try #require(SSDPResponse(message: message, sourceAddress: "192.168.1.13"))
        #expect(!SonosLocalDiscovery.matches(mismatchedAddress, playerID: "RINCON_BEAM"))
    }

    @Test func subBelongsToSelectedRoom() {
        let xml = """
            <ZoneGroups><ZoneGroup>
                <ZoneGroupMember UUID="RINCON_BEAM" HTSatChanMapSet="RINCON_BEAM:LF,RF;RINCON_SUB:SW">
                    <Satellite UUID="RINCON_SUB"/>
                </ZoneGroupMember>
                <ZoneGroupMember UUID="RINCON_OTHER" ChannelMapSet="RINCON_OTHER:LF;RINCON_PAIR:RF"/>
            </ZoneGroup></ZoneGroups>
            """
        #expect(SonosEqualizerService.hasBondedSub(in: xml, for: "RINCON_BEAM"))
        #expect(!SonosEqualizerService.hasBondedSub(in: xml, for: "RINCON_OTHER"))
        #expect(!SonosEqualizerService.hasBondedSub(in: xml, for: "RINCON_SUB"))
    }

    @Test func bonjourUsesOnlyTheSelectedDevicesDescription() {
        let description = "http://192.168.1.12:1400/xml/device_description.xml"
        let record = NWTXTRecord(["uuid": "RINCON_BEAM", "location": description])
        #expect(SonosLocalDiscovery.bonjourLocation(in: record, for: "RINCON_BEAM")?.absoluteString == description)
        #expect(SonosLocalDiscovery.bonjourLocation(in: record, for: "RINCON_OTHER") == nil)
        let wrongPort = NWTXTRecord(["uuid": "RINCON_BEAM", "location": "http://192.168.1.12:1443/xml/device_description.xml"])
        #expect(SonosLocalDiscovery.bonjourLocation(in: wrongPort, for: "RINCON_BEAM") == nil)
    }

    @Test func commandValuesUseEachControlsRange() throws {
        #expect(EqualizerControl.bass.clamped(11) == 10)
        #expect(EqualizerControl.treble.clamped(-11) == -10)
        #expect(EqualizerControl.loudness.clamped(2) == 1)
        let command = EqualizerControl.subLevel.writeCommand(-16)
        #expect(command.action == "SetEQ")
        #expect(Dictionary(uniqueKeysWithValues: command.arguments) == [
            "InstanceID": "0", "EQType": "SubGain", "DesiredValue": "-15"
        ])
        #expect(try EqualizerControl.subLevel.readValue(["CurrentValue": "0"]) == 0)
        #expect(throws: SonosAPIError.self) { try EqualizerControl.treble.readValue(["CurrentTreble": "11"]) }
    }

    @Test @MainActor func roomSessionsKeepTheirOwnValuesAndWriteTarget() async {
        let calls = WriteRecorder()
        let connect: @Sendable (String) async throws -> EqualizerConnection = { playerID in
            let values: [EqualizerControl: Int] = playerID == "beam" ? [.bass: 1, .subLevel: 0] : [.bass: -2]
            return EqualizerConnection(values: values) { control, value in
                await calls.record(playerID, control, value)
            }
        }
        let firstRoom = EqualizerState(playerID: "beam", connect: connect)
        let secondRoom = EqualizerState(playerID: "other", connect: connect)
        await firstRoom.load()
        await secondRoom.load()
        await secondRoom.save(.bass, value: -3)
        await secondRoom.save(.subLevel, value: 4)

        #expect(firstRoom.values == [.bass: 1, .subLevel: 0])
        #expect(secondRoom.values == [.bass: -3])
        #expect(await calls.writes == [.init(playerID: "other", control: .bass, value: -3)])
    }

    @Test @MainActor func failedWriteKeepsConfirmedValueAndCanBeRetried() async throws {
        let calls = WriteRecorder()
        let state = EqualizerState(playerID: "beam") { _ in
            EqualizerConnection(values: [.bass: 0]) { control, value in
                if await calls.record("beam", control, value) == 1 {
                    throw URLError(.notConnectedToInternet)
                }
            }
        }
        await state.load()
        await state.save(.bass, value: 1)
        #expect(state.values[.bass] == 0)
        let change = try #require(state.failedChange)
        await state.save(change.control, value: change.value)
        #expect(state.values[.bass] == 1)
        #expect(state.failedChange == nil)
    }
}

private actor WriteRecorder {
    struct Write: Equatable {
        let playerID: String
        let control: EqualizerControl
        let value: Int
    }

    private(set) var writes: [Write] = []

    @discardableResult
    func record(_ playerID: String, _ control: EqualizerControl, _ value: Int) -> Int {
        writes.append(Write(playerID: playerID, control: control, value: value))
        return writes.count
    }
}
