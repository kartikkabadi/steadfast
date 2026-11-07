import Foundation
import Network
import XPC
import OSLog
import SteadfastCore

@MainActor final class Engine {
    let directory: URL
    let sandbox: Bool
    let service: String
    let enforcement: Enforcement
    private(set) lazy var apps: AppEnforcer = {
        let enforcer = AppEnforcer(scope: sandbox ? directory : nil, logger: Logger(subsystem: ServiceName.production, category: "apps")) { [unowned self] in self.now }
        enforcer.onActivity = { [unowned self] in ServiceEvents.postAppActivity(for: self.service) }
        return enforcer
    }()
    var policy: Policy
    var domainIndex: DomainIndex
    var enforcementError: String?
    var listener: NWListener?
    var udp: UDPServer?
    var ready = 0
    var timer: Timer?
    var didBecomeReady: (() throws -> Void)?
    private var cleanedIdle = false
    private var announcedReady = false
    /// The commitments running at the last refresh. A block that ends without touching
    /// DNS (an apps-only block) still has to tell the window it finished.
    private var announcedActive = Set<UUID>()
    let origin = ContinuousClock.now
    let initialTime: Date
    let logger = Logger(subsystem: ServiceName.production, category: "service")

    init(directory: URL, sandbox: Bool, service: String) throws {
        self.directory = directory; self.sandbox = sandbox; self.service = service
        let policyURL = directory.appendingPathComponent("policy.json")
        if FileManager.default.fileExists(atPath: policyURL.path) {
            policy = try JSONDecoder().decode(Policy.self, from: Data(contentsOf: policyURL))
        } else { policy = Policy() }
        domainIndex = DomainIndex(policy: policy)
        initialTime = max(Date(), policy.lastObserved)
        let sandboxPort = ProcessInfo.processInfo.environment["STEADFAST_TEST_DNS_PORT"].flatMap(UInt16.init)
        enforcement = Enforcement(resolverDirectory: sandbox ? directory.appendingPathComponent("resolver") : URL(fileURLWithPath: "/etc/resolver"), hostsURL: sandbox ? directory.appendingPathComponent("hosts") : URL(fileURLWithPath: "/etc/hosts"), port: sandbox ? sandboxPort ?? 55353 : 53535)
        if sandbox && !FileManager.default.fileExists(atPath: enforcement.hostsURL.path) {
            try "127.0.0.1 localhost\n::1 localhost\n".write(to: enforcement.hostsURL, atomically: true, encoding: .utf8)
        }
    }
    var now: Date {
        let elapsed = origin.duration(to: .now).components
        let monotonic = initialTime.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        return max(Date(), max(policy.lastObserved, monotonic))
    }
    func save() throws {
        let data = try JSONEncoder().encode(policy)
        let path = directory.appendingPathComponent("policy.json")
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
    var canExitIdle: Bool {
        ready == 2 && cleanedIdle && enforcementError == nil && policy.active(at: now).isEmpty
            && !policy.routines.contains { $0.schedule?.enabled == true }
            && !policy.dailyLimits.contains { $0.blockedUntil(at: now) != nil }
    }
    func refresh() {
        let time = now
        let previousError = enforcementError
        var changed = false
        var policyChanged = false
        do {
            let previous = policy
            let scheduled = policy.startScheduledBlocks(at: time)
            let trimmed = policy.trimHistory(at: time)
            policyChanged = scheduled || trimmed
            if policyChanged {
                do { try save() } catch { policy = previous; throw error }
            }
            domainIndex = DomainIndex(policy: policy, at: time)
            let exhausted = policy.dailyLimits.filter { $0.blockedUntil(at: time) != nil }.map(\.domain)
            let domains = Array(Set(policy.active(at: time).flatMap(\.domains) + exhausted)).sorted()
            changed = try enforcement.apply(domains: domains)
            if !domains.isEmpty || changed { policy.lastObserved = time; try save() }
            if changed && !sandbox { flushDNS() }
            enforcementError = nil
            cleanedIdle = domains.isEmpty
        } catch {
            cleanedIdle = false
            enforcementError = error.localizedDescription
            logger.error("enforcement failed: \(error.localizedDescription, privacy: .public)")
        }
        // Apps are enforced even if DNS configuration needs attention.
        apps.update(policy.blockedApps(at: time))
        let running = Set(policy.active(at: time).map(\.id))
        let activeChanged = running != announcedActive
        announcedActive = running
        if changed || policyChanged || activeChanged || previousError != enforcementError || !announcedReady {
            ServiceEvents.postChange(for: service)
            announcedReady = true
        }
        schedule()
    }
    func schedule() {
        timer?.invalidate()
        timer = nil
        if let delay = policy.maintenanceDelay(at: now, retrying: enforcementError != nil) {
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            timer?.tolerance = min(1, delay / 10)
        } else if canExitIdle {
            // Wait out launchd's ten-second throttle before releasing an empty process.
            timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.canExitIdle == true { exit(0) }
                }
            }
            timer?.tolerance = 1
        }
    }
    func flushDNS() {
        for (path, args) in [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])] {
            let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = args
            do { try process.run() } catch { logger.error("dns cache refresh failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
    func startDNS() throws {
        udp = try UDPServer(port: enforcement.port) { [weak self] in self?.answer($0) }
        ready = 1
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: enforcement.port)!)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.ready += 1
                    if self.ready == 2 {
                        self.refresh()
                        let activate = self.didBecomeReady
                        self.didBecomeReady = nil
                        do { try activate?() }
                        catch { self.logger.fault("xpc activation failed: \(error.localizedDescription, privacy: .public)"); exit(1) }
                    }
                case .failed(let error):
                    self.enforcementError = "dns service could not bind its local port: \(error.localizedDescription)"
                    self.logger.fault("dns listener failed: \(error.localizedDescription, privacy: .public)")
                    // launchd retries a failed service; it must never report enforcement as healthy.
                    exit(1)
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                let watchdog = Task {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    connection.cancel()
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .cancelled, .failed: watchdog.cancel()
                    default: break
                    }
                }
                connection.start(queue: .main)
                self.receiveTCP(connection, buffer: Data())
            }
        }
        listener.start(queue: .main); self.listener = listener
    }
    func answer(_ data: Data) -> Data? { DNS.reply(to: data) { domainIndex.blocks($0, at: now) } }
    func receiveTCP(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4098) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, let data, error == nil else { connection.cancel(); return }
                let combined = buffer + data
                guard combined.count <= 4098 else { connection.cancel(); return }
                if combined.count >= 2 {
                    let length = Int(combined[0]) * 256 + Int(combined[1])
                    guard length <= 4096 else { connection.cancel(); return }
                    if combined.count >= length + 2 {
                        guard let response = self.answer(combined.subdata(in: 2..<(length + 2))) else { connection.cancel(); return }
                        let framed = Data([UInt8(response.count >> 8), UInt8(response.count & 255)]) + response
                        connection.send(content: framed, completion: .contentProcessed { _ in connection.cancel() }); return
                    }
                }
                if complete { connection.cancel() } else { self.receiveTCP(connection, buffer: combined) }
            }
        }
    }
    func request(_ data: Data) -> ServiceReply {
        defer { if canExitIdle { schedule() } }
        do {
            guard data.count <= 320_000 else { throw Failure("request is too large") }
            let request = try JSONDecoder().decode(Request.self, from: data)
            switch request.action {
            case "status": break
            case "prepare-uninstall":
                guard policy.active(at: now).isEmpty else { throw Failure("wait until every commitment expires before uninstalling") }
                guard !policy.routines.contains(where: { $0.schedule?.enabled == true }) else {
                    throw Failure("turn off your schedules before uninstalling")
                }
                guard !policy.dailyLimits.contains(where: { $0.blockedUntil(at: now) != nil }) else {
                    throw Failure("remove daily limits or wait for them to reset before uninstalling")
                }
                refresh()
            case "save-limit", "delete-limit", "record-usage":
                var next = policy
                let time = now
                let before = policy.dailyLimits.filter { $0.blockedUntil(at: time) != nil }.map(\.domain)
                if request.action == "record-usage" {
                    guard let sample = request.usageSample else { throw Failure("missing usage sample") }
                    _ = try next.recordUsage(sample, at: time)
                } else {
                    guard let limit = request.limit else { throw Failure("choose a daily limit") }
                    let domain = try Domain.parse(limit.domain)
                    if request.action == "save-limit" {
                        try enforcement.validate(domains: [domain])
                        try next.saveLimit(domain: domain, minutes: limit.minutes)
                    } else {
                        next.dailyLimits.removeAll { $0.domain == domain }
                    }
                }
                if next.dailyLimits != policy.dailyLimits {
                    let previous = policy
                    policy = next
                    do { try save() } catch { policy = previous; throw error }
                    let after = policy.dailyLimits.filter { $0.blockedUntil(at: time) != nil }.map(\.domain)
                    if before != after { refresh() }
                    if request.action != "record-usage" || before != after { ServiceEvents.postChange(for: service) }
                }
            case "save-routine", "delete-routine", "skip-run", "restore-run", "sync-routines":
                var next = policy
                if request.action == "sync-routines" {
                    guard let change = request.routineSync else { throw Failure("no routine changes to sync") }
                    try next.applyRoutineSync(change, at: now)
                    try enforcement.validate(domains: next.routines.flatMap(\.domains))
                } else if request.action == "save-routine" {
                    guard let routine = request.routine else { throw Failure("choose a routine to save") }
                    try enforcement.validate(domains: Domain.normalized(routine.domains))
                    try next.saveRoutine(routine, at: now)
                } else if request.action == "delete-routine" {
                    guard let id = request.routineID, next.routines.contains(where: { $0.id == id }) else {
                        throw Failure("this routine no longer exists")
                    }
                    next.routines.removeAll { $0.id == id }
                } else {
                    guard let id = request.routineID, let start = request.scheduledStart else {
                        throw Failure("choose an upcoming run")
                    }
                    try next.setSkippedRun(routineID: id, start: start, skip: request.action == "skip-run", at: now)
                }
                let previous = policy
                policy = next
                do { try save() } catch { policy = previous; throw error }
                refresh()
                ServiceEvents.postChange(for: service)
            case "commit":
                guard ready == 2 else { throw Failure("the dns service is still starting") }
                if (request.minutes ?? 0) > 1440 && request.confirmedLongBlock != true {
                    throw Failure("confirm the end date for a block longer than 24 hours")
                }
                let domains = try Domain.normalized(request.domains ?? [])
                try enforcement.validate(domains: Array(Set(policy.active(at: now).flatMap(\.domains) + domains)))
                var next = policy
                try next.commit(domains, apps: request.apps ?? [], minutes: request.minutes ?? 0, at: now, name: request.name, routineID: request.routineID)
                let previous = policy
                policy = next
                do { try save() } catch { policy = previous; throw error }
                refresh()
            default: throw Failure("active commitments cannot be removed or changed")
            }
            let status = Snapshot(policy: policy, now: now, sandbox: sandbox, enforcementError: ready == 2 ? enforcementError : "dns service is starting",
                                  appActivity: apps.activity)
            return ServiceReply(data: try JSONEncoder().encode(status))
        } catch { return ServiceReply(error: error.localizedDescription) }
    }
}

