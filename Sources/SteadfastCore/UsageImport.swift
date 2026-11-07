import Foundation

// Shared keys and summaries for Steadfast’s local app and website activity.

/// Seconds spent in one app or on one website over some span.
public struct UsageTotal: Codable, Equatable, Sendable, Identifiable {
    /// A lowercased bundle identifier for apps, a domain for websites.
    public let key: String
    public let seconds: Double
    public let isApp: Bool
    public var id: String { (isApp ? "app:" : "web:") + key }
    public init(key: String, seconds: Double, isApp: Bool) { self.key = key; self.seconds = seconds; self.isApp = isApp }
}

public enum UsageKeys {
    /// Second-level labels under which country domains register names: `bbc.co.uk`, `amazon.com.au`.
    static let registrySecondLevels: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or", "go", "gv", "nic"]

    /// The key a host is tallied under: the most specific known rule it falls under
    /// (so `news.ycombinator.com` stays itself), otherwise its registrable domain
    /// (`m.youtube.com` → `youtube.com`, `www.bbc.co.uk` → `bbc.co.uk`).
    public static func domain(_ host: String, known: [String] = []) -> String {
        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        if name.hasPrefix("www.") { name.removeFirst(4) }
        if let rule = known.filter({ Domain.matches(name, rule: $0) }).max(by: { $0.count < $1.count }) { return rule }
        let labels = name.split(separator: ".")
        guard labels.count > 2 else { return name }
        let keep = labels[labels.count - 1].count == 2 && registrySecondLevels.contains(String(labels[labels.count - 2])) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    /// Steadfast itself, the login window and the screen saver are never tallied.
    public static func isExcludedApp(_ bundleID: String) -> Bool {
        let key = bundleID.lowercased()
        return key == "dev.local.steadfast" || key.hasPrefix("dev.local.steadfast.")
            || key == "com.apple.loginwindow" || key.hasPrefix("com.apple.screensaver")
    }

    /// A bundle identifier that is plain data: letters, digits, dot, dash and underscore.
    public static func validBundleID(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = id.utf8.allSatisfy { (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }
        guard (1...255).contains(id.utf8.count), allowed, !id.hasPrefix("."), !id.hasSuffix("."), !id.contains("..") else { return nil }
        return id.lowercased()
    }
}

public enum UsageSummary {
    /// Seconds per app and per website across tallied days from `since` (a `yyyy-MM-dd` key) on.
    public static func totals(_ days: [UsageDay], since: String) -> [UsageTotal] {
        var apps: [String: Double] = [:]
        var domains: [String: Double] = [:]
        for day in days where day.day >= since {
            for (key, value) in day.apps { apps[key, default: 0] += value }
            for (key, value) in day.domains { domains[key, default: 0] += value }
        }
        let all = apps.map { UsageTotal(key: $0.key, seconds: $0.value, isApp: true) }
            + domains.map { UsageTotal(key: $0.key, seconds: $0.value, isApp: false) }
        return all.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
    }

    /// One estimate per sink with any time, in `TimeSink` order, as minutes per day.
    public static func estimates(_ seconds: [(sink: TimeSink?, seconds: Double)], days: Int, source: UsageSource) -> [TimeEstimate] {
        var bySink: [TimeSink: Double] = [:]
        for item in seconds { if let sink = item.sink, item.seconds > 0, item.seconds.isFinite { bySink[sink, default: 0] += item.seconds } }
        let span = Double(max(1, days))
        return TimeSink.allCases.compactMap { sink in
            bySink[sink].map { TimeEstimate(sink: sink, minutesPerDay: $0 / 60 / span, source: source) }
        }
    }

    /// The keys that count as distracting: whatever the person blocks, any recorded
    /// website under a blocked domain, and anything `classify` recognises.
    public static func distracting(keys: [(key: String, isApp: Bool)], blockedDomains: [String], blockedApps: [String],
                                   classify: (_ key: String, _ isApp: Bool) -> Bool) -> Set<String> {
        var result = Set(blockedDomains.map { $0.lowercased() } + blockedApps.map { $0.lowercased() })
        for item in keys {
            let key = item.key.lowercased()
            if result.contains(key) { continue }
            if !item.isApp, blockedDomains.contains(where: { Domain.matches(key, rule: $0.lowercased()) }) { result.insert(key); continue }
            if classify(key, item.isApp) { result.insert(key) }
        }
        return result
    }
}
