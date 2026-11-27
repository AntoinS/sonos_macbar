import Foundation

struct SonosRateLimited: LocalizedError {
    let retryAt: Date

    var errorDescription: String? {
        "Sonos is temporarily limiting requests."
    }
}

struct SonosRequestThrottle {
    private var retryAt: Date?
    private var failures = 0

    func check(now: Date = .now) throws {
        if let retryAt, retryAt > now {
            throw SonosRateLimited(retryAt: retryAt)
        }
    }

    mutating func recordSuccess(now: Date = .now) {
        if let retryAt, retryAt <= now {
            self.retryAt = nil
            failures = 0
        }
    }

    mutating func recordLimit(_ response: HTTPURLResponse, data: Data, now: Date = .now) -> SonosRateLimited {
        failures = min(failures + 1, 6)
        let fallback = now.addingTimeInterval(pow(2, Double(failures - 1)) + Double.random(in: 0...1))
        let deadline = Self.serverRetryDate(response, data: data, now: now) ?? fallback
        let retryAt = max(self.retryAt ?? now, deadline)
        self.retryAt = retryAt
        return SonosRateLimited(retryAt: retryAt)
    }

    private static func serverRetryDate(_ response: HTTPURLResponse, data: Data, now: Date) -> Date? {
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(header), seconds.isFinite, seconds > 0 {
                return now.addingTimeInterval(seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header), date > now { return date }
        }

        if String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("per day per user") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
        return nil
    }
}