let args = CommandLine.arguments
let sandboxIndex = args.firstIndex(of: "--sandbox")
let sandbox = sandboxIndex != nil
if !sandbox && geteuid() != 0 { fputs("production service must run as root via launchd\n", stderr); exit(1) }
if sandbox && geteuid() == 0 { fputs("sandbox mode must run without root\n", stderr); exit(1) }
do {
    let directory: URL
    let name: String
    if let index = sandboxIndex, args.count > index + 2 {
        directory = URL(fileURLWithPath: args[index + 1], isDirectory: true); name = args[index + 2]
        guard name.hasPrefix("dev.local.steadfast.test.") else { throw Failure("invalid sandbox service name") }
    } else if sandbox { throw Failure("usage: steadfastd --sandbox directory mach-service") }
    else { directory = URL(fileURLWithPath: "/Library/Application Support/Steadfast", isDirectory: true); name = ServiceName.production }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let engine = try Engine(directory: directory, sandbox: sandbox, service: name)
    try engine.startDNS()
    let handler: @Sendable (XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision = { incoming in
        let (decision, session): (XPCListener.IncomingSessionRequest.Decision, XPCSession) = incoming.accept { (data: Data) -> (any Encodable)? in
            MainActor.assumeIsolated { engine.request(data) }
        }
        session.setTargetQueue(.main)
        return decision
    }
    let listener: XPCListener
    if sandbox {
        listener = try XPCListener(service: name, targetQueue: .main, options: .inactive, incomingSessionHandler: handler)
    } else {
        let text = try String(contentsOf: directory.appendingPathComponent("client.runtime-requirement"), encoding: .utf8)
        listener = try XPCListener(service: name, targetQueue: .main, options: .inactive, requirement: RuntimeAuthorization.requirement(from: text), incomingSessionHandler: handler)
    }
    engine.didBecomeReady = { try listener.activate() }
    withExtendedLifetime((engine, listener)) { RunLoop.main.run() }
} catch { fputs("steadfastd: \(error.localizedDescription)\n", stderr); exit(1) }
