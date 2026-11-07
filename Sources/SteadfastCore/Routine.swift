import Foundation

public struct WeeklySchedule: Codable, Equatable, Sendable {
    public var weekdays: [Int]
    public var startMinute: Int
    public var enabled: Bool
    public init(weekdays: [Int], startMinute: Int, enabled: Bool = true) {
        self.weekdays = weekdays; self.startMinute = startMinute; self.enabled = enabled
    }
}

public struct Routine: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var domains: [String]
    public var apps: [BlockedApp]
    public var minutes: Double
    public var schedule: WeeklySchedule?
    public var createdAt: Date
    public var lastStartedAt: Date?
    public var skippedStart: Date?

    public init(id: UUID = UUID(), name: String, domains: [String], apps: [BlockedApp] = [], minutes: Double, schedule: WeeklySchedule? = nil) {
        self.id = id; self.name = name; self.domains = domains; self.apps = apps; self.minutes = minutes
        self.schedule = schedule; self.createdAt = Date()
    }

    private enum CodingKeys: String, CodingKey { case id, name, domains, apps, minutes, schedule, createdAt, lastStartedAt, skippedStart }
    // Routines saved before app blocking have no apps.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        domains = try values.decode([String].self, forKey: .domains)
        apps = try values.decodeIfPresent([BlockedApp].self, forKey: .apps) ?? []
        minutes = try values.decode(Double.self, forKey: .minutes)
        schedule = try values.decodeIfPresent(WeeklySchedule.self, forKey: .schedule)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastStartedAt = try values.decodeIfPresent(Date.self, forKey: .lastStartedAt)
        skippedStart = try values.decodeIfPresent(Date.self, forKey: .skippedStart)
    }

    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard let schedule, schedule.enabled else { return nil }
        let today = calendar.startOfDay(for: date)
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  schedule.weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = start(on: day, calendar: calendar),
                  start >= createdAt, start > date, start != skippedStart else { continue }
            return start
        }
        return nil
    }

    public func currentStart(at date: Date, calendar: Calendar = .current) -> Date? {
        guard let schedule, schedule.enabled else { return nil }
        let today = calendar.startOfDay(for: date)
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  schedule.weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = start(on: day, calendar: calendar),
                  start >= createdAt, start <= date, date < start.addingTimeInterval(minutes * 60),
                  start != skippedStart, lastStartedAt.map({ start > $0 }) ?? true else { continue }
            return start
        }
        return nil
    }

    private func start(on day: Date, calendar: Calendar) -> Date? {
        guard let schedule else { return nil }
        return calendar.date(bySettingHour: schedule.startMinute / 60, minute: schedule.startMinute % 60,
                             second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}

public struct RoutineTemplate: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let domains: [String]
    public let apps: [BlockedApp]
    public let minutes: Double

    public init(_ routine: Routine) {
        id = routine.id; name = routine.name; domains = routine.domains; apps = routine.apps; minutes = routine.minutes
    }

    private enum CodingKeys: String, CodingKey { case id, name, domains, apps, minutes }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        domains = try values.decode([String].self, forKey: .domains)
        apps = try values.decodeIfPresent([BlockedApp].self, forKey: .apps) ?? []
        minutes = try values.decode(Double.self, forKey: .minutes)
    }
}

public struct RoutineSyncChange: Codable, Sendable {
    public let expected: [RoutineTemplate]
    public let desired: [RoutineTemplate]

    public init(expected: [RoutineTemplate], desired: [RoutineTemplate]) {
        self.expected = expected; self.desired = desired
    }
}

