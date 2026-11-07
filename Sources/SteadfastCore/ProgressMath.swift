import Foundation

// Pure helpers behind the Progress page and the year ring: wording for amounts of
// protected time, the ring's colour scale and geometry, and per-day block counts.

public enum ProtectedTime {
    /// Compact, for stats and rows: "35 min", "2 h 30 min", "142 h".
    public static func short(hours: Double) -> String {
        let minutes = Int((max(0, hours) * 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        if minutes >= 600 { return "\(Int((Double(minutes) / 60).rounded()).formatted()) h" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// For a sentence: "35 minutes", "1 hour", "4.5 hours", "142 hours".
    public static func phrase(hours: Double) -> String {
        let hours = max(0, hours)
        let minutes = Int((hours * 60).rounded())
        if minutes < 60 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes")" }
        if hours < 10 {
            let tenths = (hours * 10).rounded() / 10
            if tenths == 1 { return "1 hour" }
            return "\(tenths.formatted(.number.precision(.fractionLength(0...1)))) hours"
        }
        return "\(Int(hours.rounded()).formatted()) hours"
    }

    /// The figure and unit for the ring's centre: ("35", "minutes"), ("4.5", "hours"), ("142", "hours").
    public static func figure(hours: Double) -> (value: String, unit: String) {
        let hours = max(0, hours)
        let minutes = Int((hours * 60).rounded())
        if minutes < 60 { return ("\(minutes)", minutes == 1 ? "minute" : "minutes") }
        if hours < 10 {
            let tenths = (hours * 10).rounded() / 10
            return (tenths.formatted(.number.precision(.fractionLength(0...1))), tenths == 1 ? "hour" : "hours")
        }
        return (Int(hours.rounded()).formatted(), "hours")
    }
}

public enum RingScale {
    /// A day with this many protected hours draws at full length and full accent.
    public static let fullHours = 8.0

    /// 0...1 length of a day's tick: linear in hours, capped at `fullHours`.
    public static func length(hours: Double) -> Double {
        min(1, max(0, hours) / fullHours)
    }

    /// 0...1 mix from neutral to accent. Square root, so a quiet half hour is still
    /// visibly more than nothing while long days stay distinct.
    public static func tint(hours: Double) -> Double {
        length(hours: hours).squareRoot()
    }
}

public enum RingGeometry {
    /// Radians for the start of day `index` of `count`, measured clockwise from twelve o'clock
    /// in a y-down coordinate space (0 points up).
    public static func angle(_ index: Double, of count: Int) -> Double {
        index / Double(max(1, count)) * 2 * .pi - .pi / 2
    }

    /// The day nearest to a point at offset (`dx`, `dy`) from the centre, y down,
    /// or nil when the point is outside `band` (inner and outer radius).
    public static func day(dx: Double, dy: Double, count: Int, band: ClosedRange<Double>) -> Int? {
        guard count > 0, band.contains((dx * dx + dy * dy).squareRoot()) else { return nil }
        let turn = (atan2(dy, dx) + .pi / 2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return Int((turn / (2 * .pi) * Double(count)).rounded()) % count
    }
}

extension Ledger {
    /// How many commitments touch each day of `now`'s year, January 1 first.
    public static func blockCounts(_ commitments: [Commitment], now: Date, calendar: Calendar = .current) -> [Int] {
        guard let interval = calendar.dateInterval(of: .year, for: now) else { return [] }
        let count = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        var counts = Array(repeating: 0, count: count)
        for item in commitments where item.endsAt > interval.start && item.createdAt < interval.end {
            let first = calendar.startOfDay(for: max(item.createdAt, interval.start))
            // A block ending exactly at midnight doesn't touch the next day.
            let last = calendar.startOfDay(for: min(item.endsAt.addingTimeInterval(-1), interval.end.addingTimeInterval(-1)))
            guard let a = calendar.dateComponents([.day], from: interval.start, to: first).day,
                  let b = calendar.dateComponents([.day], from: interval.start, to: last).day else { continue }
            for index in max(0, a)...min(count - 1, max(a, b)) { counts[index] += 1 }
        }
        return counts
    }

    /// Zero-based index of `date` within its year.
    public static func dayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        (calendar.ordinality(of: .day, in: .year, for: date) ?? 1) - 1
    }
}
