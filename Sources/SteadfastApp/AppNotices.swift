import AppKit
import Observation
import SwiftUI
import SteadfastCore

/// Runs in the menu bar app for the whole session, independent of the window.
///
/// When a block starts, apps that are already open are asked to quit, so they can
/// offer to save; the service closes them after the grace period either way. When
/// the service stops a launch, a small notice says what was blocked and until when.
@Observable final class AppNotices {
    static let shared = AppNotices()
    static let grace = AppRule.gracePeriod
    /// An app the service closes this often is relaunching itself, for example as a login item.
    static let storm = (count: 3, window: 120.0, quiet: 600.0)

    enum Notice: Equatable {
        case closing(ClosingApp)
        case blocked(BlockedLaunch, more: Int)
    }

    var notice: Notice?
    /// What the person is protecting time for, shown under a blocked launch.
    var aim: Aim?
    var purpose: String?
    @ObservationIgnored private var service = ServiceName.production
    @ObservationIgnored private var started = false
    @ObservationIgnored private var seen = Set<UUID>()
    @ObservationIgnored private var asked: [String: Date] = [:]
    @ObservationIgnored private var primed = false
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var checkAgain = false
    @ObservationIgnored private var shown: [String: [Date]] = [:]
    @ObservationIgnored private var quietUntil: [String: Date] = [:]
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hide: Task<Void, Never>?

    func start(service: String) {
        guard !started else { return }
        started = true
        self.service = service
        Task {
            do {
                let updates = try ServiceEvents.appActivity(for: service)
                await check()
                for await _ in updates { await check() }
            } catch {
                // Without notifications, check while something might be closing.
                while !Task.isCancelled {
                    await check()
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                }
            }
        }
    }

    /// Any process can post the activity notification, so a burst of posts collapses into
    /// one authenticated status request at a time, at most four times a second. What the
    /// notice shows always comes from the service, never from the notification.
    func check() async {
        guard !checking else { checkAgain = true; return }
        checking = true
        defer { checking = false }
        repeat {
            checkAgain = false
            await checkOnce()
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        } while checkAgain
    }

    private func checkOnce() async {
        guard let snapshot = try? await Client.send(Request(action: "status"), service: service),
              let activity = snapshot.appActivity else { return }
        for item in activity.closing where asked[item.app.key] != item.deadline {
            asked[item.app.key] = item.deadline
            quit(item.app)
            show(.closing(item), until: item.deadline.addingTimeInterval(1), now: snapshot.now)
        }
        // On first look, only launches from the last few seconds are news. Older ones were
        // seen by an earlier session, or happened while nobody was signed in.
        let fresh = activity.recent.filter { !seen.contains($0.id) && (primed || snapshot.now.timeIntervalSince($0.at) < 8) }
        // The service keeps only its latest launches, so older IDs can never come back.
        seen = Set(activity.recent.map(\.id))
        primed = true
        let worth = fresh.filter { announce($0.app, at: snapshot.now) }
        if let latest = worth.first {
            purpose = snapshot.policy.active(at: snapshot.now)
                .filter { $0.apps.contains(latest.app) }
                .max { $0.endsAt < $1.endsAt }?.name
            show(.blocked(latest, more: Set(worth.map(\.app)).count - 1), until: snapshot.now.addingTimeInterval(5), now: snapshot.now)
        }
    }

    /// Whether a blocked launch deserves a notice. An app closed again and again in a short
    /// time is relaunching itself, so it goes quiet for a while instead of flashing a notice.
    private func announce(_ app: BlockedApp, at time: Date) -> Bool {
        if let quiet = quietUntil[app.key], quiet > time { return false }
        let times = (shown[app.key] ?? []).filter { time.timeIntervalSince($0) < Self.storm.window } + [time]
        shown[app.key] = times
        if times.count > Self.storm.count {
            quietUntil[app.key] = time.addingTimeInterval(Self.storm.quiet)
            shown[app.key] = []
            return false
        }
        return true
    }

