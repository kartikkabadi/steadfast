import AppKit
import ApplicationServices
import SteadfastCore

/// Steadfast's own private record of where foreground time goes on this Mac.
///
/// It notes which app is in front when that changes and every `tick` while the
/// Mac is in use (display awake, input in the last minute, not asleep,
/// locked or switched to another user), and adds the time between notes to the
/// app. With explicit website tracking and Accessibility access, browser time
/// is also credited to the active domain. Page contents and titles are not read.
/// Nothing runs while tracking is off.
final class ForegroundTally {
    static let tick: Duration = .seconds(5)
    /// A gap longer than this between notes means the Mac wasn't being watched (a
    /// missed sleep, a stalled run loop); that stretch is not counted.
    static let longestInterval: Double = 15

    private struct Mark {
        let pid: pid_t
        let bundleID: String
        let appName: String
        let browser: Bool
        var domain: String?
        var at: ContinuousClock.Instant
    }

    private weak var store: OutcomeStore?
    private var mark: Mark?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Task<Void, Never>?
    private var lookingUp = false
    private var generation = 0
    private var browserIDs = Set<String>()
    private var asleep = false, screensAsleep = false, locked = false, switchedOut = false
    private var paused: Bool { asleep || screensAsleep || locked || switchedOut }
    var running: Bool { timer != nil }

    init(store: OutcomeStore) { self.store = store }

    func start() {
        guard timer == nil else { return }
        if let website = URL(string: "https://example.com") {
            browserIDs = Set(NSWorkspace.shared.urlsForApplications(toOpen: website)
                .compactMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ act: @escaping @MainActor (ForegroundTally) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { act(self) } }
            }
            observers.append((center, token))
        }
        on(workspace, NSWorkspace.didActivateApplicationNotification) { $0.note(lookUp: true) }
        on(workspace, NSWorkspace.willSleepNotification) { $0.pause { $0.asleep = true } }
        on(workspace, NSWorkspace.didWakeNotification) { $0.resume { $0.asleep = false } }
        on(workspace, NSWorkspace.screensDidSleepNotification) { $0.pause { $0.screensAsleep = true } }
        on(workspace, NSWorkspace.screensDidWakeNotification) { $0.resume { $0.screensAsleep = false } }
        on(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.pause { $0.switchedOut = true } }
        on(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.resume { $0.switchedOut = false } }
        on(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.pause { $0.locked = true } }
        on(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.resume { $0.locked = false } }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.tick, tolerance: .seconds(5)) } catch { return }
                self?.note(lookUp: true)
            }
        }
        note(lookUp: true)
    }

    func stop() {
        flush()
        generation += 1
        timer?.cancel(); timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        mark = nil
        asleep = false; screensAsleep = false; locked = false; switchedOut = false
        store?.showing(app: nil, domain: nil)
    }

    /// Drop the current sample when history is erased or website tracking changes.
    func reset() {
        generation += 1
        mark = nil
        store?.showing(app: nil, domain: nil)
    }

    private func pause(_ change: (ForegroundTally) -> Void) {
        flush()
        generation += 1
        change(self)
        mark = nil
        store?.showing(app: nil, domain: nil)
    }

    private func resume(_ change: (ForegroundTally) -> Void) {
        change(self)
        note(lookUp: true)
    }

    /// Credits the time since the last note, then notes what is in front now.
    private func note(lookUp: Bool) {
        flush()
        guard !paused, ForegroundWebsite.isInUse, let app = NSWorkspace.shared.frontmostApplication, let raw = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = UsageKeys.validBundleID(raw), !UsageKeys.isExcludedApp(bundleID) else {
            mark = nil
            store?.showing(app: nil, domain: nil)
            return
        }
        let browser = AppPresets.category(bundleID: bundleID, declared: app.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }) == .browsers
            || ForegroundWebsite.isBrowser(bundleID) || browserIDs.contains(bundleID)
        let canReadWebsite = store?.websiteTrackingEnabled == true && AXIsProcessTrusted()
        let carried = canReadWebsite ? mark.flatMap { $0.pid == app.processIdentifier ? $0.domain : nil } : nil
        mark = Mark(pid: app.processIdentifier, bundleID: bundleID, appName: app.localizedName ?? bundleID,
                    browser: browser, domain: carried, at: .now)
        store?.showing(app: app.localizedName ?? bundleID, domain: carried)
        if lookUp, browser, store?.websiteTrackingEnabled == true { lookUpDomain(pid: app.processIdentifier) }
    }

    private func flush() {
        guard let current = mark, let store else { return }
        let now = ContinuousClock.now
        mark?.at = now
        let elapsed = current.at.duration(to: now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        guard seconds > 0, seconds <= Self.longestInterval, !paused, ForegroundWebsite.isInUse else { return }
        store.record(app: current.bundleID, domain: current.browser ? current.domain : nil,
                     seconds: seconds, appName: current.appName)
    }

    /// Reads the front browser window's domain off the main actor, only if
    /// Accessibility is already allowed. Never prompts.
    private func lookUpDomain(pid: pid_t) {
        guard !lookingUp, AXIsProcessTrusted() else { return }
        lookingUp = true
        let generation = generation
        Task { [weak self] in
            let host = await Task.detached(priority: .utility) { ForegroundWebsite.host(in: pid) }.value
            guard let self else { return }
            self.lookingUp = false
            guard self.generation == generation, self.store?.websiteTrackingEnabled == true,
                  let current = self.mark, current.pid == pid,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            let domain = host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
            if domain != current.domain {
                // The stretch before the address was read belongs to whatever was showing before.
                self.flush()
                self.mark?.domain = domain
            }
            self.store?.showing(app: current.appName, domain: domain, unreadable: domain == nil)
        }
    }
}
