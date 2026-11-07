import AppKit
import ApplicationServices
import Observation
import SteadfastCore

struct ActivitySession: Codable, Equatable, Identifiable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date
    let appID: String
    let appName: String
    let domain: String?
    var seconds: Double { endedAt.timeIntervalSince(startedAt) }
}

struct BlockReflection: Codable, Equatable, Identifiable {
    enum Answer: String, Codable { case helped, notHelpful, skipped }
    let id: UUID
    let answer: Answer
    let note: String?
}

/// The person's aim, their time estimates and Steadfast's own private tally.
/// Stored as one JSON file in the user's Application Support folder; nothing
/// leaves this Mac. The privileged service never sees any of it.
@Observable final class OutcomeStore {
    struct Saved: Codable {
        var aim: Aim?
        var estimates: [TimeEstimate] = []
        var trackingEnabled = true
        var websiteTrackingEnabled: Bool?
        var days: [UsageDay] = []
        var sessions: [ActivitySession]?
        var reflections: [BlockReflection]?
    }

    var aim: Aim? { didSet { save() } }
    var estimates: [TimeEstimate] = [] { didSet { save() } }
    /// Keep local activity by default. Website domains still require macOS access.
    var trackingEnabled = true {
        willSet { if !newValue, started { tally.stop() } }
        didSet { save(); trackingChanged() }
    }
    var websiteTrackingEnabled = true { didSet { tally.reset(); save() } }
    var activityEnabled: Bool {
        get { trackingEnabled }
        set {
            if newValue {
                websiteTrackingEnabled = true
                trackingEnabled = true
            } else {
                trackingEnabled = false
                websiteTrackingEnabled = false
            }
        }
    }
    private(set) var websiteAccessGranted = AXIsProcessTrusted()
    private(set) var currentApp: String?
    private(set) var currentDomain: String?
    private(set) var websiteUnreadable = false
    /// Most recent last; at most `retainedDays`.
    private(set) var days: [UsageDay] = []
    private(set) var sessions: [ActivitySession] = []
    private(set) var reflections: [BlockReflection] = []
    private(set) var saveError: String?

    static let retainedDays = 400
    private let url: URL?
    private var loading = true
    private var loadFailed = false
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var unsaved = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var terminating: NSObjectProtocol?
    @ObservationIgnored private lazy var tally = ForegroundTally(store: self)
    /// How often the tally is written to disk while it runs.
    static let saveInterval: TimeInterval = 60

