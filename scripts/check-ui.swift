import AppKit
import SwiftUI
import SteadfastCore

@main struct CheckUI {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        let interactive = arguments.contains("--interactive")
        func option(_ name: String, fallback: String) -> String {
            guard let index = arguments.firstIndex(of: name), arguments.count > index + 1 else { return fallback }
            return arguments[index + 1]
        }
        let service = ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"] ?? ""
        precondition(service.hasPrefix("dev.local.steadfast.test."), "UI checks require an isolated test service")
        let output = URL(fileURLWithPath: option("--output", fallback: NSTemporaryDirectory() + "steadfast-ui.png"))
        let state = option("--state", fallback: "empty")
        let browserStage: BrowserCheckSheet.Stage? = switch state {
        case "browser-check-ready", "browser-check-error": .ready
        case "browser-check-running": .running(.now.addingTimeInterval(60))
        case "browser-check-blocked": .blocked
        case "browser-check-loaded": .loaded
        case "browser-check-expired": .expired
        default: nil
        }
        let width = Double(option("--width", fallback: "900")) ?? 900
        let height = Double(option("--height", fallback: "720")) ?? 720
        let model = Model()
        model.hasCompletedOnboarding = !state.hasPrefix("onboarding")
        model.panel = nil
        model.connecting = false
        model.installationNeedsUpdate = state == "update"
        model.connected = state != "offline" && state != "active-offline" && state != "onboarding-install"
        var policy = Policy()
        let libraryStates = ["routines", "routine-editor", "history"]
        if libraryStates.contains(state) {
            var routine = Routine(name: "morning focus", domains: ["youtube.com", "x.com"], minutes: 60,
                                  schedule: WeeklySchedule(weekdays: [2, 3, 4, 5, 6], startMinute: 540))
            try policy.saveRoutine(routine, at: Date())
            routine = Routine(name: "reading", domains: ["reddit.com", "news.ycombinator.com"], minutes: 30)
            try policy.saveRoutine(routine, at: Date())
            try policy.commit(["youtube.com"], minutes: 30, at: Date().addingTimeInterval(-7200), name: "morning focus")
        }
        let sampleApps = [BlockedApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
                          BlockedApp(bundleID: "com.spotify.client", name: "Spotify"),
                          BlockedApp(bundleID: "com.apple.games", name: "Games")]
        if state.hasPrefix("active") {
            try policy.commit(["x.com", "twitter.com", "instagram.com"], apps: state == "active-apps" ? sampleApps : [], minutes: 30, at: Date())
        }
        if state == "active-apps-only" {
            policy = Policy()
            try policy.commit([], apps: sampleApps, minutes: 90, at: Date())
        }
        if state == "active-many" {
            try policy.commit(["youtube.com"], minutes: 60, at: Date())
            try policy.commit(["reddit.com"], minutes: 240, at: Date())
        }
        if state == "active-browser-check" || state == "browser-check-running" {
            policy = Policy()
            try policy.commit(["example.com"], minutes: 1, at: Date(), name: "browser check")
        }
        // Outcome fixtures: a realistic aim and about two months of varied history.
        let aimStates = ["ring-day", "ring-deadline", "progress", "progress-empty", "active-aim", "empty-aim", "notice-blocked-aim", "notice-blocked-cost"]
        if aimStates.contains(state) {
            let calendar = Calendar.current
            let year = calendar.component(.year, from: Date())
            model.outcomes.aim = Aim(title: "Ship my app", kind: .build,
                                     cost: state == "notice-blocked-aim" ? nil : "Another year of telling people it's nearly done.",
                                     deadline: calendar.date(from: DateComponents(year: year, month: 12, day: 19)))
        }
        if ["progress", "progress-noaim", "active-aim", "ring-day", "ring-deadline"].contains(state) {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            var seed: UInt64 = 0x5eed
            func next(_ bound: Int) -> Int {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Int((seed >> 33) % UInt64(bound))
            }
            let sets = [["x.com", "twitter.com"], ["youtube.com"], ["x.com", "reddit.com", "youtube.com"], ["instagram.com"]]
            for offset in stride(from: 62, through: 1, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                // Early days are patchy; the habit firms up over the weeks.
                let skip = offset > 40 ? 5 : offset > 20 ? 3 : 2
                if next(10) < skip { continue }
                var hour = 8 + next(3)
                for _ in 0..<(1 + next(offset > 30 ? 2 : 3)) {
                    let length = [30, 45, 60, 90, 120, 180, 240][next(offset > 30 ? 4 : 7)]
                    guard let start = calendar.date(byAdding: .minute, value: hour * 60 + next(4) * 15, to: day) else { break }
                    policy.commitments.append(Commitment(domains: sets[next(sets.count)], createdAt: start,
                                                         endsAt: start.addingTimeInterval(Double(length) * 60),
                                                         name: next(3) == 0 ? "morning focus" : nil))
                    hour += length / 60 + 1 + next(3)
                    if hour > 20 { break }
                }
            }
            if state != "active-aim" {
                let start = Date().addingTimeInterval(-3 * 3600)
                policy.commitments.append(Commitment(domains: ["x.com", "twitter.com"], createdAt: start, endsAt: start.addingTimeInterval(5400)))
            }
        }
        if state == "active-aim" {
            policy.commitments.append(Commitment(domains: ["x.com", "twitter.com", "instagram.com"], createdAt: Date().addingTimeInterval(-2400),
                                                 endsAt: Date().addingTimeInterval(3000)))
        }
        model.snapshot = Snapshot(policy: policy, now: Date(), sandbox: true,
                                  enforcementError: state == "error" || state == "active-error" ? "DNS listener unavailable. Retry the background service." : nil)
        if ["selected", "review", "review-long", "invalid"].contains(state) {
            model.chosen = ["example.com", "youtube.com"]
            model.amount = 30; model.multiplier = 1
        }
        if ["selected-apps", "review-apps", "apps"].contains(state) {
            model.chosen = state == "apps" ? [] : ["youtube.com"]
            model.chosenApps = Set(sampleApps)
            model.amount = 2; model.multiplier = 60
        }
        if state == "review-apps" { precondition(model.reviewDraft()) }
        if state == "apps" {
            AppCatalog.shared.load()
            model.openAppPicker()
        }
        if state == "invalid" { model.amountText = "invalid"; _ = model.reviewDraft() }
        if state == "pending" { model.text = "https://example.org/path" }
        if state == "pending-many" {
            model.chosen = Set(Presets.groups[0].domains)
            model.text = "https://example.org/path"
        }
        if state == "normalized-invalid" {
            model.chosen = ["reddit.com", "old.reddit.com"]
            model.amount = 0; model.multiplier = 1
        }
        if state == "review-long" { model.amount = 3; model.multiplier = 1440 }
        if state == "review" || state == "review-long" { precondition(model.reviewDraft()) }
        if state == "websites" { model.openComposer() }
        if state == "routines" || state == "routines-empty" { model.page = .routines }
        if ["history", "history-empty", "progress", "progress-empty", "progress-noaim"].contains(state) { model.page = .history }
        if state == "routine-editor", let routine = model.routines.first { model.editRoutine(routine) }
        if state == "routine-editor-apps" {
            model.newRoutine(seed: Routine(name: "evenings", domains: ["youtube.com"], apps: sampleApps, minutes: 120))
        }
        if state == "settings" { model.panel = .settings }
        if ["settings-outcomes", "settings-aim-edit", "settings-tally", "activity", "activity-websites", "activity-paused", "activity-empty"].contains(state) {
            let store = model.outcomes
            store.aim = Aim(title: "Ship my app", kind: .build, cost: "Another year of telling people it's almost done.", deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date()))
            store.trackingEnabled = true
            store.websiteTrackingEnabled = true
            let usage: [(String?, String?, Double)] = [("com.google.chrome", "youtube.com", 2400), ("com.google.chrome", "x.com", 1500),
                                                       ("com.hnc.discord", nil, 1300), ("com.apple.dt.xcode", nil, 5200),
                                                       ("com.apple.finder", nil, 300)]
            for offset in (0..<4).reversed() {
                let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
                for (app, domain, seconds) in usage {
                    var left = seconds * (1 - Double(offset) * 0.1)
                    while left > 0 { store.record(app: app, domain: domain, seconds: min(120, left), at: day); left -= 120 }
                }
            }
            OutcomeSettings.startsEditing = state == "settings-aim-edit"
            if state == "settings-tally" { store.aim = nil }
            model.panel = .settings
            if state.hasPrefix("activity") {
                model.panel = nil; model.page = .history; model.progressActivity = true
                if state == "activity-paused" { store.trackingEnabled = false }
                if state == "activity-empty" { store.eraseTally() }
            }
        }
        if state == "browser-check" { model.panel = .browserCheck }
        if state == "daily-limits" || state == "block-limits" {
            try policy.saveLimit(domain: "youtube.com", minutes: 30)
            try policy.saveLimit(domain: "reddit.com", minutes: 10)
            model.snapshot = Snapshot(policy: policy, now: Date(), sandbox: true, enforcementError: nil)
            if state == "daily-limits" { model.panel = .dailyLimits }
        }
        let onboardingPages = ["onboarding": 0, "onboarding-aim": 1,
                               "onboarding-aim-selected": 1, "onboarding-aim-custom": 1,
                               "onboarding-activity": 2,
                               "onboarding-blocklist": 3, "onboarding-apps": 3,
                               "onboarding-start": 4, "onboarding-install": 4]
        if let page = onboardingPages[state] {
            if state == "onboarding-aim-selected" { model.outcomes.aim = Aim(title: "Time to think", kind: .other) }
            if state == "onboarding-aim-custom" { model.outcomes.aim = Aim(title: "Read more", kind: .other) }
            if page >= 2 { model.outcomes.aim = Aim(title: "Time to think", kind: .other) }
            if page >= 3 { model.chosen = ["x.com", "twitter.com", "youtube.com"] }
            model.onboardingStep = page
            model.panel = .onboarding
        }
        if ["selected", "selected-apps", "review", "review-apps", "review-long", "invalid", "pending", "pending-many", "normalized-invalid"].contains(state) {
            model.composing = true
        }
        if state == "returning" || state == "reflection" {
            try policy.commit(["x.com", "twitter.com"], minutes: 45, at: Date().addingTimeInterval(-7200), name: "Think through my next step")
            model.snapshot = Snapshot(policy: policy, now: Date(), sandbox: true, enforcementError: nil)
            model.outcomes.aim = Aim(title: "Time to think", kind: .other)
            if state == "returning", let block = model.lastBlock { model.outcomes.reflect(on: block.id, answer: .helped) }
        }
        StatusMenu.preview = arguments.contains("--menu")
        let app = NSApplication.shared
        app.setActivationPolicy(interactive ? .regular : .prohibited)
        app.appearance = NSAppearance(named: arguments.contains("--light") ? .aqua : .darkAqua)
        let notices = AppNotices()
        if state == "notice-closing" {
            notices.notice = .closing(ClosingApp(app: sampleApps[0], deadline: Date().addingTimeInterval(9)))
        } else if state.hasPrefix("notice-blocked") {
            notices.aim = model.outcomes.aim
            notices.notice = .blocked(BlockedLaunch(app: sampleApps[1], at: Date(), until: Date().addingTimeInterval(5400)), more: 0)
        }
        let content = Group {
            if state.hasPrefix("ring-") {
                let facts = model.progressFacts
                let day = state == "ring-day" ? facts.today - 3 : facts.deadline ?? facts.today
                YearRing(facts: facts, aim: model.outcomes.aim, diameter: 384, selection: day)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Glass())
            } else if state.hasPrefix("notice") {
                AppNoticeView(notices: notices).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: arguments.contains("--light") ? .white : .darkGray))
            } else if arguments.contains("--menu") {
                StatusMenu(model: model).fixedSize()
                    .background(Glass(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state == "onboarding-apps" {
                OnboardingView(model: model, appsExpanded: true)
            } else if state.hasPrefix("review") {
                // Hidden windows do not present native sheets.
                CommitmentFlow(model: model)
            } else { RootView(model: model) }
        }
            .preferredColorScheme(arguments.contains("--light") ? .light : .dark)
            .sheet(isPresented: .constant(browserStage != nil)) {
                if let browserStage {
                    BrowserCheckSheet(stage: browserStage, busy: false, canStart: true,
                                      error: state == "browser-check-error" ? "couldn't connect to blocking. check the connection and try again." : nil) { _ in }
                }
            }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Steadfast UI Check"
        window.contentMinSize = NSSize(width: 640, height: 600)
        window.contentView = hosting
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        if interactive { window.makeKeyAndOrderFront(nil) }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(800))
                guard interactive || (!app.isActive && !window.isVisible) else {
                    throw Failure("a noninteractive capture must not activate or show its window")
                }
                hosting.layoutSubtreeIfNeeded()
                guard abs(hosting.bounds.width - width) < 1, abs(hosting.bounds.height - height) < 1 else {
                    throw Failure("capture size \(hosting.bounds.size) does not match requested \(width)x\(height)")
                }
                let target = window.attachedSheet?.contentView ?? hosting
                guard let image = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
                    throw Failure("unable to allocate window capture")
                }
                target.cacheDisplay(in: target.bounds, to: image)
                guard let png = image.representation(using: .png, properties: [:]) else {
                    throw Failure("unable to encode window capture")
                }
                try png.write(to: output)
                print("rendered \(state) at \(Int(width))x\(Int(height)): \(output.path)")
                fflush(stdout)
                if !interactive { exit(0) }
            } catch {
                fputs("UI check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }
}
