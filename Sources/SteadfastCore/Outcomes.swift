import Foundation

// Outcomes: what the person wants their time back for, where their time goes,
// and how much a block protected. Pure values and arithmetic only — storage,
// tracking and display live in the app. Everything stays on this Mac.

/// What the person is protecting their time for.
public struct Aim: Codable, Equatable, Sendable {
    /// Their words: "Ship my app", "Get fit", "Finish the novel".
    public var title: String
    public var kind: AimKind
    /// Their answer to "if nothing changes, what will it cost you?" — shown back
    /// to them when they reach for something blocked.
    public var cost: String?
    public var deadline: Date?
    public var createdAt: Date

    public init(title: String, kind: AimKind, cost: String? = nil, deadline: Date? = nil, createdAt: Date = Date()) {
        self.title = title; self.kind = kind; self.cost = cost
        self.deadline = deadline; self.createdAt = createdAt
    }
}

public enum AimKind: String, Codable, CaseIterable, Sendable {
    case build, learn, health, create, people, calm, other

    public var label: String {
        switch self {
        case .build: return "Build something"
        case .learn: return "Learn a skill"
        case .health: return "Get healthy"
        case .create: return "Make art"
        case .people: return "Be with people"
        case .calm: return "Feel calmer"
        case .other: return "Something else"
        }
    }

    public var symbol: String {
        switch self {
        case .build: return "hammer"
        case .learn: return "book"
        case .health: return "figure.run"
        case .create: return "paintbrush.pointed"
        case .people: return "person.2"
        case .calm: return "leaf"
        case .other: return "sparkle"
        }
    }

    /// A first title to edit, so the field is never blank.
    public var suggestedTitle: String {
        switch self {
        case .build: return "Ship what I'm building"
        case .learn: return "Learn something properly"
        case .health: return "Get strong and sleep well"
        case .create: return "Make the thing I keep putting off"
        case .people: return "Be present with the people I love"
        case .calm: return "Get my attention back"
        case .other: return ""
        }
    }

    /// One concrete unit of progress and roughly how long it takes, for
    /// "that's enough time to …" lines. Deliberately conservative.
    public var unit: (singular: String, plural: String, hours: Double) {
        switch self {
        case .build: return ("focused work week", "focused work weeks", 40)
        case .learn: return ("full online course", "full online courses", 30)
        case .health: return ("hour-long workout", "hour-long workouts", 1)
        case .create: return ("finished draft chapter", "finished draft chapters", 10)
        case .people: return ("long dinner with a friend", "long dinners with friends", 2)
        case .calm: return ("unhurried morning", "unhurried mornings", 2)
        case .other: return ("focused work week", "focused work weeks", 40)
        }
    }
}

/// Where a figure for "time per day" came from, strongest first.
public enum UsageSource: String, Codable, Sendable, Comparable {
    /// Steadfast's own tally on this Mac.
    case measured
    /// Kept only to decode old imported estimates. Never collected or shown.
    case legacyImport = "coast"
    /// The person's own guess during setup.
    case estimate

