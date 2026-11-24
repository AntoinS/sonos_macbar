import Foundation

struct AppUpdate: Equatable {
    let version: String
    let downloadURL: URL
}

enum AppUpdateService {
    private static let latestRelease = URL(string: "https://api.github.com/repos/AntoinS/sonos_macbar/releases/latest")!
    private static let downloads = URL(string: "https://github.com/AntoinS/sonos_macbar/releases/download")!

    static var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func check(installedVersion: String, session: URLSession = .shared) async throws -> AppUpdate? {
        var request = URLRequest(url: latestRelease, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try update(in: data, installedVersion: installedVersion)
    }

    static func update(in data: Data, installedVersion: String) throws -> AppUpdate? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        guard release.tagName.hasPrefix("v") else { throw URLError(.cannotParseResponse) }
        let version = String(release.tagName.dropFirst())
        guard version.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil,
              installedVersion.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil else {
            throw URLError(.cannotParseResponse)
        }
        guard version.compare(installedVersion, options: .numeric) == .orderedDescending else { return nil }

        let archive = "Sonos-Macbar-\(version).zip"
        guard release.assets.contains(where: { $0.name == archive && $0.state == "uploaded" }) else {
            throw URLError(.resourceUnavailable)
        }
        return AppUpdate(
            version: version,
            downloadURL: downloads.appending(path: release.tagName).appending(path: archive)
        )
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
        }

        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
}
