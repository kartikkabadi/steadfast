import Foundation

public struct Commitment: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let domains: [String]
    public let apps: [BlockedApp]
    public let createdAt: Date
    public let endsAt: Date
    public let name: String?
    public let routineID: UUID?
    public init(domains: [String], apps: [BlockedApp] = [], createdAt: Date, endsAt: Date, name: String? = nil, routineID: UUID? = nil) {
        self.id = UUID(); self.domains = domains; self.apps = apps; self.createdAt = createdAt; self.endsAt = endsAt
        self.name = name; self.routineID = routineID
    }
    private enum CodingKeys: String, CodingKey { case id, domains, apps, createdAt, endsAt, name, routineID }
    // Policies saved before app blocking have no apps.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        domains = try values.decode([String].self, forKey: .domains)
        apps = try values.decodeIfPresent([BlockedApp].self, forKey: .apps) ?? []
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        endsAt = try values.decode(Date.self, forKey: .endsAt)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        routineID = try values.decodeIfPresent(UUID.self, forKey: .routineID)
    }
}
public struct Policy: Codable, Sendable {
    public var commitments: [Commitment] = []
    public var lastObserved: Date = .distantPast
    public var routines: [Routine] = []
    public var dailyLimits: [DailyLimit] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case commitments, lastObserved, routines, dailyLimits }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        commitments = try values.decode([Commitment].self, forKey: .commitments)
        lastObserved = try values.decodeIfPresent(Date.self, forKey: .lastObserved) ?? .distantPast
        routines = try values.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        dailyLimits = try values.decodeIfPresent([DailyLimit].self, forKey: .dailyLimits) ?? []
    }
    public func active(at date: Date) -> [Commitment] { commitments.filter { $0.endsAt > date } }
    public func blocks(_ domain: String, at date: Date) -> Bool {
        active(at: date).contains { $0.domains.contains { Domain.matches(domain, rule: $0) } }
            || dailyLimits.contains { $0.blockedUntil(at: date) != nil && Domain.matches(domain, rule: $0.domain) }
    }
    public func maintenanceDelay(at date: Date, retrying: Bool = false) -> TimeInterval? {
        let deadlines = active(at: date).map(\.endsAt) + routines.compactMap { $0.nextStart(after: date) }
            + dailyLimits.compactMap { $0.blockedUntil(at: date) }
        guard let deadline = deadlines.min() else { return retrying ? 60 : nil }
        return max(0.1, min(60, deadline.timeIntervalSince(date)))
    }
    public mutating func commit(_ input: [String], apps appInput: [BlockedApp] = [], minutes: Double, at date: Date, name: String? = nil, routineID: UUID? = nil) throws {
        guard minutes.isFinite, minutes >= 1, minutes <= 525_600 else { throw Failure("choose a duration between 1 minute and 365 days") }
        let domains = try Domain.normalized(input)
        let apps = try AppRule.normalized(appInput)
        guard !domains.isEmpty || !apps.isEmpty else { throw Failure("choose at least one website or app") }
        let current = active(at: date)
        let currentDomains = current.flatMap(\.domains)
        guard domains.count + currentDomains.count <= 500 else { throw Failure("you can commit up to 500 domains") }
        guard Set(domains + currentDomains + routines.flatMap(\.domains)).count <= 500 else {
            throw Failure("you can save up to 500 different websites")
        }
        let existing = Set(currentDomains), incoming = Set(domains)
        guard !domains.contains(where: { Domain.covered($0, by: existing) }),
              !currentDomains.contains(where: { Domain.covered($0, by: incoming) }) else { throw Failure("one of these websites is already blocked. choose other websites") }
        let currentApps = Set(current.flatMap(\.apps))
        if let repeated = apps.first(where: currentApps.contains) {
            throw Failure("\(repeated.name) is already blocked. choose other apps")
        }
        guard Set(apps + currentApps + routines.flatMap(\.apps)).count <= AppRule.maximumApps else {
            throw Failure("you can save up to \(AppRule.maximumApps) different apps")
        }
        if let name, name.count > 60 { throw Failure("keep the name under 60 characters") }
        commitments.append(Commitment(domains: domains, apps: apps, createdAt: date, endsAt: date.addingTimeInterval(minutes * 60), name: name, routineID: routineID))
        trimHistory(at: date)
        lastObserved = date
    }
    @discardableResult public mutating func trimHistory(at date: Date) -> Bool {
        let count = commitments.count
        let completed = commitments.filter { $0.endsAt <= date }.sorted { $0.endsAt > $1.endsAt }.prefix(200)
        commitments = Array(completed) + active(at: date)
        return commitments.count != count
    }
}
public struct DomainIndex: Sendable {
    private let deadlines: [String: Date]
    public init(policy: Policy, at date: Date = Date()) {
        let commitments = policy.commitments.flatMap { commitment in
            commitment.domains.map { ($0, commitment.endsAt) }
        }
        let limits = policy.dailyLimits.compactMap { limit in limit.blockedUntil(at: date).map { (limit.domain, $0) } }
        deadlines = Dictionary(commitments + limits, uniquingKeysWith: max)
    }
    public func blocks(_ domain: String, at date: Date) -> Bool {
        var suffix = domain[...]
        while !suffix.isEmpty {
            if let deadline = deadlines[String(suffix)], deadline > date { return true }
            guard let dot = suffix.firstIndex(of: ".") else { break }
            suffix = suffix[suffix.index(after: dot)...]
        }
        return false
    }
}
public struct Failure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public enum Domain {
    public static func parse(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme), url.user == nil, url.password == nil, let raw = url.host(percentEncoded: false) else { throw Failure("invalid website: \(input)") }
        var host = raw.hasSuffix(".") ? String(raw.dropLast()) : raw
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, host.utf8.count <= 253, !host.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }), parts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") && $0.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 } }) else { throw Failure("enter a domain such as x.com") }
        return host
    }
    public static func normalized(_ input: [String]) throws -> [String] {
        let all = Set(try input.map(parse))
        return all.filter { name in
            guard let dot = name.firstIndex(of: ".") else { return true }
            return !covered(String(name[name.index(after: dot)...]), by: all)
        }.sorted()
    }
    // Only complete label suffixes can cover a domain.
    static func covered(_ name: String, by rules: Set<String>) -> Bool {
        var suffix = name[...]
        while !suffix.isEmpty {
            if rules.contains(String(suffix)) { return true }
            guard let dot = suffix.firstIndex(of: ".") else { break }
            suffix = suffix[suffix.index(after: dot)...]
        }
        return false
    }
    public static func matches(_ name: String, rule: String) -> Bool { name == rule || name.hasSuffix("." + rule) }
}
public struct Request: Codable, Sendable {
    public let action: String
    public let domains: [String]?
    public let apps: [BlockedApp]?
    public let minutes: Double?
    public let name: String?
    public let routine: Routine?
    public let routineID: UUID?
    public let scheduledStart: Date?
    public let confirmedLongBlock: Bool?
    public let routineSync: RoutineSyncChange?
    public let limit: DailyLimit?
    public let usageSample: UsageSample?
    public init(action: String, domains: [String]? = nil, apps: [BlockedApp]? = nil, minutes: Double? = nil, name: String? = nil,
                routine: Routine? = nil, routineID: UUID? = nil, scheduledStart: Date? = nil,
                confirmedLongBlock: Bool? = nil, routineSync: RoutineSyncChange? = nil,
                limit: DailyLimit? = nil, usageSample: UsageSample? = nil) {
        self.action = action; self.domains = domains; self.apps = apps; self.minutes = minutes
        self.name = name; self.routine = routine; self.routineID = routineID
        self.scheduledStart = scheduledStart; self.confirmedLongBlock = confirmedLongBlock
        self.routineSync = routineSync
        self.limit = limit; self.usageSample = usageSample
    }
}
public struct Snapshot: Codable, Sendable {
    public let policy: Policy
    public let now: Date
    public let sandbox: Bool
    public let enforcementError: String?
    public let appActivity: AppActivity?
    public init(policy: Policy, now: Date, sandbox: Bool, enforcementError: String?, appActivity: AppActivity? = nil) {
        self.policy = policy; self.now = now; self.sandbox = sandbox; self.enforcementError = enforcementError
        self.appActivity = appActivity
    }
}
public struct ServiceReply: Codable, Sendable {
    public let data: Data?
    public let error: String?
    public init(data: Data? = nil, error: String? = nil) { self.data = data; self.error = error }
}
public enum ServiceName {
    public static let production = "dev.local.steadfast.service"
}