    private var rank: Int { switch self { case .measured: 0; case .legacyImport: 1; case .estimate: 2 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// The distraction categories people estimate during setup. They map onto the
/// website preset groups and app categories so a guess can preselect a blocklist.
public enum TimeSink: String, Codable, CaseIterable, Sendable {
    case social, video, games, feeds, news, chat, shopping

    public var label: String {
        switch self {
        case .social: return "Social"
        case .video: return "Streaming"
        case .games: return "Games"
        case .feeds: return "Forums & feeds"
        case .news: return "News"
        case .chat: return "Chat"
        case .shopping: return "Shopping"
        }
    }

    public var symbol: String {
        switch self {
        case .social: return "person.2.wave.2"
        case .video: return "play.rectangle"
        case .games: return "gamecontroller"
        case .feeds: return "text.bubble"
        case .news: return "newspaper"
        case .chat: return "bubble.left.and.bubble.right"
        case .shopping: return "bag"
        }
    }

    /// Matching `Presets.groups` names in the app.
    public var presetGroups: [String] {
        switch self {
        case .social: return ["social"]
        case .video: return ["streaming"]
        case .games: return ["games"]
        case .feeds: return ["forums & feeds"]
        case .news: return ["news"]
        case .chat: return ["chat"]
        case .shopping: return ["shopping"]
        }
    }
}

/// A guessed or imported daily figure for one sink.
public struct TimeEstimate: Codable, Equatable, Sendable {
    public var sink: TimeSink
    public var minutesPerDay: Double
    public var source: UsageSource
    public init(sink: TimeSink, minutesPerDay: Double, source: UsageSource) {
        self.sink = sink; self.minutesPerDay = max(0, minutesPerDay); self.source = source
    }
}

/// One local day of Steadfast's own foreground tally, in seconds.
public struct UsageDay: Codable, Equatable, Sendable {
    /// Local calendar day, `yyyy-MM-dd`.
    public var day: String
    /// Seconds by lowercased bundle identifier.
    public var apps: [String: Double]
    /// Seconds by registrable domain, only when browser reading is allowed.
    public var domains: [String: Double]
    public init(day: String, apps: [String: Double] = [:], domains: [String: Double] = [:]) {
        self.day = day; self.apps = apps; self.domains = domains
    }
    public var total: Double { apps.values.reduce(0, +) }
}

/// The three timelines of what a habit costs, and what that time could be instead.
public struct Cost: Equatable, Sendable {
    public let minutesPerDay: Double
    /// From January 1 of this year until now.
    public let thisYearHours: Double
    /// Seven days at the daily rate.
    public let weekHours: Double
    /// The next twelve months at the daily rate.
    public let nextYearHours: Double
    /// The next five years at the daily rate.
    public let fiveYearHours: Double
    /// Five years expressed in waking days of 16 hours.
    public let fiveYearWakingDays: Double
}

public enum Ledger {
    /// Hours a person is awake and able to choose, used for "waking days".
    public static let wakingHoursPerDay = 16.0
    /// Protected time counts only inside these local hours, so an overnight block
    /// is not credited with time that would have been spent asleep.
    public static let dayStartHour = 7
    public static let dayEndHour = 23

    public static func cost(minutesPerDay: Double, now: Date, calendar: Calendar = .current) -> Cost {
        let perDay = max(0, minutesPerDay) / 60
        let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let daysSoFar = max(0, now.timeIntervalSince(yearStart) / 86_400)
        let fiveYears = perDay * 365 * 5
        return Cost(minutesPerDay: max(0, minutesPerDay), thisYearHours: perDay * daysSoFar, weekHours: perDay * 7,
                    nextYearHours: perDay * 365, fiveYearHours: fiveYears,
                    fiveYearWakingDays: fiveYears / wakingHoursPerDay)
    }

    /// How many of the aim's units fit in `hours`, rounded down, never negative.
    public static func units(of kind: AimKind, in hours: Double) -> Int {
        max(0, Int((hours / kind.unit.hours).rounded(.down)))
    }

    /// "12 hour-long workouts", "1 focused work week".
    public static func unitsText(of kind: AimKind, in hours: Double) -> String {
        let count = units(of: kind, in: hours)
        return "\(count.formatted()) \(count == 1 ? kind.unit.singular : kind.unit.plural)"
    }

    /// The best available daily figure: measured time takes priority over a guess. Only
    /// measured figures with at least `minimumDays` of tally replace the others.
    public static func dailyMinutes(estimates: [TimeEstimate], measuredDays: [UsageDay] = [], distracting: Set<String> = [], minimumDays: Int = 3) -> (minutes: Double, source: UsageSource)? {
        let tallied = measuredDays.filter { $0.total > 0 }
        if tallied.count >= minimumDays, !distracting.isEmpty {
            let seconds = tallied.map { day in
                day.apps.filter { distracting.contains($0.key) }.values.reduce(0, +)
                    + day.domains.filter { distracting.contains($0.key) }.values.reduce(0, +)
            }.reduce(0, +)
            return (seconds / 60 / Double(tallied.count), .measured)
        }
        guard let best = estimates.map(\.source).min() else { return nil }
        let minutes = estimates.filter { $0.source == best }.map(\.minutesPerDay).reduce(0, +)
        return (minutes, best)
    }

    /// Seconds of `day` covered by at least one commitment, counting only the
    /// waking window and never counting overlapping commitments twice.
    public static func protectedSeconds(_ commitments: [Commitment], on day: Date, now: Date, notBefore: Date = .distantPast,
                                        calendar: Calendar = .current) -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        guard let waking = calendar.date(byAdding: .hour, value: dayStartHour, to: start),
              let close = calendar.date(byAdding: .hour, value: dayEndHour, to: start) else { return 0 }
        let open = max(waking, notBefore)
        let limit = min(close, now)
        guard limit > open else { return 0 }
        return coveredSeconds(commitments, from: open, to: limit)
    }

    /// Elapsed coverage by at least one block, including night hours. This does
    /// not measure attention, time saved, or work completed.
    public static func coverageHours(_ commitments: [Commitment], from: Date, to: Date, now: Date) -> Double {
        coveredSeconds(commitments, from: from, to: min(to, now)) / 3600
    }

    private static func coveredSeconds(_ commitments: [Commitment], from open: Date, to limit: Date) -> TimeInterval {
        guard limit > open else { return 0 }
        let spans = commitments
            .map { (max($0.createdAt, open), min($0.endsAt, limit)) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for span in spans {
            if let c = current, span.0 <= c.1 {
                current = (c.0, max(c.1, span.1))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = span
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    /// Protected hours for every day of `now`'s year, January 1 first. Future days are nil.
    public static func year(_ commitments: [Commitment], now: Date, calendar: Calendar = .current) -> [Double?] {
        guard let interval = calendar.dateInterval(of: .year, for: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        let relevant = commitments.filter { $0.endsAt > interval.start && $0.createdAt < interval.end }
        var days: [Double?] = []
        var day = interval.start
        while day < interval.end {
            days.append(day > today ? nil : protectedSeconds(relevant, on: day, now: now, calendar: calendar) / 3600)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Total protected hours in `[from, to)`, by local day.
    public static func protectedHours(_ commitments: [Commitment], from: Date, to: Date, now: Date, calendar: Calendar = .current) -> Double {
        var total = 0.0
        var day = calendar.startOfDay(for: from)
        let relevant = commitments.filter { $0.endsAt > from && $0.createdAt < to }
        while day < to {
            total += protectedSeconds(relevant, on: day, now: min(now, to), notBefore: from, calendar: calendar)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total / 3600
    }

    /// Local `yyyy-MM-dd` for `date`.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
