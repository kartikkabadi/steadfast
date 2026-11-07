import Foundation
import AppKit
import SteadfastCore

@main struct ExperienceCheck {
    @MainActor static func main() async throws {
        guard let service = ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"],
              service.hasPrefix("dev.local.steadfast.test."), CommandLine.arguments.count == 2 else {
            throw Failure("experience checks require an isolated service and storage folder")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let savedURL = directory.appending(path: "outcomes.json")
        let store = OutcomeStore(url: savedURL)
        let model = Model(outcomes: store)
        let previousOnboarding = model.hasCompletedOnboarding
        defer { model.hasCompletedOnboarding = previousOnboarding }
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(message) }
            print("pass: \(message)")
            fflush(stdout)
        }

        await model.refresh()
        try check(model.serviceReady && model.snapshot?.sandbox == true, "real app model connects to the isolated XPC service")
        model.hasCompletedOnboarding = false
        model.panel = .onboarding
        model.completeOnboarding()
        try check(model.hasCompletedOnboarding && !model.composing && model.active.isEmpty, "setup can be skipped with no history, permissions, or commitment")
        try check(store.activityEnabled && store.websiteTrackingEnabled && store.aim == nil,
                  "fresh setup enables local app and website history without requiring an aim or external app")
        store.activityEnabled = false
        try check(!store.trackingEnabled && !store.websiteTrackingEnabled,
                  "one activity choice turns off both app and website history")
        store.activityEnabled = true
        let activityReloaded = OutcomeStore(url: savedURL)
        try check(activityReloaded.trackingEnabled && activityReloaded.websiteTrackingEnabled,
                  "one activity choice restores both app and website history and survives a disk reload")

        model.startDraft()
        model.chosen = ["x.com", "twitter.com"]
        model.setDuration(1)
        model.draftPurpose = "Think through my next step"
        try check(model.reviewDraft() && model.panel == .commitment && model.active.isEmpty, "review shows a named draft without starting a lock")
        model.closeComposer()
        try check(model.chosen.contains("x.com") && model.draftPurpose == "Think through my next step", "back from review preserves the person's choices")
        model.composing = false
        model.startDraft()
        try check(model.draftPurpose == "Think through my next step", "returning to an unfinished draft preserves its purpose")
        try check(model.reviewDraft(), "preserved draft can be reviewed again")
        await model.commit()
        try check(model.error == nil && model.active.count == 1 && !model.composing && model.panel == nil, "confirmation starts a real one-minute commitment and closes the editor")
        let block = try model.active.first.unwrap("missing committed block")
        try check(block.name == "Think through my next step", "the service persists the chosen purpose using the existing policy format")
        model.clearCompletedDraft()
        try check(!model.hasDraftTargets && model.draftPurpose.isEmpty, "completed draft clears for the next visit")
        try check(model.latestUnreviewedBlock == nil, "a running block never asks for completion feedback")

        let routine = Routine(name: "Quiet reading", domains: ["reddit.com"], minutes: 30)
        try check(await model.saveRoutine(routine), "a routine saves through real XPC")
        model.startDraft()
        model.chosen = ["example.org"]
        model.draftPurpose = "A draft to keep"
        model.setDuration(45)
        model.composing = false
        model.prepareRoutine(routine)
        try check(model.panel == .commitment && model.minutes == 30, "a routine opens the shared review")
        model.closeComposer()
        try check(model.chosen == ["example.org"] && model.minutes == 45 && model.draftPurpose == "A draft to keep", "canceling routine review restores the earlier draft")
        model.startDraft()
        model.chosen = []
        try check(!model.reviewDraft() && model.panel == nil && model.error != nil, "empty selection cannot open a commitment review")
        model.error = nil
        model.chosen = ["example.org"]
        model.setDuration(0)
        try check(!model.reviewDraft() && model.panel == nil, "invalid duration does not reach confirmation")
        model.connected = false
        await model.commit()
        try check(model.active.count == 1, "disconnection cannot submit another commitment")
        await model.refresh()
        model.composing = false
        model.clearSelection()

