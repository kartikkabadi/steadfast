import AppKit
import ApplicationServices
import SteadfastCore

@Observable final class WebsiteUsage {
    enum Activity: Equatable {
        case waiting, unreadable, tracking(String)
    }

    private(set) var authorized = AXIsProcessTrusted()
    private(set) var status: String?
    private(set) var activity = Activity.waiting
    private var task: Task<Void, Never>?

    func requestAccess() {
        authorized = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func start(for model: Model) {
        authorized = AXIsProcessTrusted()
        guard !model.dailyLimits.isEmpty, task == nil else { return }
        task = Task { [weak self, weak model] in
            var previous: (pid_t, String, ContinuousClock.Instant)?
            while !Task.isCancelled {
                guard let self, let model else { return }
                guard !model.dailyLimits.isEmpty else {
                    self.activity = .waiting; self.status = nil; self.task = nil
                    return
                }
                self.authorized = AXIsProcessTrusted()
                let process = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let rules = model.dailyLimits.map(\.domain)
                let host: String?
                if self.authorized, model.serviceReady, let process, process != ProcessInfo.processInfo.processIdentifier {
                    host = await Task.detached(priority: .utility) { ForegroundWebsite.host(in: process) }.value
                } else { host = nil }
                let stillFrontmost = process != nil && process == NSWorkspace.shared.frontmostApplication?.processIdentifier
                let match = host.flatMap { host in rules.first { Domain.matches(host, rule: $0) } }
                let wasTracking = match.map { self.activity == .tracking($0) } ?? false
                if !stillFrontmost || !wasTracking {
                    self.activity = self.authorized && model.serviceReady && stillFrontmost
                        && process != ProcessInfo.processInfo.processIdentifier && host == nil && ForegroundWebsite.isInUse
                        ? .unreadable : .waiting
                }
                let now = ContinuousClock.now
                if let process, let match, stillFrontmost {
                    if let prior = previous, prior.0 == process, prior.1 == match {
                        let elapsed = prior.2.duration(to: now).components
                        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                        if (0...8).contains(seconds) {
                            let sample = UsageSample(domain: match, endedAt: Date(), seconds: seconds)
                            do {
                                let result = try await Client.send(Request(action: "record-usage", usageSample: sample), service: model.service)
                                if result.now >= (model.snapshot?.now ?? .distantPast) { model.snapshot = result }
                                self.status = nil
                                let tracking = model.dailyLimits.contains { $0.domain == match && $0.blockedUntil(at: result.now) == nil }
                                self.activity = tracking && process == NSWorkspace.shared.frontmostApplication?.processIdentifier
                                    ? .tracking(match) : .waiting
                            } catch {
                                self.status = "usage could not be recorded. check the blocking connection."
                                self.activity = .waiting
                            }
                        }
                    }
                    previous = (process, match, now)
                } else { previous = nil }
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
    }
}

nonisolated enum ForegroundWebsite {
    static func isBrowser(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return AppPresets.categories[id] == .browsers || id.hasPrefix("com.google.chrome.")
            || id.hasPrefix("org.mozilla.firefox") || id.hasPrefix("com.brave.browser.")
            || id.hasPrefix("com.microsoft.edgemac.") || id.contains("cedar") || id.contains("yab")
    }
    static var isInUse: Bool {
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return false }
        let events: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]
        return events.contains { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < 60 }
    }

    static func host(in pid: pid_t) -> String? {
        guard isInUse else { return nil }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        // Chromium enables its native accessibility tree when a client queries the application role.
        guard value(root, kAXRoleAttribute) as? String == "AXApplication" else { return nil }
        let window: AXUIElement
        if let focused = value(root, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            window = unsafeDowncast(focused, to: AXUIElement.self)
        } else if let windows = value(root, kAXWindowsAttribute) as? [AXUIElement], windows.count == 1,
                  let only = windows.first {
            window = only
        } else { return nil }
        var queue = [window]
        var index = 0
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(650))
        var hosts = Set<String>()
        while index < queue.count, index < 120, ContinuousClock.now < deadline {
            let element = queue[index]
            index += 1
            let role = value(element, kAXRoleAttribute) as? String
            if role == "AXWebArea" {
                if let domain = domain(value(element, kAXURLAttribute)) { hosts.insert(domain) }
                continue
            }
            // Some browsers expose the current URL on their window, others on
            // the address field. Never inspect web content or arbitrary text.
            if element == window, let domain = domain(value(element, kAXDocumentAttribute)) { hosts.insert(domain) }
            if role == "AXTextField" || role == "AXComboBox" {
                let identifier = (value(element, kAXIdentifierAttribute) as? String ?? "").lowercased()
                let description = (value(element, kAXRoleDescriptionAttribute) as? String ?? "").lowercased()
                if identifier.contains("url") || identifier.contains("address") || description.contains("address") {
                    if let domain = domain(value(element, kAXValueAttribute)) { hosts.insert(domain) }
                }
            }
            let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            queue.append(contentsOf: children.prefix(max(0, 120 - queue.count)))
        }
        return hosts.count == 1 ? hosts.first : nil
    }

    private static func domain(_ raw: CFTypeRef?) -> String? {
        let text: String
        if let url = raw as? URL { text = url.absoluteString }
        else if let string = raw as? String { text = string }
        else { return nil }
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme), let host = url.host() else { return nil }
        return try? Domain.parse(host)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
}