    /// Asks every running copy to quit the normal way, as if from the Dock.
    private func quit(_ app: BlockedApp) {
        for running in NSWorkspace.shared.runningApplications where running.bundleIdentifier?.lowercased() == app.key {
            running.terminate()
        }
    }

    // MARK: - Panel

    private func show(_ notice: Notice, until end: Date, now: Date) {
        aim = Self.savedAim()
        self.notice = notice
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // SwiftUI lays out the new notice on the next pass; centre it once it has its height.
        DispatchQueue.main.async { [weak self] in self?.position(panel) }
        hide?.cancel()
        let seconds = max(2, end.timeIntervalSince(now))
        hide = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.dismiss()
        }
        if let text = accessibilityText(notice) {
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// Read fresh each time: the notice can appear in a background launch with no window,
    /// and the aim may have changed since. Missing or unreadable means no aim line.
    private static func savedAim() -> Aim? {
        guard let url = OutcomeStore.defaultURL, let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder.outcomes.decode(OutcomeStore.Saved.self, from: data))?.aim
    }

    func dismiss() {
        hide?.cancel(); hide = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.still ? 0 : 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.hide == nil else { return }
                panel.orderOut(nil); self.notice = nil
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
                            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        let host = NSHostingView(rootView: AppNoticeView(notices: self))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 360, height: 72)
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 12,
                              width: size.width, height: size.height), display: true)
    }

    private func accessibilityText(_ notice: Notice) -> String? {
        switch notice {
        case let .closing(item): return "\(item.app.name) is blocked and will close in \(Int(Self.grace)) seconds. Save your work."
        case let .blocked(item, _):
            let reason = AppNoticeView.reason(aim, purpose: purpose).map { " \($0)" } ?? ""
            return "\(item.app.name) is blocked \(item.until.blockDeadline).\(reason)"
        }
    }
}

struct AppNoticeView: View {
    let notices: AppNotices

    var body: some View {
        Group {
            if let notice = notices.notice {
                content(notice)
            } else {
                // The same footprint as a notice, shadow margin included, so the
                // panel is placed for what it is about to show.
                Color.clear.frame(width: 360, height: 72).padding(16)
            }
        }
        .font(TypeScale.body)
        .foregroundStyle(Palette.ink)
    }

    private func content(_ notice: Notice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AppIcon(bundleID: app(notice).bundleID, size: 36)
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Palette.accent.color, in: Circle())
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                switch notice {
                case let .closing(item):
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(ceil(item.deadline.timeIntervalSince(context.date))))
                        Text(left > 0 ? "\(item.app.name) closes in \(left) s" : "Closing \(item.app.name)")
                            .font(TypeScale.body.weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Text("Save your work now.")
                        .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                case let .blocked(item, more):
                    Text(more > 0 ? "\(item.app.name) and \(more) more are blocked" : "\(item.app.name) is blocked")
                        .font(TypeScale.body.weight(.semibold))
                    Text("Steadfast unlocks it \(item.until.blockDeadline)")
                        .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                    if let reason = Self.reason(notices.aim, purpose: notices.purpose) {
                        Text(reason)
                            .font(TypeScale.chrome).foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .truncationMode(.tail)
                            .padding(.top, 3)
                            .help(reason)
                    }
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Door(icon: "xmark", help: "Dismiss", act: { notices.dismiss() })
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 12)
        .frame(width: 360)
        .background { Glass(cornerRadius: 18) }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .depth(.floating, cornerRadius: 18)
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private typealias Notice = AppNotices.Notice

    /// Prefer the active block's purpose, then the person's current aim.
    static func reason(_ aim: Aim?, purpose: String? = nil) -> String? {
        guard let reason = purpose ?? aim?.title else { return nil }
        return "Making room for: \(reason)"
    }

    private func app(_ notice: Notice) -> BlockedApp {
        switch notice {
        case let .closing(item): return item.app
        case let .blocked(item, _): return item.app
        }
    }
}
