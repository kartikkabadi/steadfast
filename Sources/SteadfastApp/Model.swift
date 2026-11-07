import Foundation
import AppKit
import Observation
import SteadfastCore

enum Panel: String, Identifiable {
    case websites, apps, commitment, routine, settings, browserCheck, dailyLimits, onboarding
    var id: String { rawValue }
}
enum AppPage: String, CaseIterable {
    case block, routines, history

    var title: String {
        switch self {
        case .block: return "Today"
        case .routines: return "Routines"
        case .history: return "Progress"
        }
    }
}

struct AppUnlock: Identifiable {
    let app: BlockedApp
    let end: Date
    var id: String { app.key }
}

/// "2 websites · 1 app", leaving out whichever is empty.
enum TargetLabel {
    static func text(websites: Int, apps: Int) -> String {
        var parts: [String] = []
        if websites > 0 { parts.append("\(websites) \(websites == 1 ? "website" : "websites")") }
        if apps > 0 { parts.append("\(apps) \(apps == 1 ? "app" : "apps")") }
        return parts.isEmpty ? "nothing selected" : parts.joined(separator: " · ")
    }
}

struct WebsiteUnlock: Identifiable {
    let domain: String
    let end: Date
    let dailyLimitReached: Bool
    var id: String { domain }
}

extension Commitment {
    var displayName: String {
        // The one-minute browser test is recorded under a fixed lowercase name.
        if name == "browser check", domains == [Model.browserCheckDomain], apps.isEmpty { return "Browser test" }
        if let name { return name }
        let names = domains + apps.map(\.name)
        guard let first = names.first else { return "block" }
        return names.count == 1 ? first : "\(first) + \(names.count - 1) more"
    }

    var targetLabel: String { TargetLabel.text(websites: domains.count, apps: apps.count) }
    /// Websites then apps, for a one-line list.
    var targetList: String { (domains + apps.map(\.name)).joined(separator: ", ") }

    var durationMinutes: Double { min(525_600, max(1, endsAt.timeIntervalSince(createdAt) / 60)) }
}

