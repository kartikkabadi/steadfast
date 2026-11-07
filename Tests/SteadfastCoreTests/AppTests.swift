import Foundation
import Testing
@testable import SteadfastCore

private let discord = BlockedApp(bundleID: "com.hnc.Discord", name: "Discord")
private let steam = BlockedApp(bundleID: "com.valvesoftware.steam", name: "Steam")

@Test func bundlePathsIncludeEveryEnclosingAppOutermostFirst() {
    #expect(AppBundles.bundlePaths(forExecutable: "/Applications/Discord.app/Contents/MacOS/Discord") == ["/Applications/Discord.app"])
    #expect(AppBundles.bundlePaths(forExecutable: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)")
            == ["/Applications/Discord.app", "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app"])
    #expect(AppBundles.bundlePaths(forExecutable: "/usr/bin/true").isEmpty)
    #expect(AppBundles.bundlePaths(forExecutable: "/Users/me/my.application/bin/tool").isEmpty)
    #expect(AppBundles.bundlePaths(forExecutable: "/Applications/Odd.APP/Contents/MacOS/Odd") == ["/Applications/Odd.APP"])
}

@Test func matcherFindsHelpersNestedAppsAndIgnoresCase() {
    let ids = [
        "/Applications/Discord.app": "com.hnc.Discord",
        "/Applications/Discord.app/Contents/Frameworks/Discord Helper.app": "com.hnc.Discord.helper",
        "/Applications/Xcode.app": "com.apple.dt.Xcode",
        "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app": "com.apple.iphonesimulator"
    ]
    let matcher = AppMatcher(blocked: ["COM.HNC.DISCORD", "com.apple.iphonesimulator"])
    #expect(matcher.match(executable: "/Applications/Discord.app/Contents/Frameworks/Discord Helper.app/Contents/MacOS/Discord Helper", bundleID: { ids[$0] }) == "com.hnc.discord")
    #expect(matcher.match(executable: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator", bundleID: { ids[$0] }) == "com.apple.iphonesimulator")
    #expect(matcher.match(executable: "/Applications/Xcode.app/Contents/MacOS/Xcode", bundleID: { ids[$0] }) == nil)
    #expect(matcher.match(executable: "/bin/zsh", bundleID: { ids[$0] }) == nil)
}

@Test func protectedAppsAreNeverMatchedOrAccepted() throws {
    let matcher = AppMatcher(blocked: ["com.apple.finder", "dev.local.steadfast", "com.apple.Terminal"])
    #expect(matcher.blocked.isEmpty)
    for id in ["com.apple.finder", "COM.APPLE.DOCK", "dev.local.steadfast", "com.apple.systempreferences", "com.apple.Terminal", "com.apple.coreservices.uiagent"] {
        #expect(AppRule.isProtected(id))
        #expect(throws: (any Error).self) { try AppRule.validated(BlockedApp(bundleID: id, name: "x")) }
    }
    #expect(!AppRule.isProtected("com.apple.Safari"))
    #expect(!AppRule.isProtected("com.apple.MobileSMS"))
}

@Test(arguments: ["", " ", "has space", "../etc", "a..b", ".lead", "trail.", String(repeating: "a", count: 256), "emoji😀.app"])
func rejectsInvalidBundleIdentifiers(_ id: String) {
    #expect(throws: (any Error).self) { try AppRule.validated(BlockedApp(bundleID: id, name: "App")) }
}

@Test func normalizationDeduplicatesIgnoringCaseAndSortsByName() throws {
    let apps = try AppRule.normalized([steam, BlockedApp(bundleID: "COM.HNC.DISCORD", name: "  Discord  "), discord])
    #expect(apps.map(\.name) == ["Discord", "Steam"])
    #expect(try AppRule.validated(BlockedApp(bundleID: "com.example.app", name: "  ")).name == "com.example.app")
}

