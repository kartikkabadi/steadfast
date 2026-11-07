import Foundation
import Testing
@testable import SteadfastCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Test func protectedTimeReadsNaturally() {
    #expect(ProtectedTime.short(hours: 0) == "0 min")
    #expect(ProtectedTime.short(hours: 35 / 60) == "35 min")
    #expect(ProtectedTime.short(hours: 2.5) == "2 h 30 min")
    #expect(ProtectedTime.short(hours: 3) == "3 h")
    #expect(ProtectedTime.short(hours: 141.6) == "142 h")
    #expect(ProtectedTime.phrase(hours: 1 / 60) == "1 minute")
    #expect(ProtectedTime.phrase(hours: 1) == "1 hour")
    #expect(ProtectedTime.phrase(hours: 4.46) == "4.5 hours")
    #expect(ProtectedTime.phrase(hours: 4) == "4 hours")
    #expect(ProtectedTime.phrase(hours: 142.4) == "142 hours")
    #expect(ProtectedTime.figure(hours: 0.5) == ("30", "minutes"))
    #expect(ProtectedTime.figure(hours: 12.2) == ("12", "hours"))
}

@Test func ringScaleIsCappedAndMonotonic() {
    #expect(RingScale.length(hours: -1) == 0)
    #expect(RingScale.length(hours: 4) == 0.5)
    #expect(RingScale.length(hours: 20) == 1)
    #expect(RingScale.tint(hours: 0.5) > RingScale.length(hours: 0.5))
    #expect(RingScale.tint(hours: 2) < RingScale.tint(hours: 3))
}

@Test func ringGeometryFindsDays() {
    let band = 100.0...140.0
    // Straight up is January 1; right is a quarter through; left three quarters.
    #expect(RingGeometry.day(dx: 0, dy: -120, count: 365, band: band) == 0)
    #expect(RingGeometry.day(dx: 120, dy: 0, count: 364, band: band) == 91)
    #expect(RingGeometry.day(dx: -120, dy: 0, count: 364, band: band) == 273)
    // Just left of twelve o'clock is the last day, not past the end.
    #expect(RingGeometry.day(dx: -0.5, dy: -120, count: 365, band: band) == 0)
    #expect(RingGeometry.day(dx: -20, dy: -118, count: 365, band: band) == 355)
    #expect(RingGeometry.day(dx: 0, dy: -50, count: 365, band: band) == nil)
    #expect(RingGeometry.angle(0, of: 365) == -.pi / 2)
}

@Test func blockCountsSpanDaysOnce() {
    let now = date("2026-03-10T12:00:00Z")
    let items = [Commitment(domains: ["x.com"], createdAt: date("2026-03-08T22:00:00Z"), endsAt: date("2026-03-09T02:00:00Z")),
                 Commitment(domains: ["x.com"], createdAt: date("2026-03-09T09:00:00Z"), endsAt: date("2026-03-10T00:00:00Z")),
                 Commitment(domains: ["x.com"], createdAt: date("2025-12-31T20:00:00Z"), endsAt: date("2026-01-01T08:00:00Z"))]
    let counts = Ledger.blockCounts(items, now: now, calendar: utc)
    #expect(counts.count == 365)
    #expect(counts[0] == 1)
    #expect(counts[66] == 1)  // March 8
    #expect(counts[67] == 2)  // March 9
    #expect(counts[68] == 0)  // March 10: the second block ended at midnight
    #expect(Ledger.dayIndex(now, calendar: utc) == 68)
}

@Test func steadyLinesAreStablePerBlock() {
    let id = UUID(uuidString: "6F1D8E8A-3C64-4B0B-9C59-1E1F3B9A0C11")!
    #expect(SteadyLines.line(for: id, kind: .build) == SteadyLines.line(for: id, kind: .build))
    #expect(SteadyLines.stableHash(id) == SteadyLines.stableHash(UUID(uuidString: id.uuidString)!))
    // Different blocks see a spread of lines, not one.
    let seen = Set((0..<60).map { _ in SteadyLines.line(for: UUID(), kind: .calm).text })
    #expect(seen.count > 5)
    #expect(SteadyLines.pool(for: .health).count == SteadyLines.general.count + 2)
    #expect(SteadyLines.pool(for: nil) == SteadyLines.general)
    // Calm and plain: no exclamation marks anywhere.
    for kind in AimKind.allCases {
        #expect(SteadyLines.pool(for: kind).allSatisfy { !$0.text.contains("!") })
    }
}
