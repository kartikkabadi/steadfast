import Foundation
import Darwin
import OSLog
import SystemConfiguration
import SteadfastCore

/// Closes blocked apps.
///
/// While any app is blocked, a kqueue watches every process for fork, exec and exit.
/// A launch from the Dock, Finder, Spotlight or `open` is a launchd fork followed by
/// an exec of the app's executable, so it is stopped at exec, before the app's own
/// code runs. A one-second sweep of the process table backs that up. With no app
/// blocks the watcher closes completely and costs nothing.
///
/// Everything runs on the main queue with the DNS listener. Each step is bounded:
/// fork bursts are coalesced into at most one scan per `scanInterval`, and file reads
/// never block (see `SafeFile`).
@MainActor final class AppEnforcer {
    static let companion = "/Applications/Steadfast.app/Contents/MacOS/Steadfast"
    static let scanInterval: TimeInterval = 0.015
    /// Kills of one app within this window count as one launch, however many helpers it starts.
    static let launchWindow: TimeInterval = 3

    var onActivity: (() -> Void)?
    private let scope: String?
    private let logger: Logger
    private let now: () -> Date
    private let ownPID = getpid()

    private var targets: [String: AppBlock] = [:]
    private var matcher = AppMatcher(blocked: [])
    private var closing: [String: ClosingApp] = [:]
    private var recent: [BlockedLaunch] = []
    private var lastRecorded: [String: Date] = [:]
    private var error: String?

    private var queue: Int32 = -1
    private var source: (any DispatchSourceRead)?
    private var sweeper: Timer?
    private var graceTimer: Timer?
    private var watched = Set<pid_t>()
    private var bundleIDs: [String: CachedID] = [:]
    private var lastScan = ContinuousClock.now
    private var scanTimer: (any DispatchSourceTimer)?
    private var companionLaunches: [Date] = []
    private var companionProcess: Process?

    private struct CachedID { let modified: timespec; let size: off_t; let id: String? }
    /// A process as it was when checked, so a kill can't land on a reused process ID.
    private struct Identity: Equatable { let pid: pid_t; let started: UInt64; let uid: uid_t }

    /// In sandbox mode only executables inside `scope` are ever matched, so tests cannot close real apps.
    init(scope: URL?, logger: Logger, now: @escaping () -> Date) {
        // realpath keeps /private, matching the paths the kernel reports for processes.
        self.scope = scope.map { url in
            guard let resolved = realpath(url.path, nil) else { return url.path + "/" }
            defer { free(resolved) }
            return String(decoding: Data(bytes: resolved, count: strlen(resolved)), as: UTF8.self) + "/"
        }
        self.logger = logger; self.now = now
    }

    var activity: AppActivity {
        let time = now()
        return AppActivity(closing: closing.values.filter { $0.deadline > time }.sorted { $0.deadline < $1.deadline },
                           recent: recent, error: error)
    }

    func update(_ blocks: [String: AppBlock]) {
        let blocks = blocks.filter { !AppRule.isProtected($0.key) }
        let added = Set(blocks.keys).subtracting(targets.keys)
        targets = blocks
        matcher = AppMatcher(blocked: Set(blocks.keys))
        let before = closing
        closing = closing.filter { blocks[$0.key] != nil }
        guard !blocks.isEmpty else {
            stop()
            if before != closing { onActivity?() }
            return
        }
        start()
        // Apps that were already open when their block began get a moment to save.
        sweep(granting: added, notifyAfter: before != closing)
    }

    // MARK: - Watching