@Test func appOnlyBlocksStartExpireAndRejectOverlap() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = Policy()
    #expect(throws: (any Error).self) { try policy.commit([], apps: [], minutes: 30, at: now) }
    try policy.commit([], apps: [discord], minutes: 30, at: now)
    #expect(policy.blocksApp("com.hnc.discord", at: now))
    #expect(!policy.blocks("discord.com", at: now))
    let original = policy.commitments
    #expect(throws: (any Error).self) { try policy.commit([], apps: [BlockedApp(bundleID: "COM.hnc.discord", name: "Discord")], minutes: 5, at: now) }
    #expect(policy.commitments == original)
    try policy.commit(["discord.com"], apps: [steam], minutes: 90, at: now)
    #expect(policy.blockedApps(at: now).keys.sorted() == ["com.hnc.discord", "com.valvesoftware.steam"])
    #expect(policy.blockedApps(at: now.addingTimeInterval(31 * 60)).keys.sorted() == ["com.valvesoftware.steam"])
    #expect(policy.blockedApps(at: now.addingTimeInterval(91 * 60)).isEmpty)
    #expect(throws: (any Error).self) { try policy.commit([], apps: [BlockedApp(bundleID: "com.apple.finder", name: "Finder")], minutes: 5, at: now) }
}

@Test func blockedAppsUseTheLatestDeadline() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = Policy()
    policy.commitments = [
        Commitment(domains: [], apps: [discord], createdAt: now, endsAt: now.addingTimeInterval(600)),
        Commitment(domains: [], apps: [discord], createdAt: now, endsAt: now.addingTimeInterval(3600)),
        Commitment(domains: [], apps: [discord], createdAt: now, endsAt: now.addingTimeInterval(60))
    ]
    #expect(policy.blockedApps(at: now)["com.hnc.discord"]?.until == now.addingTimeInterval(3600))
}

@Test func appCapacityIsBounded() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = Policy()
    let apps = (0..<AppRule.maximumApps).map { BlockedApp(bundleID: "com.example.app\($0)", name: "App \($0)") }
    try policy.commit([], apps: apps, minutes: 10, at: now)
    #expect(throws: (any Error).self) { try policy.commit([], apps: [BlockedApp(bundleID: "com.example.extra", name: "Extra")], minutes: 10, at: now) }
}

