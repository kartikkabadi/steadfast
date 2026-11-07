import Foundation

public struct DailyLimit: Codable, Equatable, Identifiable, Sendable {
    public var id: String { domain }
    public let domain: String
    public var minutes: Int
    public var secondsUsed = 0.0
    public var dayStart: Date?
    public var lastSample: Date?

    public init(domain: String, minutes: Int) {
        self.domain = domain; self.minutes = minutes
    }

    public func usage(at date: Date, calendar: Calendar = .current) -> Double {
        guard dayStart == calendar.startOfDay(for: date) else { return 0 }
        return secondsUsed
    }

    public func blockedUntil(at date: Date, calendar: Calendar = .current) -> Date? {
        guard usage(at: date, calendar: calendar) >= Double(minutes * 60) else { return nil }
        return calendar.dateInterval(of: .day, for: date)?.end
    }
}

public struct UsageSample: Codable, Sendable {
    public let domain: String
    public let endedAt: Date
    public let seconds: Double

    public init(domain: String, endedAt: Date, seconds: Double) {
        self.domain = domain; self.endedAt = endedAt; self.seconds = seconds
    }
}

extension Policy {
    public mutating func saveLimit(domain input: String, minutes: Int) throws {
        let domain = try Domain.parse(input)
        guard (1...1440).contains(minutes) else { throw Failure("choose a daily limit between 1 and 1,440 minutes") }
        if let index = dailyLimits.firstIndex(where: { $0.domain == domain }) {
            dailyLimits[index].minutes = minutes
            return
        }
        guard dailyLimits.count < 20 else { throw Failure("you can set up to 20 daily limits") }
        guard !dailyLimits.contains(where: { Domain.matches(domain, rule: $0.domain) || Domain.matches($0.domain, rule: domain) }) else {
            throw Failure("a daily limit already covers this website")
        }
        dailyLimits.append(DailyLimit(domain: domain, minutes: minutes))
        dailyLimits.sort { $0.domain < $1.domain }
    }

    @discardableResult public mutating func recordUsage(_ sample: UsageSample, at date: Date, calendar: Calendar = .current) throws -> Bool {
        guard sample.seconds.isFinite, sample.seconds > 0, sample.seconds <= 8,
              abs(date.timeIntervalSince(sample.endedAt)) <= 20 else {
            throw Failure("that usage sample is no longer current")
        }
        guard let index = dailyLimits.firstIndex(where: { $0.domain == sample.domain }) else { return false }
        var limit = dailyLimits[index]
        guard limit.blockedUntil(at: date, calendar: calendar) == nil else { return false }
        let day = calendar.startOfDay(for: date)
        let intervalStart = max(day, max(limit.lastSample ?? day, sample.endedAt.addingTimeInterval(-sample.seconds)))
        let seconds = min(date, sample.endedAt).timeIntervalSince(intervalStart)
        guard seconds > 0 else { return false }
        limit.secondsUsed = limit.usage(at: date, calendar: calendar) + seconds
        limit.dayStart = day
        limit.lastSample = min(date, sample.endedAt)
        dailyLimits[index] = limit
        return true
    }
}