        print("waiting for real one-minute expiry…")
        fflush(stdout)
        try await Task.sleep(for: .seconds(max(0, block.endsAt.timeIntervalSinceNow) + 2))
        await model.refresh()
        try check(model.active.isEmpty && model.lastBlock?.id == block.id, "expired commitment appears in real history")
        try check(model.latestUnreviewedBlock?.id == block.id, "returning home offers optional feedback on the last block")
        store.reflect(on: block.id, answer: .helped, note: "I chose a direction.")
        try check(model.latestUnreviewedBlock == nil, "answering feedback dismisses it without a required journal")
        let reloaded = OutcomeStore(url: savedURL)
        try check(reloaded.reflections.first?.answer == .helped && reloaded.reflections.first?.note == "I chose a direction.", "reflection survives a fresh disk load")
        let returned = Model(outcomes: reloaded)
        await returned.refresh()
        try check(returned.latestUnreviewedBlock == nil, "a later visit does not repeat a saved reflection")
        returned.reuseBlock(block)
        try check(returned.panel == .commitment && returned.draftPurpose == block.name && returned.active.isEmpty, "repeat opens review with the original purpose and does not silently lock")
        returned.closeComposer()
        reloaded.reflect(on: block.id, answer: .skipped)
        try check(returned.latestUnreviewedBlock == nil, "skip is persistent and does not become overdue work")

        // Exercise the new presentation with a real legacy outcome file.
        let legacyURL = directory.appending(path: "legacy-outcomes.json")
        try Data(#"{"estimates":[],"trackingEnabled":false,"days":[]}"#.utf8).write(to: legacyURL)
        let legacy = OutcomeStore(url: legacyURL)
        try check(legacy.reflections.isEmpty && !legacy.trackingEnabled && legacy.saveError == nil, "old outcome files load without migration or tracking changes")
        legacy.aim = Aim(title: "A quiet evening", kind: .calm)
        try check(OutcomeStore(url: legacyURL).aim?.title == "A quiet evening", "editing an aim preserves compatible local storage")

        let damagedURL = directory.appending(path: "damaged-outcomes.json")
        let damaged = Data("{invalid".utf8)
        try damaged.write(to: damagedURL)
        let unreadable = OutcomeStore(url: damagedURL)
        unreadable.aim = Aim(title: "A quiet evening", kind: .calm)
        try check(unreadable.saveError != nil && Data(contentsOf: damagedURL) == damaged, "an unreadable outcome file is reported and never overwritten")

        let occupied = directory.appending(path: "occupied")
        try Data("file".utf8).write(to: occupied)
        let unavailable = OutcomeStore(url: occupied.appending(path: "outcomes.json"))
        unavailable.reflect(on: block.id, answer: .helped, note: "Keep this if saved")
        try check(unavailable.saveError != nil && unavailable.reflections.isEmpty, "a real disk-write failure stays visible and leaves reflection available to retry")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8))!
        let overnight = Commitment(domains: ["example.com"], createdAt: midnight.addingTimeInterval(-3600), endsAt: midnight.addingTimeInterval(3600))
        let overlap = Commitment(domains: ["other.example"], createdAt: midnight, endsAt: midnight.addingTimeInterval(7200))
        let facts = ProgressFacts(commitments: [overnight, overlap], aim: nil, now: midnight.addingTimeInterval(7200), calendar: calendar)
        try check(abs(facts.yearHours - 3) < 0.0001 && facts.coveredDays == 2, "real progress presentation includes night hours and counts overlaps once")
        let long = Commitment(domains: ["x.com"], createdAt: midnight, endsAt: midnight.addingTimeInterval(7 * 86_400))
        let longFacts = ProgressFacts(commitments: [long], aim: nil, now: midnight.addingTimeInterval(86_400), calendar: calendar)
        try check(longFacts.yearHours == 24 && longFacts.coveredDays == 1, "a week-long boundary records elapsed coverage without crediting future time")
        try check(AppNoticeView.reason(Aim(title: "Time to think", kind: .other, cost: "A private concern")) == "Making room for: Time to think", "blocked-app support uses the person's purpose instead of replaying regret")
        try check(AppNoticeView.reason(nil, purpose: "Read a chapter") == "Making room for: Read a chapter", "a named block supplies its own reason without a global aim")
        print("experience checks passed")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else { throw Failure(message) }
        return self
    }
}