@Test func policiesAndRoutinesSavedBeforeAppBlockingStillDecode() throws {
    let legacy = #"""
    {"commitments":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","domains":["x.com"],"createdAt":0,"endsAt":60}],
     "routines":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"focus","domains":["x.com"],"minutes":30,"createdAt":0}]}
    """#
    let policy = try JSONDecoder().decode(Policy.self, from: Data(legacy.utf8))
    #expect(policy.commitments[0].apps.isEmpty && policy.routines[0].apps.isEmpty)
    let template = try JSONDecoder().decode(RoutineTemplate.self, from: Data(#"{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"focus","domains":["x.com"],"minutes":30}"#.utf8))
    #expect(template.apps.isEmpty)
    var withApps = Policy()
    try withApps.commit(["x.com"], apps: [discord], minutes: 5, at: Date())
    let round = try JSONDecoder().decode(Policy.self, from: JSONEncoder().encode(withApps))
    #expect(round.commitments[0].apps == [discord] && round.commitments[0].apps[0].name == "Discord")
}

@Test func routinesCarryAppsIntoScheduledBlocks() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let created = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = Policy()
    var routine = Routine(name: "games off", domains: [], apps: [steam], minutes: 60,
                          schedule: WeeklySchedule(weekdays: Array(1...7), startMinute: 0))
    routine.createdAt = created
    try policy.saveRoutine(routine, at: created)
    #expect(policy.routines[0].apps == [steam])
    var empty = policy
    #expect(throws: (any Error).self) { try empty.saveRoutine(Routine(name: "empty", domains: [], minutes: 30), at: created) }
    let start = calendar.startOfDay(for: created.addingTimeInterval(86_400))
    let started = policy.startScheduledBlocks(at: start.addingTimeInterval(5), calendar: calendar)
    #expect(started)
    #expect(policy.blocksApp("com.valvesoftware.steam", at: start.addingTimeInterval(10)))
    #expect(policy.routineTemplates[0].apps == [steam])
}

@Test func onlyAnAppsOwnExecutablesCount() {
    let owning = AppBundles.owningBundles
    #expect(owning("/Applications/Discord.app/Contents/MacOS/Discord") == ["/Applications/Discord.app"])
    #expect(owning("/Applications/Discord.app/Contents/Frameworks/Discord Helper.app/Contents/MacOS/Discord Helper").count == 2)
    // Command-line tools inside a bundle are left alone, so blocking Xcode never breaks git or clang.
    #expect(owning("/Applications/Xcode.app/Contents/Developer/usr/bin/git").isEmpty)
    #expect(owning("/Applications/Docker.app/Contents/Resources/bin/docker").isEmpty)
    #expect(owning("/Applications/Discord.app/Contents/Frameworks/Squirrel.framework/Resources/ShipIt").isEmpty)
    // iPhone and iPad apps keep their executable at the root of the inner bundle.
    #expect(owning("/Applications/Game.app/Wrapper/Game.app/Game") == ["/Applications/Game.app", "/Applications/Game.app/Wrapper/Game.app"])
    // Safari runs from the app cryptex, which is not part of the protected system locations.
    #expect(owning("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari").count == 1)
    #expect(owning("/System/Applications/Messages.app/Contents/MacOS/Messages").count == 1)
}

@Test(arguments: [
    "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
    "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/Thing.app/Contents/MacOS/Thing",
    "/usr/libexec/Thing.app/Contents/MacOS/Thing",
    "/Library/Apple/System/Library/Thing.app/Contents/MacOS/Thing",
    "/Applications/../System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
    "relative/Thing.app/Contents/MacOS/Thing",
    "/Applications//Thing.app/Contents/MacOS/Thing"
])
func systemAndMalformedPathsNeverMatch(_ path: String) {
    #expect(AppBundles.owningBundles(forExecutable: path).isEmpty)
    #expect(AppMatcher(blocked: ["com.example.thing"]).match(executable: path, bundleID: { _ in "com.example.thing" }) == nil)
}

@Test func appNamesAreCleanedForDisplay() throws {
    let tricky = BlockedApp(bundleID: "com.example.app", name: "Evil\u{202E}gnp.exe\n\tApp\u{0007}  Name")
    #expect(try AppRule.validated(tricky).name == "Evil gnp.exe App Name")
    #expect(try AppRule.validated(BlockedApp(bundleID: "com.example.app", name: String(repeating: "a", count: 200))).name.count == 80)
    #expect(try AppRule.validated(BlockedApp(bundleID: "com.example.app", name: "\u{200B}\u{0000}")).name == "com.example.app")
}

@Test func safeFileReadsOnlySmallRegularFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "steadfast-safefile-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let plist = folder.appending(path: "Info.plist")
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.app"], format: .xml, options: 0).write(to: plist)
    #expect(SafeFile.infoPlist(atPath: plist.path)?["CFBundleIdentifier"] as? String == "com.example.app")
    #expect(SafeFile.read(plist.path, limit: 10) == nil, "files over the limit are refused")
    let link = folder.appending(path: "link.plist")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: plist)
    #expect(SafeFile.read(link.path, limit: 4096) == nil, "a final symlink is never followed")
    let pipe = folder.appending(path: "pipe.plist")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    let start = Date()
    #expect(SafeFile.read(pipe.path, limit: 4096) == nil, "a pipe is refused without blocking")
    #expect(Date().timeIntervalSince(start) < 1)
    #expect(SafeFile.read(folder.path, limit: 4096) == nil, "a folder is refused")
    #expect(SafeFile.read(folder.appending(path: "missing").path, limit: 4096) == nil)
    let empty = folder.appending(path: "empty")
    try Data().write(to: empty)
    #expect(SafeFile.read(empty.path, limit: 10) == Data())
}

@Test func systemLocationsAreRecognized() {
    #expect(AppBundles.isSystemLocation("/System/Library/CoreServices/Ticket Viewer.app"))
    #expect(!AppBundles.isSystemLocation("/System/Applications/Chess.app"))
    #expect(!AppBundles.isSystemLocation("/Applications/Steam.app"))
}
