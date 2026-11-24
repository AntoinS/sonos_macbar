import Foundation
import Testing
@testable import sonos_macbar

struct AppUpdateTests {
    @Test func newerVersionLinksToThePublishedArchive() throws {
        let candidate = try AppUpdateService.update(
            in: release("0.1.10"),
            installedVersion: "0.1.9"
        )
        let update = try #require(candidate)
        #expect(update.version == "0.1.10")
        #expect(update.downloadURL.absoluteString ==
            "https://github.com/AntoinS/sonos_macbar/releases/download/v0.1.10/Sonos-Macbar-0.1.10.zip")
    }

    @Test func installedOrOlderVersionsDoNotTriggerAnUpdate() throws {
        let data = release("0.2.0")
        #expect(try AppUpdateService.update(in: data, installedVersion: "0.2.0") == nil)
        #expect(try AppUpdateService.update(in: data, installedVersion: "0.10.0") == nil)
    }

    @Test func draftAndBetaReleasesDoNotTriggerAnUpdate() throws {
        #expect(try AppUpdateService.update(in: release("1.0.0", draft: true), installedVersion: "0.2.0") == nil)
        #expect(try AppUpdateService.update(in: release("1.0.0-beta", prerelease: true), installedVersion: "0.2.0") == nil)
    }

    @Test func unfinishedReleaseCannotOfferADownload() {
        #expect(throws: URLError.self) {
            try AppUpdateService.update(in: release("1.0.0", assetState: "new"), installedVersion: "0.2.0")
        }
        #expect(throws: URLError.self) {
            try AppUpdateService.update(in: release("1.0.0", includeArchive: false), installedVersion: "0.2.0")
        }
    }

    private func release(
        _ version: String, draft: Bool = false, prerelease: Bool = false,
        assetState: String = "uploaded", includeArchive: Bool = true
    ) -> Data {
        let asset = includeArchive ? """
            {"name":"Sonos-Macbar-\(version).zip","state":"\(assetState)"}
            """ : ""
        return Data("""
            {"tag_name":"v\(version)","draft":\(draft),"prerelease":\(prerelease),"assets":[\(asset)]}
            """.utf8)
    }
}
