import Foundation
import AppKit
import SteadfastCore

@main struct CheckModel {
    @MainActor static func main() {
        let model = Model()
        model.text = "https://www.example.com/path x.com;\nsub.x.com,example.com"
        precondition(model.addCustomSites())
        precondition(model.text.isEmpty && model.chosen.contains("example.com") && model.chosen.contains("x.com"))
        precondition(model.validateSites())
        precondition(model.reviewedDomains == ["example.com", "x.com"], "review must normalize duplicates and subdomains")
        model.text = "localhost"
        let previous = model.chosen
        precondition(!model.addCustomSites() && model.chosen == previous && model.text == "localhost", "invalid additions must preserve the draft")
        model.clearSelection()
        precondition(!model.hasSelection && model.reviewedDomains.isEmpty)
        model.text = "example.com"
        precondition(model.validateSites())
        precondition(model.siteCountLabel == "1 website")
        model.amount = 0
        precondition(model.validateSites(), "site navigation must not validate duration")
        model.closeComposer(); model.openComposer()
        precondition(model.validateSites(), "reopening must not trap a draft with an invalid duration")
        precondition(!model.validateDuration())
        for value in [Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
            model.amount = value
            precondition(model.durationLabel == "custom duration")
            precondition(!model.validateDuration())
        }
        model.multiplier = 1
        model.amount = 1
        precondition(model.durationLabel == "1 minute" && model.validateDuration())
        model.amount = 1.9
        precondition(model.minutes == 1.9 && model.durationLabel == "1.9 minutes", "display must not truncate fractional durations")
        model.amountText = "not a number"
        precondition(model.amount.isNaN && !model.validateDuration(), "invalid text must never retain the previous numeric value")
        model.amountText = ""
        precondition(model.amount.isNaN && !model.validateDuration())
        model.amount = 1.5; model.multiplier = 60
        precondition(model.minutes == 90 && model.durationLabel == "90 minutes" && model.validateDuration())
        model.amount = 365; model.multiplier = 1440
        precondition(model.durationLabel == "365 days" && model.validateDuration())
        model.amount = 366
        precondition(!model.validateDuration())
        model.panel = .commitment; model.busy = true
        model.openComposer(); model.closeComposer()
        precondition(model.panel == .commitment, "menus and closing must not replace an in-flight commitment")
        model.busy = false; model.closeComposer()
        precondition(model.panel == nil && model.chosen == ["example.com"], "closing a draft must keep the selected sites")
        var policy = Policy()
        let past = Date().addingTimeInterval(-120)
        try! policy.commit(["expired.example"], minutes: 1, at: past)
        model.snapshot = Snapshot(policy: policy, now: past, sandbox: false, enforcementError: nil)
        precondition(model.active.isEmpty, "offline snapshots must not keep expired blocks active in the UI")
        model.connected = true; model.connecting = false
        precondition(model.statusLabel == "Ready to block")
        model.snapshot = Snapshot(policy: policy, now: Date(), sandbox: false, enforcementError: "fixture failure")
        precondition(!model.serviceReady && model.statusLabel == "Protection needs attention")
        model.serviceDisconnected()
        precondition(!model.connected, "an unhealthy service disconnect must trigger recovery")
        model.connected = true
        model.snapshot = Snapshot(policy: Policy(), now: Date(), sandbox: false, enforcementError: nil)
        model.serviceDisconnected()
        precondition(model.connected, "a clean, empty service may leave memory without an error")
        model.snapshot = Snapshot(policy: policy, now: past, sandbox: false, enforcementError: nil)
        model.serviceDisconnected()
        precondition(!model.connected, "an active last reply cannot prove that expiry cleanup finished")
        var active = Policy()
        try! active.commit(["example.com"], minutes: 30, at: Date())
        model.snapshot = Snapshot(policy: active, now: Date(), sandbox: false, enforcementError: nil)
        model.chosen = []; model.text = "example.com"
        precondition(!model.addCustomSites(), "custom input must not add an already blocked domain")
        model.connected = false
        precondition(model.statusLabel != "Blocking is not active", "a disconnected client cannot assert that DNS blocking stopped")
        let start = Date()
        var saved = Policy()
        try! saved.commit(["saved.example"], minutes: 1.9, at: start.addingTimeInterval(1))
        let confirmation = Snapshot(policy: saved, now: start.addingTimeInterval(2), sandbox: false, enforcementError: nil)
        model.panel = .commitment
        precondition(!model.reconcileCommit(confirmation, domains: ["different.example"], minutes: 1.9, since: start))
        precondition(!model.reconcileCommit(confirmation, domains: ["saved.example"], minutes: 2, since: start))
        precondition(!model.reconcileCommit(confirmation, domains: ["saved.example"], minutes: 1.9, since: start.addingTimeInterval(2)))
        precondition(model.panel == .commitment, "an unrelated or older block must not dismiss the draft")
        model.reviewedDomains = ["saved.example"]; model.chosen = ["saved.example"]
        precondition(model.reconcileCommit(confirmation, domains: ["saved.example"], minutes: 1.9, since: start))
        precondition(model.panel == nil && model.connected, "a confirmed saved block must finish the draft after a lost reply")
        precondition(model.reviewedDomains == ["saved.example"], "the departing review must remain intact until its closing transition finishes")
        model.clearCompletedDraft()
        precondition(model.chosen.isEmpty && model.reviewedDomains.isEmpty && model.minutes == 60)
        model.openComposer(); model.chosen = ["fresh.example"]
        model.clearCompletedDraft()
        precondition(model.chosen == ["fresh.example"], "a departing view must not clear a new draft")
        model.closeComposer()
        model.panel = .commitment; model.chosen = ["saved.example"]
        precondition(model.reconcileCommit(confirmation, domains: ["saved.example"], minutes: 1.9, since: start))
        model.openComposer()
        precondition(model.chosen.isEmpty && model.panel == .websites, "reopening before disappearance must clear a completed draft")
        var ending = Policy()
        let recent = Date().addingTimeInterval(-55)
        try! ending.commit(["ending.example"], minutes: 1, at: recent)
        model.snapshot = Snapshot(policy: ending, now: Date(), sandbox: false, enforcementError: nil)
        model.connected = true
        model.serviceDisconnected()
        precondition(!model.connected, "active service loss must trigger recovery")
        let draft = Model()
        draft.panel = nil
        precondition(!draft.reviewDraft() && draft.panel == nil, "an empty draft must not open a review")
        draft.openComposer()
        precondition(draft.panel == .websites && draft.chosen.isEmpty, "choosing websites must not select or block anything by default")
        draft.text = "https://example.org/path"
        draft.closeComposer()
        precondition(draft.hasSelection && draft.selectionLabel == "finish choosing websites" &&
                     draft.selectionSummary.contains("draft: https://example.org/path"),
                     "closing a picker must expose typed-but-unadded websites in the draft summary")
        draft.chosen = ["facebook.com", "instagram.com", "mastodon.social", "snapchat.com",
                        "threads.net", "tiktok.com", "twitter.com", "x.com", "youtube.com"]
        precondition(draft.selectionSummary.hasPrefix("draft: https://example.org/path"),
                     "pending websites must remain visible ahead of a long selected-site summary")
        draft.chosen = []
        precondition(draft.validateSites())
        precondition(draft.selectionLabel == "1 website selected" && draft.selectionSummary == "example.org")
        draft.closeComposer()
        draft.multiplier = 1; draft.amount = 30
        precondition(draft.chosen == ["example.org"] && draft.panel == nil, "website selection must return to the setup workspace")
        precondition(draft.reviewDraft() && draft.panel == .commitment)
        precondition(draft.reviewedDomains == ["example.org"] && draft.minutes == 30 && draft.active.isEmpty,
                     "reviewing a draft must preserve its duration without starting a block")
        draft.closeComposer()
        draft.amountText = "not a number"
        precondition(!draft.reviewDraft() && draft.panel == nil && draft.chosen == ["example.org"] && draft.error != nil,
                     "an invalid duration must leave the draft editable on the dashboard")
        draft.amount = 0
        precondition(!draft.reviewDraft() && draft.panel == nil)
        draft.amount = 525_601
        precondition(!draft.reviewDraft() && draft.panel == nil)
        draft.amount = 90
        precondition(draft.reviewDraft() && draft.durationLabel == "90 minutes")
        draft.busy = true
        draft.openComposer(); draft.closeComposer()
        precondition(!draft.reviewDraft() && draft.panel == .commitment, "busy review must not be replaced by another draft")
        draft.busy = false; draft.closeComposer(); draft.openComposer()
        precondition(draft.chosen == ["example.org"] && draft.minutes == 90 && draft.panel == .websites,
                     "editing or closing a review must preserve the draft's websites and duration")
        draft.closeComposer()
        draft.chosen = ["reddit.com", "old.reddit.com"]; draft.amount = 0
        precondition(!draft.reviewDraft() && draft.panel == nil && draft.chosen == ["reddit.com"] && draft.error != nil,
                     "site normalization must not hide an invalid-duration error")
        let savedWithError = Model()
        let errorStart = Date()
        var errorPolicy = Policy()
        try! errorPolicy.commit(["error.example"], minutes: 30, at: errorStart)
        savedWithError.chosen = ["error.example"]; savedWithError.amount = 30; savedWithError.multiplier = 1
        savedWithError.panel = .commitment
        let errorReply = Snapshot(policy: errorPolicy, now: errorStart, sandbox: true, enforcementError: "fixture failure")
        precondition(savedWithError.reconcileCommit(errorReply, domains: ["error.example"], minutes: 30, since: errorStart))
        savedWithError.clearCompletedDraft()
        precondition(!savedWithError.hasSelection && savedWithError.minutes == 60 && savedWithError.success == nil,
                     "a saved commitment with an enforcement error must still reset the completed draft")
        // App blocking
        let apps = Model()
        let telegram = BlockedApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram")
        apps.chosenApps = [telegram, BlockedApp(bundleID: "RU.KEEPCODER.TELEGRAM", name: "Telegram")]
        precondition(apps.chosenApps.count == 1, "the same app in a different case is one selection")
        precondition(apps.hasSelection && apps.hasDraftTargets && apps.draftTargetLabel == "1 app")
        apps.amount = 30; apps.multiplier = 1
        precondition(apps.validateSites() && apps.reviewedApps == [telegram] && apps.reviewedDomains.isEmpty,
                     "an app-only draft must be reviewable")
        precondition(apps.validateDuration() && apps.reviewedTargetLabel == "1 app")
        apps.chosen = ["x.com"]
        precondition(apps.validateSites() && apps.reviewedTargetLabel == "1 website · 1 app")
        apps.chosenApps.insert(BlockedApp(bundleID: "com.apple.finder", name: "Finder"))
        precondition(!apps.validateSites() && apps.error != nil, "protected apps must be refused before review")
        apps.clearSelection()
        precondition(!apps.hasSelection && apps.chosenApps.isEmpty && apps.reviewedApps.isEmpty, "clearing must drop apps too")
        let appStart = Date()
        var appPolicy = Policy()
        try! appPolicy.commit([], apps: [telegram], minutes: 30, at: appStart)
        let appReply = Snapshot(policy: appPolicy, now: appStart, sandbox: true, enforcementError: nil)
        apps.panel = .commitment
        precondition(!apps.reconcileCommit(appReply, domains: [], minutes: 30, since: appStart),
                     "a lost reply must not match a block with different apps")
        precondition(apps.reconcileCommit(appReply, domains: [], apps: [telegram], minutes: 30, since: appStart))
        precondition(apps.appUnlocks.map(\.app) == [telegram] && apps.hasActiveBlocks && apps.websiteUnlocks.isEmpty,
                     "an app-only block counts as an active block")
        precondition(apps.blockedAppKeys == ["ru.keepcoder.telegram"])
        let finished = appPolicy.commitments[0]
        precondition(finished.displayName == "Telegram" && finished.targetLabel == "1 app")
        print("model regression checks passed")
    }
}
