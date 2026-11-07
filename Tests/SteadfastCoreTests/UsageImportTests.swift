import Foundation
import Testing
@testable import SteadfastCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Test func domainKeysPreferKnownRulesThenRegistrable() {
    #expect(UsageKeys.domain("www.youtube.com") == "youtube.com")
    #expect(UsageKeys.domain("m.youtube.com") == "youtube.com")
    #expect(UsageKeys.domain("news.ycombinator.com") == "ycombinator.com")
    #expect(UsageKeys.domain("news.ycombinator.com", known: ["news.ycombinator.com", "ycombinator.com"]) == "news.ycombinator.com")
    #expect(UsageKeys.domain("www.bbc.co.uk") == "bbc.co.uk")
    #expect(UsageKeys.domain("x.com.") == "x.com")
    #expect(UsageKeys.isExcludedApp("dev.local.steadfast"))
    #expect(UsageKeys.isExcludedApp("com.apple.ScreenSaver.Engine"))
    #expect(!UsageKeys.isExcludedApp("com.apple.Safari"))
}

@Test func usageTotalsAndSinkEstimates() {
    let days = [UsageDay(day: "2026-11-01", apps: ["com.hnc.discord": 600], domains: ["x.com": 1200]),
                UsageDay(day: "2026-11-05", apps: ["com.hnc.discord": 300, "com.apple.finder": 60], domains: ["x.com": 600])]
    let totals = UsageSummary.totals(days, since: "2026-11-02")
    #expect(totals.map(\.key) == ["x.com", "com.hnc.discord", "com.apple.finder"])
    #expect(totals[0].seconds == 600 && !totals[0].isApp)

    let estimates = UsageSummary.estimates([(.social, 3600), (.chat, 1200), (nil, 9999), (.social, 600)], days: 7, source: .legacyImport)
    #expect(estimates.map(\.sink) == [.social, .chat])
    #expect(abs(estimates[0].minutesPerDay - 10) < 0.001)
    #expect(estimates.allSatisfy { $0.source == .legacyImport })
}

@Test func distractingCombinesBlockedAndClassified() {
    let keys: [(key: String, isApp: Bool)] = [("old.reddit.com", false), ("github.com", false), ("com.hnc.discord", true), ("com.apple.finder", true)]
    let set = UsageSummary.distracting(keys: keys, blockedDomains: ["reddit.com"], blockedApps: ["com.valvesoftware.steam"]) { key, isApp in
        isApp && key == "com.hnc.discord"
    }
    #expect(set == ["reddit.com", "old.reddit.com", "com.valvesoftware.steam", "com.hnc.discord"])
    let days = [UsageDay(day: "a", apps: ["com.hnc.discord": 600], domains: ["old.reddit.com": 600]),
                UsageDay(day: "b", apps: ["com.hnc.discord": 600]), UsageDay(day: "c", apps: ["com.apple.finder": 60])]
    let figure = Ledger.dailyMinutes(estimates: [], measuredDays: days, distracting: set)
    #expect(figure?.source == .measured)
    #expect(abs((figure?.minutes ?? 0) - 10) < 0.001)
}