    init(url: URL? = OutcomeStore.defaultURL) {
        self.url = url
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do {
                let saved = try JSONDecoder.outcomes.decode(Saved.self, from: Data(contentsOf: url))
                aim = saved.aim; estimates = saved.estimates.filter { $0.source != .legacyImport }; trackingEnabled = saved.trackingEnabled
                days = saved.days
                websiteTrackingEnabled = saved.websiteTrackingEnabled ?? saved.trackingEnabled
                sessions = saved.sessions ?? []
                reflections = saved.reflections ?? []
            } catch {
                loadFailed = true
                saveError = "Couldn't read your local choices. Your existing file has been left unchanged."
            }
        }
        loading = false
        if prune(at: Date()) { save() }
    }

    static var defaultURL: URL? {
        if let path = ProcessInfo.processInfo.environment["STEADFAST_ACTIVITY_FILE"] {
            return URL(filePath: path)
        }
        if ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"] != nil { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Steadfast", directoryHint: .isDirectory).appending(path: "outcomes.json")
    }

    func save() {
        guard !loading, !loadFailed, let url else { return }
        let saved = Saved(aim: aim, estimates: estimates, trackingEnabled: trackingEnabled,
                          websiteTrackingEnabled: websiteTrackingEnabled, days: days,
                          sessions: sessions, reflections: reflections)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try JSONEncoder.outcomes.encode(saved).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastSaved = Date(); unsaved = false
            saveError = nil
        } catch {
            saveError = "Couldn't save your local choices. Check that your disk has space and try again."
        }
    }

    func reflect(on block: UUID, answer: BlockReflection.Answer, note: String = "") {
        let previous = reflections
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        reflections.removeAll { $0.id == block }
        reflections.append(BlockReflection(id: block, answer: answer, note: text.isEmpty ? nil : text))
        if reflections.count > 200 { reflections.removeFirst(reflections.count - 200) }
        save()
        if saveError != nil { reflections = previous }
    }

    /// Deletes recorded activity; keeps the aim and estimates.
    func eraseTally() {
        tally.reset(); days = []; sessions = []; save()
    }

    /// Adds `seconds` of foreground time to today's tally.
    func record(app bundleID: String?, domain: String?, seconds: Double, at date: Date = Date(), appName: String? = nil) {
        guard trackingEnabled, seconds.isFinite, seconds > 0, seconds <= 120,
              let raw = bundleID, let bundleID = UsageKeys.validBundleID(raw), !UsageKeys.isExcludedApp(bundleID) else { return }
        let host = websiteTrackingEnabled ? domain.flatMap { try? Domain.parse($0) } : nil
        let begin = date.addingTimeInterval(-seconds)
        var cursor = begin
        while cursor < date {
            let end = min(date, Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: cursor)) ?? date)
            let key = Ledger.dayKey(cursor)
            if !days.contains(where: { $0.day == key }) { days.append(UsageDay(day: key)); days.sort { $0.day < $1.day } }
            if let index = days.firstIndex(where: { $0.day == key }) {
                let duration = end.timeIntervalSince(cursor)
                days[index].apps[bundleID, default: 0] += duration
                if let host { days[index].domains[host, default: 0] += duration }
            }
            cursor = end
        }
        if days.count > Self.retainedDays { days.removeFirst(days.count - Self.retainedDays) }
        let name = String((appName ?? AppCatalog.shared.app(for: bundleID)?.name ?? bundleID).prefix(100))
        if let last = sessions.last, last.appID == bundleID, last.domain == host,
           abs(last.endedAt.timeIntervalSince(begin)) < 2, Ledger.dayKey(last.startedAt) == Ledger.dayKey(date) {
            sessions[sessions.count - 1].endedAt = max(last.endedAt, date)
        } else {
            sessions.append(ActivitySession(startedAt: begin, endedAt: date, appID: bundleID, appName: name, domain: host))
        }
        _ = prune(at: date)
        unsaved = true
        if Date().timeIntervalSince(lastSaved) >= Self.saveInterval { save() }
    }

    /// Writes any tally not yet on disk.
    func saveIfNeeded() { if unsaved { save() } }

    @discardableResult private func prune(at date: Date) -> Bool {
        let before = (days.count, sessions.count)
        let firstDay = Calendar.current.date(byAdding: .day, value: -(Self.retainedDays - 1), to: date) ?? date
        days.removeAll { $0.day < Ledger.dayKey(firstDay) }
        let cutoff = date.addingTimeInterval(-30 * 86_400)
        sessions.removeAll { $0.endedAt < cutoff }
        if sessions.count > 20_000 { sessions.removeFirst(sessions.count - 20_000) }
        return before != (days.count, sessions.count)
    }

    func refreshWebsiteAccess() { websiteAccessGranted = AXIsProcessTrusted() }

    func requestWebsiteAccess() {
        websiteAccessGranted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func showing(app: String?, domain: String?, unreadable: Bool = false) {
        currentApp = app; currentDomain = domain; websiteUnreadable = unreadable
        refreshWebsiteAccess()
    }

    /// The distraction category a website belongs to, from the preset groups.
    static func sink(domain: String) -> TimeSink? {
        let host = domain.lowercased().hasPrefix("www.") ? String(domain.lowercased().dropFirst(4)) : domain.lowercased()
        for sink in TimeSink.allCases {
            let groups = Presets.groups.filter { sink.presetGroups.contains($0.name) }
            if groups.contains(where: { $0.domains.contains { Domain.matches(host, rule: $0) } }) { return sink }
        }
        return nil
    }

    /// The distraction category an app belongs to, from its catalogue category.
    /// Browsers, AI tools and other apps are not distractions by themselves.
    static func sink(app category: AppCategory) -> TimeSink? {
        switch category {
        case .chat: return .chat
        case .games: return .games
        case .media: return .video
        case .news: return .news
        case .browsers, .ai, .other: return nil
        }
    }

    /// Starts or stops the foreground tally to match `trackingEnabled`.
    func trackingChanged() {
        guard started else { return }
        if trackingEnabled { tally.start() } else { tally.stop(); saveIfNeeded() }
    }

    /// Begins tracking if enabled. Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true
        terminating = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.tally.running { self.tally.stop() }
                self.saveIfNeeded()
            }
        }
        trackingChanged()
    }

    // MARK: - Figures for the outcome screens

    /// Every website in the preset groups, used to key tallied domains.
    static let knownDomains: [String] = Presets.groups.flatMap(\.domains)

    /// An app's catalogue category, from the installed-app scan when it has run.
    static func category(bundleID: String) -> AppCategory {
        AppCatalog.shared.app(for: bundleID)?.category ?? AppPresets.category(bundleID: bundleID, declared: nil)
    }

    /// Lowercased bundle identifiers and domains that count as distractions: what
    /// the person blocks now or blocked before, plus anything a preset group or app
    /// category marks as one, among the keys that appear in the local activity record.
    func distractingKeys(model: Model) -> Set<String> {
        let blocks = model.active + model.history.filter { !model.isBrowserCheck($0) }
        var keys: [(key: String, isApp: Bool)] = []
        var seen = Set<String>()
        func add(_ key: String, _ isApp: Bool) { if seen.insert((isApp ? "a:" : "w:") + key).inserted { keys.append((key, isApp)) } }
        for day in days {
            for key in day.apps.keys { add(key, true) }
            for key in day.domains.keys { add(key, false) }
        }
        return UsageSummary.distracting(keys: keys, blockedDomains: blocks.flatMap(\.domains), blockedApps: blocks.flatMap(\.apps).map(\.key)) { key, isApp in
            isApp ? Self.sink(app: Self.category(bundleID: key)) != nil : Self.sink(domain: key) != nil
        }
    }

    /// Recorded time on chosen or classified distractions, once enough days exist.
    func dailyFigure(model: Model) -> (minutes: Double, source: UsageSource)? {
        Ledger.dailyMinutes(estimates: estimates.filter { $0.source != .legacyImport }, measuredDays: days,
                            distracting: distractingKeys(model: model))
    }

    /// Local days with any tallied time.
    var talliedDays: Int { days.filter { $0.total > 0 }.count }

    /// Everything tallied in the last seven days, longest first.
    func recentTotals(now: Date = Date()) -> [UsageTotal] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
        return UsageSummary.totals(days, since: Ledger.dayKey(start))
    }

    /// A name to show for a tallied key: the app's own name when known, otherwise the key.
    func name(for total: UsageTotal) -> String {
        guard total.isApp else { return total.key }
        return AppCatalog.shared.app(for: total.key)?.name
            ?? sessions.last(where: { $0.appID == total.key })?.appName ?? total.key
    }
}

extension JSONEncoder {
    static let outcomes: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let outcomes: JSONDecoder = {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