@Observable final class Model {
    static let browserCheckDomain = "example.com"
    var page = AppPage.block
    var editingRoutine: Routine?
    var routineSeed: Routine?
    private(set) var favoriteIDs = UserDefaults.standard.stringArray(forKey: "favoriteRoutineIDs") ?? []
    var draftName: String?
    var draftPurpose: String {
        get { draftName ?? "" }
        set {
            let value = String(newValue.prefix(60))
            draftName = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            draftRoutineID = nil
        }
    }
    var draftRoutineID: UUID?
    var snapshot: Snapshot? { didSet { scheduleWake() } }
    /// Bumped when a deadline passes, so anything reading `currentTime` redraws
    /// even if the service had nothing new to say.
    private var tick = 0
    @ObservationIgnored private var wake: Task<Void, Never>?
    var error: String?
    var setupError: String?
    let routineSync = RoutineSync()
    var progressActivity = false
    let websiteUsage = WebsiteUsage()
    let outcomes: OutcomeStore
    var availableUpdate: String?
    var updateStatus: String?
    var checkingForUpdate = false
    private var lastUpdateCheck: Date?
    var connectionError: String?
    var busy = false
    var connected = false
    var connecting = true
    var installationNeedsUpdate = Model.needsInstalledUpdate()
    private var refreshing = false
    private var refreshAgain = false
    var panel: Panel?
    /// The tour page to open on (`OnboardingView.Page` raw value); nil starts at the beginning.
    var onboardingStep: Int?
    var composing = false
    var editingReview = false
    var text = ""
    var amountText = "1"
    var multiplier = 60.0
    var chosen = Set<String>()
    var chosenApps = Set<BlockedApp>()
    var reviewedDomains: [String] = []
    var reviewedApps: [BlockedApp] = []
    var search = ""
    var category = "all websites"
    var success: String?
    private var draftCommitted = false
    private var previousDraft: Draft?
    var canEditReview: Bool { previousDraft != nil }
    var searchRequested = 0
    var amount: Double {
        get { Double(amountText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")) ?? .nan }
        set { amountText = newValue.formatted(.number.grouping(.never).precision(.fractionLength(0...6))) }
    }
    init(outcomes: OutcomeStore = OutcomeStore()) { self.outcomes = outcomes }
    var minutes: Double { amount * multiplier }
    var currentTime: Date { _ = tick; return max(Date(), snapshot?.now ?? .distantPast) }
    var active: [Commitment] { snapshot.map { $0.policy.active(at: currentTime) } ?? [] }
    var routines: [Routine] { snapshot?.policy.routines ?? [] }
    var dailyLimits: [DailyLimit] { snapshot?.policy.dailyLimits ?? [] }
    var hasExhaustedLimit: Bool { dailyLimits.contains { $0.blockedUntil(at: currentTime) != nil } }
    var history: [Commitment] {
        guard let snapshot else { return [] }
        return snapshot.policy.commitments.filter { $0.endsAt <= currentTime }.sorted { $0.endsAt > $1.endsAt }
    }
    // Older versions recorded browser diagnostics as ordinary commitments.
    var lastBlock: Commitment? { history.first { !isBrowserCheck($0) } }
    var favorites: [Routine] {
        favoriteIDs.compactMap { id in routines.first { $0.id.uuidString == id } }
    }
    var nextRun: (name: String, start: Date)? {
        let now = currentTime
        return routines.compactMap { routine in
            routine.nextStart(after: now).map { (routine.name, $0) }
        }.min { $0.1 < $1.1 }
    }
    var websiteUnlocks: [WebsiteUnlock] {
        guard snapshot != nil else { return [] }
        var deadlines: [String: Date] = [:]
        for block in active {
            for domain in block.domains {
                deadlines[domain] = max(deadlines[domain] ?? .distantPast, block.endsAt)
            }
        }
        var reachedLimits = Set<String>()
        for limit in dailyLimits {
            if let end = limit.blockedUntil(at: currentTime) {
                reachedLimits.insert(limit.domain)
                deadlines[limit.domain] = max(deadlines[limit.domain] ?? .distantPast, end)
            }
        }
        return deadlines.map { domain, end in
            var latest = end
            var parent = domain[...]
            while let dot = parent.firstIndex(of: ".") {
                parent = parent[parent.index(after: dot)...]
                if let end = deadlines[String(parent)] { latest = max(latest, end) }
            }
            return WebsiteUnlock(domain: domain, end: latest, dailyLimitReached: reachedLimits.contains(domain))
        }.sorted { $0.end == $1.end ? $0.domain < $1.domain : $0.end < $1.end }
    }
    var appUnlocks: [AppUnlock] {
        guard let snapshot else { return [] }
        return snapshot.policy.blockedApps(at: currentTime).values.map { AppUnlock(app: $0.app, end: $0.until) }
            .sorted { $0.end == $1.end ? $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending : $0.end < $1.end }
    }
    var hasActiveBlocks: Bool { !websiteUnlocks.isEmpty || !appUnlocks.isEmpty }
    var blockedAppKeys: Set<String> { Set(active.flatMap(\.apps).map(\.key)) }
    var hasDraftTargets: Bool { !chosen.isEmpty || !chosenApps.isEmpty }
    func isBrowserCheck(_ item: Commitment) -> Bool {
        item.routineID == nil && item.name == "browser check" && item.domains == [Self.browserCheckDomain]
            && item.endsAt.timeIntervalSince(item.createdAt) == 60
    }
    func isFavorite(_ routine: Routine) -> Bool { favoriteIDs.contains(routine.id.uuidString) }
    func toggleFavorite(_ routine: Routine) {
        let id = routine.id.uuidString
        if isFavorite(routine) { favoriteIDs.removeAll { $0 == id } }
        else { favoriteIDs.append(id) }
        UserDefaults.standard.set(favoriteIDs, forKey: "favoriteRoutineIDs")
    }
    var isWebsiteSearch: Bool {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard panel == .websites, !query.isEmpty, (try? Domain.normalized([query])) == nil else { return false }
        return Presets.searchableDomains.contains { Presets.matches($0, query: query) }
    }
    var hasSelection: Bool { !chosen.isEmpty || !chosenApps.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWebsiteSearch }
    var selectionLabel: String {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "finish choosing websites" }
        return chosen.isEmpty ? "choose websites" : "\(chosen.count) \(chosen.count == 1 ? "website" : "websites") selected"
    }
    var selectionSummary: String {
        let pending = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ((pending.isEmpty ? [] : ["draft: \(pending)"]) + chosen.sorted()).joined(separator: ", ")
    }
    var service: String { ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"] ?? ServiceName.production }
    var installationExists: Bool { FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/dev.local.steadfastd") }
    var serviceReady: Bool { connected && !installationNeedsUpdate && snapshot?.enforcementError == nil }
    var needsBlockingSetup: Bool { snapshot == nil && !installationExists && !connected }
    var statusLabel: String {
        if connecting { return "Connecting…" }
        if installationNeedsUpdate { return "Update required" }
        if !connected { return installationExists ? "Protection status unavailable" : "Background service is not installed" }
        if snapshot?.enforcementError != nil { return "Protection needs attention" }
        if snapshot?.sandbox == true { return "Preview · system DNS unchanged" }
        return active.isEmpty ? "Ready to block" : "Background protection is running"
    }
    func refresh(showProgress: Bool = false) async {
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        installationNeedsUpdate = Self.needsInstalledUpdate()
        if showProgress { connecting = true }
        defer { connecting = false; refreshing = false }
        guard !installationNeedsUpdate else {
            connected = false; connectionError = nil
            return
        }
        repeat {
            refreshAgain = false
            let previous = snapshot?.now
            do {
                let result = try await Client.send(Request(action: "status"), service: service)
                if !active.isEmpty, result.policy.active(at: result.now).isEmpty, result.enforcementError == nil {
                    success = "all timed blocks finished"
                }
                if result.now >= (snapshot?.now ?? .distantPast) { snapshot = result }
                connected = true; connectionError = nil
                if result.enforcementError == nil {
                    routineSync.start(for: self)
                    websiteUsage.start(for: self)
                }
            } catch {
                if snapshot?.now == previous { connected = false; connectionError = error.localizedDescription }
            }
        } while refreshAgain && !Task.isCancelled
    }

    /// Wakes at the next moment the screen changes on its own — a block ending, a
    /// daily limit resetting, a routine starting — and asks the service what is true.
    private func scheduleWake() {
        wake?.cancel(); wake = nil
        guard let policy = snapshot?.policy else { return }
        let now = currentTime
        let deadlines = policy.active(at: now).map(\.endsAt)
            + policy.dailyLimits.compactMap { $0.blockedUntil(at: now) }
            + policy.routines.compactMap { $0.nextStart(after: now) }
        guard let next = deadlines.filter({ $0 > now }).min() else { return }
        wake = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(next.timeIntervalSince(now) + 1)) } catch { return }
            guard let self else { return }
            self.tick &+= 1
            await self.refresh()
        }
    }