extension Policy {
    public var routineTemplates: [RoutineTemplate] {
        routines.map(RoutineTemplate.init).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public mutating func applyRoutineSync(_ change: RoutineSyncChange, at date: Date) throws {
        guard routineTemplates == change.expected else {
            throw Failure("routines changed during sync. try again")
        }
        guard change.desired.count <= 30, Set(change.desired.map(\.id)).count == change.desired.count else {
            throw Failure("the shared library must contain up to 30 unique routines")
        }
        let unchanged = routines.filter { change.desired.contains(RoutineTemplate($0)) }
        if let scheduled = routines.first(where: { $0.schedule?.enabled == true && !unchanged.contains($0) }) {
            throw Failure("turn off the schedule for \(scheduled.name) before syncing its changes")
        }
        var next = self
        next.routines = unchanged
        for template in change.desired where !unchanged.contains(where: { $0.id == template.id }) {
            let schedule = routines.first(where: { $0.id == template.id })?.schedule
            try next.saveRoutine(Routine(id: template.id, name: template.name, domains: template.domains,
                                         apps: template.apps, minutes: template.minutes, schedule: schedule), at: date)
        }
        self = next
    }

    public mutating func saveRoutine(_ input: Routine, at date: Date) throws {
        var routine = input
        routine.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !routine.name.isEmpty, routine.name.count <= 60 else { throw Failure("enter a name with 1 to 60 characters") }
        routine.domains = try Domain.normalized(routine.domains)
        routine.apps = try AppRule.normalized(routine.apps)
        guard !routine.domains.isEmpty || !routine.apps.isEmpty else { throw Failure("choose at least one website or app") }
        guard routine.minutes.isFinite, (1...525_600).contains(routine.minutes) else {
            throw Failure("choose a duration between 1 minute and 365 days")
        }
        if var schedule = routine.schedule {
            schedule.weekdays = Array(Set(schedule.weekdays)).sorted()
            guard !schedule.weekdays.isEmpty, schedule.weekdays.allSatisfy({ (1...7).contains($0) }),
                  (0..<1440).contains(schedule.startMinute) else { throw Failure("choose a start time and at least one day") }
            guard routine.minutes <= 1440 else { throw Failure("scheduled blocks can last up to 24 hours") }
            routine.schedule = schedule
        }
        let others = routines.filter { $0.id != routine.id }
        guard others.count < 30 else { throw Failure("you can save up to 30 routines") }
        guard !others.contains(where: { $0.name.localizedCaseInsensitiveCompare(routine.name) == .orderedSame }) else {
            throw Failure("a routine already has this name. choose another name")
        }
        let allDomains = Set((others + [routine]).flatMap(\.domains) + active(at: date).flatMap(\.domains))
        guard allDomains.count <= 500 else { throw Failure("you can save up to 500 different websites") }
        let allApps = Set((others + [routine]).flatMap(\.apps) + active(at: date).flatMap(\.apps))
        guard allApps.count <= AppRule.maximumApps else { throw Failure("you can save up to \(AppRule.maximumApps) different apps") }
        if let existing = routines.first(where: { $0.id == routine.id }),
           existing.domains == routine.domains, existing.apps.map(\.key) == routine.apps.map(\.key),
           existing.minutes == routine.minutes, existing.schedule == routine.schedule {
            routine.createdAt = existing.createdAt; routine.lastStartedAt = existing.lastStartedAt
            routine.skippedStart = existing.skippedStart
        } else {
            routine.createdAt = date; routine.lastStartedAt = nil; routine.skippedStart = nil
        }
        routines = (others + [routine]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public mutating func setSkippedRun(routineID: UUID, start: Date, skip: Bool, at date: Date) throws {
        guard let index = routines.firstIndex(where: { $0.id == routineID }),
              routines[index].schedule?.enabled == true, start > date else {
            throw Failure("that run is no longer upcoming. refresh and try again")
        }
        if skip {
            guard routines[index].skippedStart != start else { return }
            guard routines[index].skippedStart.map({ $0 <= date }) ?? true,
                  routines[index].nextStart(after: date) == start else {
                throw Failure("the next run changed. check the schedule and try again")
            }
            routines[index].skippedStart = start
        } else if routines[index].skippedStart == start {
            routines[index].skippedStart = nil
        }
    }

    @discardableResult public mutating func startScheduledBlocks(at date: Date, calendar: Calendar = .current) -> Bool {
        var changed = false
        for index in routines.indices {
            let routine = routines[index]
            guard let start = routine.currentStart(at: date, calendar: calendar) else { continue }
            commitments.append(Commitment(domains: routine.domains, apps: routine.apps, createdAt: date,
                                          endsAt: start.addingTimeInterval(routine.minutes * 60),
                                          name: routine.name, routineID: routine.id))
            routines[index].lastStartedAt = start
            changed = true
        }
        if changed { trimHistory(at: date); lastObserved = date }
        return changed
    }
}

public enum DurationLabel {
    public static func text(_ minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0, minutes <= 525_600 else { return "custom duration" }
        if minutes < 1 { return "less than a minute" }
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(Int(minutes / 1440)) \(minutes == 1440 ? "day" : "days")" }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(minutes / 60)) \(minutes == 60 ? "hour" : "hours")" }
        return "\(minutes.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))) \(minutes == 1 ? "minute" : "minutes")"
    }
}
