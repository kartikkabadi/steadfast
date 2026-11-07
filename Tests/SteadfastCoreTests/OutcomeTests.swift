import Foundation
import Testing
@testable import SteadfastCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

private func commitment(_ start: String, _ end: String) -> Commitment {
    Commitment(domains: ["x.com"], createdAt: date(start), endsAt: date(end))
}

@Test func costCoversThreeTimelines() {
    let cost = Ledger.cost(minutesPerDay: 360, now: date("2026-07-02T00:00:00Z"), calendar: utc)
    #expect(cost.weekHours == 42)
    #expect(cost.nextYearHours == 2190)
    #expect(abs(cost.thisYearHours - 6 * 182) < 0.001)
    #expect(cost.fiveYearHours == 10950)
    #expect(abs(cost.fiveYearWakingDays - 684.375) < 0.001)
    #expect(Ledger.cost(minutesPerDay: -5, now: Date(), calendar: utc).weekHours == 0)
}

@Test func unitsRoundDown() {
    #expect(Ledger.units(of: .build, in: 79) == 1)
    #expect(Ledger.unitsText(of: .build, in: 80) == "2 focused work weeks")
    #expect(Ledger.unitsText(of: .health, in: 1.5) == "1 hour-long workout")
    #expect(Ledger.units(of: .learn, in: -3) == 0)
}

@Test func protectedTimeMergesOverlapsAndSkipsNight() {
    let day = date("2026-03-10T12:00:00Z")
    let now = date("2026-03-11T00:00:00Z")
    let items = [commitment("2026-03-10T09:00:00Z", "2026-03-10T11:00:00Z"),
                 commitment("2026-03-10T10:00:00Z", "2026-03-10T12:00:00Z"),
                 commitment("2026-03-10T22:00:00Z", "2026-03-11T06:00:00Z")]
    // 09–12 merged is 3 h, plus 22–23 is 1 h; nothing after 23:00 counts.
    #expect(Ledger.protectedSeconds(items, on: day, now: now, calendar: utc) == 4 * 3600)
    // Only time already passed counts.
    #expect(Ledger.protectedSeconds(items, on: day, now: date("2026-03-10T10:00:00Z"), calendar: utc) == 3600)
    #expect(Ledger.protectedSeconds([commitment("2026-03-10T01:00:00Z", "2026-03-10T06:00:00Z")], on: day, now: now, calendar: utc) == 0)
}

@Test func protectedHoursStartAtTheRangeStart() {
    let items = [commitment("2026-03-10T08:00:00Z", "2026-03-10T12:00:00Z")]
    let now = date("2026-03-11T00:00:00Z")
    // A range that begins mid-morning leaves out the earlier part of the same day.
    #expect(Ledger.protectedHours(items, from: date("2026-03-10T10:00:00Z"), to: now, now: now, calendar: utc) == 2)
    #expect(Ledger.protectedHours(items, from: date("2026-03-10T00:00:00Z"), to: now, now: now, calendar: utc) == 4)
}

@Test func yearHasOneEntryPerDayAndNoFuture() {
    let now = date("2026-02-01T15:00:00Z")
    let year = Ledger.year([commitment("2026-02-01T08:00:00Z", "2026-02-01T10:00:00Z")], now: now, calendar: utc)
    #expect(year.count == 365)
    #expect(year[31] == 2)
    #expect(year[30] == 0)
    #expect(year[32] == nil)
}

@Test func dailyMinutesPrefersStrongestSource() {
    let estimates = [TimeEstimate(sink: .social, minutesPerDay: 120, source: .estimate),
                     TimeEstimate(sink: .video, minutesPerDay: 60, source: .estimate)]
    #expect(Ledger.dailyMinutes(estimates: estimates)?.minutes == 180)
    let withLegacy = estimates + [TimeEstimate(sink: .social, minutesPerDay: 150, source: .legacyImport)]
    #expect(Ledger.dailyMinutes(estimates: withLegacy)?.source == .legacyImport)
    let days = (1...3).map { UsageDay(day: "2026-01-0\($0)", apps: ["com.hnc.discord": 3600, "com.apple.dt.xcode": 7200]) }
    let measured = Ledger.dailyMinutes(estimates: withLegacy, measuredDays: days, distracting: ["com.hnc.discord"])
    #expect(measured?.minutes == 60)
    #expect(measured?.source == .measured)
    #expect(Ledger.dailyMinutes(estimates: []) == nil)
}

@Test func aimRoundTrips() throws {
    let aim = Aim(title: "Ship it", kind: .build, cost: "Another year of almost", createdAt: date("2026-01-01T00:00:00Z"))
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(Aim.self, from: encoder.encode(aim)) == aim)
}