    private static func needsInstalledUpdate() -> Bool {
        guard ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"] == nil,
              FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/dev.local.steadfastd"),
              let executable = Bundle.main.executableURL else { return false }
        let installed = "/Applications/Steadfast.app/Contents/MacOS/Steadfast"
        guard executable.path != installed else { return false }
        return !FileManager.default.contentsEqual(atPath: executable.path, andPath: installed)
    }

    func serviceDisconnected() {
        // A clean service with no active rules exits normally until the next request.
        if connected, let snapshot, snapshot.enforcementError == nil,
           snapshot.policy.active(at: snapshot.now).isEmpty, !hasExhaustedLimit { return }
        connected = false
        connecting = false
        connectionError = "the background service disconnected"
    }
    func startDraft() {
        guard !busy, panel == nil else { return }
        clearCompletedDraft()
        error = nil; success = nil; composing = true; page = .block
    }
    func openComposer() {
        guard !busy, panel == nil else { return }
        clearCompletedDraft()
        composing = true
        error = nil; page = .block
        panel = .websites
    }
    func openAppPicker() {
        guard !busy, panel == nil else { return }
        clearCompletedDraft()
        composing = true
        error = nil; page = .block
        AppCatalog.shared.load()
        panel = .apps
    }
    @discardableResult func reviewDraft() -> Bool {
        if isWebsiteSearch { text = "" }
        guard !busy, validateSites(), validateDuration() else { return false }
        if let id = draftRoutineID, !routines.contains(where: {
            $0.id == id && $0.name == draftName && Set($0.domains) == Set(reviewedDomains)
                && Set($0.apps) == Set(reviewedApps) && $0.minutes == minutes
        }) { draftRoutineID = nil }
        success = nil; panel = .commitment
        return true
    }
    func dismissPanel() {
        if panel == .websites { text = "" }
        closeComposer()
    }
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }
    /// Ends the first-run tour. Starting a first block opens the usual review sheet.
    func completeOnboarding(startFirstBlock: Bool = false) {
        hasCompletedOnboarding = true
        onboardingStep = nil
        dismissPanel()
        composing = hasDraftTargets
        if startFirstBlock, hasDraftTargets, serviceReady {
            _ = reviewDraft()
        }
    }
    func closeComposer() {
        guard !busy else { return }
        if let previousDraft {
            restore(previousDraft)
            self.previousDraft = nil
        }
        error = nil; panel = nil
    }
    func editReviewedDraft() {
        guard !busy, canEditReview, panel == .commitment else { return }
        previousDraft = nil
        editingReview = true
        composing = true; page = .block; panel = nil
    }
    private func typedDomains() throws -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        return try Domain.normalized(text.components(separatedBy: separators).filter { !$0.isEmpty })
    }
    func domains() throws -> [String] { try Domain.normalized(typedDomains() + chosen.sorted()) }
    @discardableResult func addCustomSites() -> Bool {
        do {
            let added = try typedDomains()
            guard !added.isEmpty else { throw Failure("enter a website such as x.com") }
            var policy = snapshot?.policy ?? Policy()
            try policy.commit(try Domain.normalized(chosen.sorted() + added), minutes: 1, at: currentTime)
            chosen.formUnion(added); text = ""; error = nil; search = ""
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func clearSelection() {
        chosen = []; chosenApps = []; text = ""; reviewedDomains = []; reviewedApps = []; error = nil
        draftName = nil; draftRoutineID = nil
    }
    func newRoutine(seed: Routine? = nil) {
        guard !busy, panel == nil else { return }
        editingRoutine = nil; routineSeed = seed; error = nil; panel = .routine
    }
    func editRoutine(_ routine: Routine) {
        guard !busy, panel == nil else { return }
        editingRoutine = routine; routineSeed = nil; error = nil; panel = .routine
    }
    func duplicateRoutine(_ routine: Routine) {
        let base = String(routine.name.prefix(55))
        var name = base + " copy"
        var number = 2
        while routines.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            let suffix = " copy \(number)"
            name = String(base.prefix(60 - suffix.count)) + suffix
            number += 1
        }
        newRoutine(seed: Routine(name: name, domains: routine.domains, apps: routine.apps, minutes: routine.minutes))
    }
    func saveAsRoutine(_ item: Commitment) {
        newRoutine(seed: Routine(name: "", domains: item.domains, apps: item.apps, minutes: item.durationMinutes))
    }
    func prepareRoutine(_ routine: Routine) {
        prepareReview(domains: routine.domains, apps: routine.apps, minutes: routine.minutes, name: routine.name, routineID: routine.id)
    }
    func reuseBlock(_ item: Commitment) {
        prepareReview(domains: item.domains, apps: item.apps, minutes: item.durationMinutes, name: item.name)
    }
    private func prepareReview(domains: [String], apps: [BlockedApp], minutes: Double, name: String? = nil, routineID: UUID? = nil) {
        guard !busy, serviceReady, panel == nil else { return }
        clearCompletedDraft()
        let original = Draft(model: self)
        chosen = Set(domains); chosenApps = Set(apps); text = ""; reviewedDomains = []; reviewedApps = []
        setDuration(minutes)
        draftName = name; draftRoutineID = routineID
        if reviewDraft() {
            previousDraft = original
        } else {
            restore(original)
        }
    }
    func setDuration(_ minutes: Double) {
        if minutes >= 1440 && minutes.truncatingRemainder(dividingBy: 1440) == 0 { multiplier = 1440 }
        else { multiplier = minutes >= 60 && minutes.truncatingRemainder(dividingBy: 60) == 0 ? 60 : 1 }
        amount = minutes / multiplier
    }
    private func restore(_ draft: Draft) {
        chosen = draft.chosen; chosenApps = draft.chosenApps; text = draft.text
        reviewedDomains = draft.reviewedDomains; reviewedApps = draft.reviewedApps
        amountText = draft.amountText; multiplier = draft.multiplier
        draftName = draft.name; draftRoutineID = draft.routineID
    }
    private struct Draft {
        let chosen: Set<String>
        let chosenApps: Set<BlockedApp>
        let text: String
        let reviewedDomains: [String]
        let reviewedApps: [BlockedApp]
        let amountText: String
        let multiplier: Double
        let name: String?
        let routineID: UUID?
        init(model: Model) {
            chosen = model.chosen; chosenApps = model.chosenApps; text = model.text
            reviewedDomains = model.reviewedDomains; reviewedApps = model.reviewedApps
            amountText = model.amountText; multiplier = model.multiplier
            name = model.draftName; routineID = model.draftRoutineID
        }
    }
    func saveRoutine(_ routine: Routine) async -> Bool {
        await changePolicy(Request(action: "save-routine", routine: routine))
    }
    func changeDailyLimit(_ limit: DailyLimit, deleting: Bool = false) async -> Bool {
        guard await changePolicy(Request(action: deleting ? "delete-limit" : "save-limit", limit: limit)) else { return false }
        websiteUsage.start(for: self)
        return true
    }
    func deleteRoutine(_ routine: Routine) async -> Bool {
        guard await changePolicy(Request(action: "delete-routine", routineID: routine.id)) else { return false }
        if isFavorite(routine) { toggleFavorite(routine) }
        return true
    }
    func setSchedule(_ routine: Routine, enabled: Bool) async {
        var updated = routine
        updated.schedule?.enabled = enabled
        _ = await saveRoutine(updated)
    }
    func setSkippedRun(_ routine: Routine, start: Date, skip: Bool) async {
        _ = await changePolicy(Request(action: skip ? "skip-run" : "restore-run", routineID: routine.id, scheduledStart: start))
    }
    private func changePolicy(_ request: Request) async -> Bool {
        guard !busy, serviceReady else { error = "connect to the background service and try again"; return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await Client.send(request, service: service)
            if result.now >= (snapshot?.now ?? .distantPast) { snapshot = result }
            connected = true
            return true
        } catch {
            if let status = try? await Client.send(Request(action: "status"), service: service) {
                if status.now >= (snapshot?.now ?? .distantPast) { snapshot = status }
                connected = true; connectionError = nil
                if request.action == "delete-routine", !status.policy.routines.contains(where: { $0.id == request.routineID }) { return true }
                if let limit = request.limit, let domain = try? Domain.parse(limit.domain) {
                    let saved = status.policy.dailyLimits.first { $0.domain == domain }
                    if request.action == "delete-limit", saved == nil { return true }
                    if request.action == "save-limit", saved?.minutes == limit.minutes { return true }
                }
                if let id = request.routineID, let start = request.scheduledStart,
                   let routine = status.policy.routines.first(where: { $0.id == id }) {
                    if request.action == "skip-run", routine.skippedStart == start { return true }
                    if request.action == "restore-run", routine.skippedStart != start { return true }
                }
                if let wanted = request.routine, let saved = status.policy.routines.first(where: { $0.id == wanted.id }),
                   saved.name == wanted.name, saved.domains == wanted.domains, Set(saved.apps) == Set(wanted.apps),
                   saved.minutes == wanted.minutes, saved.schedule == wanted.schedule { return true }
            } else {
                connected = false
                connectionError = "could not confirm whether the change was saved. reconnect and check before trying again."
            }
            self.error = "couldn't save the change. \(error.localizedDescription)"
            return false
        }
    }
    func validateSites() -> Bool {
        do {
            let domains = try domains()
            let apps = try AppRule.normalized(Array(chosenApps))
            var policy = snapshot?.policy ?? Policy()
            try policy.commit(domains, apps: apps, minutes: 1, at: currentTime)
            reviewedDomains = domains; reviewedApps = apps
            chosen = Set(domains); chosenApps = Set(apps); text = ""; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func validateDuration() -> Bool {
        guard !amount.isNaN else { error = "enter a number for the duration."; return false }
        do {
            var policy = snapshot?.policy ?? Policy()
            try policy.commit(reviewedDomains, apps: reviewedApps, minutes: minutes, at: currentTime)
            error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func commit(confirmedLongBlock: Bool = false) async {
        guard !busy, serviceReady, validateDuration() else { return }
        let domains = reviewedDomains, apps = reviewedApps, duration = minutes, startedAt = currentTime
        busy = true
        defer { busy = false }
        do {
            let result = try await Client.send(Request(action: "commit", domains: domains, apps: apps.isEmpty ? nil : apps, minutes: duration,
                                                     name: draftName, routineID: draftRoutineID, confirmedLongBlock: confirmedLongBlock), service: service)
            finishCommit(result)
        } catch {
            // A lost reply does not mean the service failed to save the commitment.
            if let status = try? await Client.send(Request(action: "status"), service: service) {
                if status.now >= (snapshot?.now ?? .distantPast) { snapshot = status }
                connected = true; connectionError = nil
                if reconcileCommit(status, domains: domains, apps: apps, minutes: duration, since: startedAt) { return }
            } else {
                connected = false
                connectionError = "could not confirm whether the block started. reconnect before trying again."
            }
            self.error = error.localizedDescription
        }
    }
    @discardableResult func reconcileCommit(_ result: Snapshot, domains: [String], apps: [BlockedApp] = [], minutes: Double, since: Date) -> Bool {
        guard result.policy.commitments.contains(where: {
            $0.domains == domains && Set($0.apps) == Set(apps) && $0.createdAt >= since && $0.endsAt == $0.createdAt.addingTimeInterval(minutes * 60)
        }) else { return false }
        finishCommit(result)
        return true
    }
    private func finishCommit(_ result: Snapshot) {
        snapshot = result; connected = true; connectionError = nil
        if let previousDraft {
            restore(previousDraft)
            self.previousDraft = nil
        } else { draftCommitted = true }
        page = .block; panel = nil; composing = false; error = nil
        success = result.enforcementError == nil ? "block started." : nil
    }
    func clearCompletedDraft() {
        guard draftCommitted, panel != .commitment else { return }
        chosen = []; chosenApps = []; text = ""; reviewedDomains = []; reviewedApps = []; search = ""
        draftName = nil; draftRoutineID = nil
        amount = 1; multiplier = 60; draftCommitted = false
    }
    func startBrowserCheck() async throws -> Date {
        guard !busy, serviceReady, snapshot?.sandbox == false else {
            throw Failure("reconnect to blocking and try again.")
        }
        let domain = Self.browserCheckDomain
        guard !active.flatMap(\.domains).contains(where: { Domain.matches(domain, rule: $0) }) else {
            throw Failure("example.com is already blocked. try again after that block ends.")
        }
        busy = true
        defer { busy = false }
        let startedAt = currentTime
        let request = Request(action: "commit", domains: [domain], minutes: 1, name: "browser check")
        let result: Snapshot
        do {
            result = try await Client.send(request, service: service)
        } catch {
            guard let status = try? await Client.send(Request(action: "status"), service: service) else {
                throw Failure("couldn't confirm the test started. check the connection before trying again.")
            }
            result = status
        }
        if result.now >= (snapshot?.now ?? .distantPast) { snapshot = result }
        guard result.enforcementError == nil,
              let check = result.policy.active(at: result.now).first(where: {
                  $0.domains == [domain] && $0.name == "browser check" && $0.createdAt >= startedAt
              }) else {
            throw Failure("couldn't start the test. check blocking status and try again.")
        }
        return check.endsAt
    }

    func install() {
        guard !CommandLine.arguments.contains("--preview") else {
            setupError = "The preview uses a disposable service. Quit it and run scripts/preview.sh again."
            return
        }
        if Bundle.main.bundleURL.path != "/Applications/Steadfast.app" {
            openSetupScript("Install")
            return
        }
        openSetupScript("Update", quitAfterOpening: true)
    }

    @MainActor func checkForUpdate(manual: Bool = false) async {
        guard Bundle.main.bundleURL.path == "/Applications/Steadfast.app", !checkingForUpdate,
              manual || lastUpdateCheck.map({ Date().timeIntervalSince($0) >= 86_400 }) ?? true,
              let site = Bundle.main.object(forInfoDictionaryKey: "SteadfastSiteURL") as? String,
              let origin = URL(string: site), origin.scheme == "https",
              let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let current = ReleaseInfo.versionNumbers(installed) else { return }
        checkingForUpdate = true
        defer { checkingForUpdate = false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpShouldSetCookies = false
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let url = origin.appending(path: "latest.json")
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let final = http.url, final.scheme == "https",
                  final.host == "release-assets.githubusercontent.com" || final == url,
                  data.count <= 4096 else { throw Failure("invalid release response") }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            guard let available = ReleaseInfo.versionNumbers(release.version),
                  release.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
                throw Failure("invalid release information")
            }
            availableUpdate = current.lexicographicallyPrecedes(available) ? release.version : nil
            updateStatus = manual && availableUpdate == nil ? "you’re up to date" : nil
        } catch {
            guard !Task.isCancelled else { return }
            if manual { updateStatus = "couldn’t check for updates. try again." }
        }
        lastUpdateCheck = Date()
    }

    func uninstall() { openSetupScript("Uninstall") }
    private func openSetupScript(_ name: String, quitAfterOpening: Bool = false) {
        guard !CommandLine.arguments.contains("--preview") else {
            setupError = "Install and uninstall are unavailable in the preview."
            return
        }
        setupError = nil
        guard let script = Bundle.main.url(forResource: name, withExtension: "command") else {
            setupError = "open \(name).command in the distribution folder."; return
        }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { setupError = "open \(name).command with Terminal."; return }
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, failure in
            Task { @MainActor in
                if let failure { self.setupError = failure.localizedDescription }
                else if quitAfterOpening { NSApp.terminate(nil) }
            }
        }
    }
    var durationLabel: String {
        DurationLabel.text(minutes)
    }
    var siteCountLabel: String { "\(reviewedDomains.count) \(reviewedDomains.count == 1 ? "website" : "websites")" }
    var reviewedTargetLabel: String { TargetLabel.text(websites: reviewedDomains.count, apps: reviewedApps.count) }
    var draftTargetLabel: String { TargetLabel.text(websites: chosen.count, apps: chosenApps.count) }
}

private struct ReleaseInfo: Decodable {
    let version: String
    let sha256: String

    static func versionNumbers(_ version: String) -> [Int]? {
        guard version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        let numbers = version.split(separator: ".").compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
}
