import Foundation
import AppKit
import SteadfastCore

@main struct ActivityCheck {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure("temporary output folder required") }
        let folder = URL(filePath: CommandLine.arguments[1])
        let file = folder.appending(path: "activity.json")
        let store = OutcomeStore(url: file)
        store.refreshWebsiteAccess()
        guard store.websiteAccessGranted else { throw Failure("live activity check needs existing Accessibility access; no permission was requested") }
        let deadline = Date().addingTimeInterval(180)
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "org.steadfast.activitybrowser" {
            guard Date() < deadline else { throw Failure("disposable browser did not become active") }
            try await Task.sleep(for: .milliseconds(200))
        }
        store.websiteTrackingEnabled = true
        store.trackingEnabled = true
        store.start()
        print("ready: recording the disposable browser; switch to example.org after 12 seconds")
        fflush(stdout)
        while !Set(store.sessions.compactMap(\.domain)).isSuperset(of: ["example.com", "example.org"]) {
            guard Date() < deadline else { throw Failure("both browser domains were not captured through live Accessibility") }
            try await Task.sleep(for: .seconds(1))
        }
        store.trackingEnabled = false
        let count = store.sessions.count
        let seconds = store.days.reduce(0) { $0 + $1.total }
        try await Task.sleep(for: .seconds(7))
        guard store.sessions.count == count, store.days.reduce(0, { $0 + $1.total }) == seconds else { throw Failure("paused history kept recording") }
        let loaded = OutcomeStore(url: file)
        let persisted = loaded.sessions.count == store.sessions.count && zip(loaded.sessions, store.sessions).allSatisfy { saved, live in
            saved.id == live.id && saved.appID == live.appID && saved.domain == live.domain && saved.appName == live.appName
                && abs(saved.startedAt.timeIntervalSince(live.startedAt)) < 1
                && abs(saved.endedAt.timeIntervalSince(live.endedAt)) < 1
        }
        guard persisted, !loaded.trackingEnabled, store.saveError == nil else { throw Failure("activity or pause did not persist") }
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        guard permissions == 0o600 else { throw Failure("activity file is not private to its owner") }
        let websiteSeconds = loaded.days.flatMap { $0.domains.values }.reduce(0, +)
        guard websiteSeconds > 0, websiteSeconds <= seconds + 0.01,
              loaded.sessions.allSatisfy({ $0.domain == nil || !$0.domain!.contains("/") }) else { throw Failure("website totals or domain privacy failed") }
        store.websiteTrackingEnabled = false
        store.trackingEnabled = true
        store.start()
        let before = store.days.flatMap { $0.domains.values }.reduce(0, +)
        try await Task.sleep(for: .seconds(12))
        store.trackingEnabled = false
        guard store.days.flatMap({ $0.domains.values }).reduce(0, +) == before else { throw Failure("website opt-out kept recording domains") }
        guard store.days.reduce(0, { $0 + $1.total }) > seconds else { throw Failure("app-only mode did not record real foreground time") }
        store.eraseTally()
        let cleared = OutcomeStore(url: file)
        guard cleared.days.isEmpty, cleared.sessions.isEmpty else { throw Failure("deleted history returned after reload") }
        print("passed: real foreground app time, two live AX website domains, local reload, pause, website opt-out, and deletion")
        fflush(stdout)
    }
}