    private func start() {
        guard sweeper == nil else { return }
        let descriptor = kqueue()
        if descriptor >= 0 {
            queue = descriptor
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.drain() } }
            source.setCancelHandler { Darwin.close(descriptor) }
            source.resume()
            self.source = source
            error = nil
        } else {
            // The sweep alone still enforces the block, a little more slowly.
            let reason = String(validatingCString: strerror(errno)) ?? "unknown error"
            error = "app launches are checked once a second because the process watcher is unavailable"
            logger.error("kqueue failed: \(reason, privacy: .public)")
        }
        let sweeper = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        sweeper.tolerance = 0.2
        RunLoop.main.add(sweeper, forMode: .common)
        self.sweeper = sweeper
        logger.log("app blocking started")
    }

    private func stop() {
        guard sweeper != nil else { return }
        sweeper?.invalidate(); sweeper = nil
        graceTimer?.invalidate(); graceTimer = nil
        source?.cancel(); source = nil
        queue = -1
        watched.removeAll()
        bundleIDs.removeAll()
        closing.removeAll()
        lastRecorded.removeAll()
        scanTimer?.cancel(); scanTimer = nil
        error = nil
        logger.log("app blocking stopped")
    }

    private func drain() {
        guard queue >= 0 else { return }
        var events = [Darwin.kevent](repeating: Darwin.kevent(), count: 128)
        var forked = false
        var zero = timespec()
        while true {
            let count = Int(kevent(queue, nil, 0, &events, Int32(events.count), &zero))
            guard count > 0 else { break }
            for event in events.prefix(count) {
                let pid = pid_t(truncatingIfNeeded: event.ident)
                if event.flags & UInt16(EV_ERROR) != 0 { watched.remove(pid); continue }
                if event.fflags & UInt32(NOTE_EXEC) != 0 { check(pid) }
                if event.fflags & UInt32(NOTE_FORK) != 0 { forked = true }
                if event.fflags & UInt32(NOTE_EXIT) != 0 { watched.remove(pid) }
            }
            if count < events.count { break }
        }
        if forked { requestScan() }
    }

    /// Coalesces fork bursts, such as a build, into at most one scan per interval. A child
    /// that execs before its scan is still caught, because each scan checks every new
    /// process's current executable.
    /// The deferred scan uses a strict timer: macOS otherwise coalesces a background
    /// daemon's timers by up to ~100 ms, which would let a blocked app start drawing.
    private func requestScan() {
        guard scanTimer == nil else { return }
        let wait = Self.scanInterval - lastScan.duration(to: .now).seconds
        guard wait > 0 else { scanNew(); return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now() + wait, leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scanTimer?.cancel(); self.scanTimer = nil
                self.scanNew()
            }
        }
        scanTimer = timer
        timer.resume()
    }

    /// Watches processes that appeared since the last look and checks each one.
    private func scanNew() {
        lastScan = .now
        let pids = Self.allPIDs()
        let fresh = pids.filter { !watched.contains($0) }
        watch(fresh)
        // Checking after the watch is registered means an exec can never fall between the two.
        for pid in fresh { check(pid) }
        if watched.count > pids.count * 2 { watched.formIntersection(pids) }
    }

    private func watch(_ pids: [pid_t]) {
        guard queue >= 0, !pids.isEmpty else { return }
        for start in stride(from: 0, to: pids.count, by: 256) {
            var changes = pids[start..<min(start + 256, pids.count)].map { pid in
                Darwin.kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_CLEAR | EV_RECEIPT),
                              fflags: UInt32(NOTE_EXEC) | UInt32(NOTE_FORK) | UInt32(NOTE_EXIT), data: 0, udata: nil)
            }
            var receipts = [Darwin.kevent](repeating: Darwin.kevent(), count: changes.count)
            let count = Int(kevent(queue, &changes, Int32(changes.count), &receipts, Int32(receipts.count), nil))
            for receipt in receipts.prefix(max(0, count)) where receipt.data == 0 {
                watched.insert(pid_t(truncatingIfNeeded: receipt.ident))
            }
        }
    }

    /// Checks every process, closes blocked ones, and keeps the open-app grace list current.
    private func sweep(granting: Set<String> = [], notifyAfter: Bool = false) {
        let pids = Self.allPIDs()
        watch(pids.filter { !watched.contains($0) })
        if watched.count > pids.count * 2 { watched.formIntersection(pids) }
        var seen = Set<String>()
        let time = now()
        var changed = notifyAfter, granted = false
        for pid in pids {
            guard let (key, identity) = blocked(pid) else { continue }
            seen.insert(key)
            if granting.contains(key), closing[key] == nil, let block = targets[key] {
                closing[key] = ClosingApp(app: block.app, deadline: time.addingTimeInterval(AppRule.gracePeriod))
                granted = true
            }
            close(identity, key: key, at: time)
        }
        // An app that quit on its own no longer needs time to save.
        for key in closing.keys where !seen.contains(key) || closing[key]!.deadline <= time {
            closing.removeValue(forKey: key); changed = true
        }
        if granted { changed = true; ensureCompanion() }
        if changed { onActivity?() }
        scheduleGraceEnd()
    }

    private func scheduleGraceEnd() {
        graceTimer?.invalidate(); graceTimer = nil
        guard let deadline = closing.values.map(\.deadline).min() else { return }
        let timer = Timer(timeInterval: max(0.05, deadline.timeIntervalSince(now()) + 0.05), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        graceTimer = timer
    }

    private func check(_ pid: pid_t) {
        guard let (key, identity) = blocked(pid) else { return }
        close(identity, key: key, at: now())
    }

    private func blocked(_ pid: pid_t) -> (String, Identity)? {
        guard pid > 1, pid != ownPID, !matcher.blocked.isEmpty,
              let identity = Self.identity(of: pid), let path = Self.path(of: pid) else { return nil }
        if let scope, !path.hasPrefix(scope) { return nil }
        guard let key = matcher.match(executable: path, bundleID: { self.bundleID(at: $0) }) else { return nil }
        return (key, identity)
    }

    private func close(_ identity: Identity, key: String, at time: Date) {
        if let grace = closing[key], grace.deadline > time { return }
        // The process ID must still name the process that was checked.
        guard Self.identity(of: identity.pid) == identity, Darwin.kill(identity.pid, SIGKILL) == 0,
              let block = targets[key] else { return }
        if let last = lastRecorded[key], time.timeIntervalSince(last) < Self.launchWindow { return }
        lastRecorded[key] = time
        recent.insert(BlockedLaunch(app: block.app, at: time, until: block.until), at: 0)
        if recent.count > 10 { recent.removeLast(recent.count - 10) }
        logger.log("closed blocked app \(block.app.bundleID, privacy: .public)")
        onActivity?()
        ensureCompanion()
    }

    // MARK: - Bundles

    private func bundleID(at bundle: String) -> String? {
        for location in SafeFile.infoPlistLocations {
            let plist = bundle + "/" + location
            var info = stat()
            guard lstat(plist, &info) == 0 else { continue }
            if let cached = bundleIDs[plist], cached.size == info.st_size,
               cached.modified.tv_sec == info.st_mtimespec.tv_sec, cached.modified.tv_nsec == info.st_mtimespec.tv_nsec {
                return cached.id
            }
            let id = SafeFile.infoPlist(atPath: plist)?["CFBundleIdentifier"] as? String
            if bundleIDs.count >= 4096 { bundleIDs.removeAll(keepingCapacity: true) }
            bundleIDs[plist] = CachedID(modified: info.st_mtimespec, size: info.st_size, id: id)
            return id
        }
        return nil
    }

    // MARK: - Companion

    /// The window app explains a closed launch and asks open apps to quit. If it isn't
    /// running for the signed-in user, it's opened in the background, at most three
    /// times an hour, so an app that relaunches itself can't keep reopening Steadfast.
    private func ensureCompanion() {
        let time = now()
        companionLaunches.removeAll { time.timeIntervalSince($0) > 3600 }
        guard scope == nil, companionProcess == nil, companionLaunches.count < 3,
              companionLaunches.last.map({ time.timeIntervalSince($0) > 20 }) ?? true,
              FileManager.default.isExecutableFile(atPath: Self.companion) else { return }
        var uid: uid_t = 0
        guard let user = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?, uid != 0, user != "loginwindow" else { return }
        let running = Self.allPIDs().contains { pid in
            Self.identity(of: pid)?.uid == uid && Self.path(of: pid) == Self.companion
        }
        guard !running else { return }
        companionLaunches.append(time)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        // Launch in the signed-in user's session, as that user, never as root.
        process.arguments = ["asuser", String(uid), "/usr/bin/sudo", "-n", "-u", "#\(uid)", "--",
                             "/usr/bin/open", "-g", "-a", "/Applications/Steadfast.app", "--args", "--background"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.companionProcess = nil } }
        do { try process.run(); companionProcess = process }
        catch { logger.error("could not open steadfast: \(error.localizedDescription, privacy: .public)") }
    }

    // MARK: - Processes

    static func allPIDs() -> [pid_t] {
        let estimate = Int(proc_listallpids(nil, 0))
        guard estimate > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: estimate + 128)
        let count = Int(proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size)))
        return Array(buffer.prefix(max(0, count)))
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func identity(of pid: pid_t) -> Identity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Identity(pid: pid, started: info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec, uid: info.pbi_uid)
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
