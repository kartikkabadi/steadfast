import AppKit
import Observation
import SwiftUI
import SteadfastCore

/// An app found in one of the Applications folders.
nonisolated struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let path: String
    let category: AppCategory
    var id: String { bundleID.lowercased() }
    var blocked: BlockedApp { BlockedApp(bundleID: bundleID, name: name) }
}

nonisolated enum AppCategory: String, CaseIterable, Sendable {
    case chat = "Chat & social"
    case games = "Games"
    case media = "Video & music"
    case browsers = "Browsers"
    case news = "News & reading"
    case ai = "AI tools"
    case other = "Other apps"
}

/// Known distracting apps by bundle identifier. Anything else falls back to the
/// App Store category the app declares, then to "Other apps".
nonisolated enum AppPresets {
    static let categories: [String: AppCategory] = {
        var map: [String: AppCategory] = [:]
        func add(_ category: AppCategory, _ ids: [String]) { for id in ids { map[id.lowercased()] = category } }
        add(.chat, ["com.hnc.Discord", "com.tinyspeck.slackmacgap", "ru.keepcoder.Telegram", "org.telegram.desktop",
                    "net.whatsapp.WhatsApp", "desktop.WhatsApp", "com.apple.MobileSMS", "org.whispersystems.signal-desktop",
                    "com.apple.FaceTime", "com.microsoft.teams2", "us.zoom.xos", "com.facebook.archon"])
        add(.games, ["com.valvesoftware.steam", "com.epicgames.EpicGamesLauncher", "com.apple.Chess", "com.apple.games",
                     "net.battle.app", "com.mojang.minecraftlauncher", "com.felixrum.supertribes"])
        add(.media, ["com.spotify.client", "com.apple.Music", "com.apple.TV", "com.apple.podcasts", "org.videolan.vlc",
                     "com.colliderli.iina", "com.amazon.aiv.AIVApp", "tv.plex.desktop", "me.paolino.fastpotify"])
        add(.browsers, ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
                        "company.thebrowser.dia", "com.brave.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera",
                        "com.vivaldi.Vivaldi", "net.imput.helium", "app.zen-browser.zen", "org.chromium.Chromium"])
        add(.news, ["com.apple.news", "com.apple.iBooksX", "com.apple.stocks"])
        add(.ai, ["com.openai.chat", "com.openai.codex", "com.anthropic.claudefordesktop", "com.google.GeminiMacOS",
                  "ai.perplexity.mac", "ai.perplexity.macv3", "com.meta.endo.vanilla"])
        return map
    }()

    /// Shown as one-click tiles when installed, in this order.
    static let popular = ["com.hnc.Discord", "com.valvesoftware.steam", "com.apple.MobileSMS", "com.spotify.client",
                          "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp", "com.tinyspeck.slackmacgap",
                          "com.apple.TV", "com.apple.Music", "com.apple.news", "com.epicgames.EpicGamesLauncher",
                          "com.apple.games"].map { $0.lowercased() }

    static func category(bundleID: String, declared: String?) -> AppCategory {
        if let known = categories[bundleID.lowercased()] { return known }
        guard let declared = declared?.lowercased() else { return .other }
        if declared.contains("web-browser") { return .browsers }
        if declared.contains("games") { return .games }
        if declared.hasSuffix(".social-networking") { return .chat }
        if declared.hasSuffix(".entertainment") || declared.hasSuffix(".music") || declared.hasSuffix(".video") { return .media }
        if declared.hasSuffix(".news") || declared.hasSuffix(".books") || declared.hasSuffix(".magazines-and-newspapers") { return .news }
        return .other
    }
}

@Observable final class AppCatalog {
    static let shared = AppCatalog()
    private(set) var apps: [InstalledApp] = []
    private(set) var loaded = false
    private var loading = false
    @ObservationIgnored private var loadedAt = Date.distantPast
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    func app(for bundleID: String) -> InstalledApp? { apps.first { $0.id == bundleID.lowercased() } }

    /// Scans once, then again when asked after a minute, so newly installed apps appear.
    func load() {
        guard !loading, !loaded || Date().timeIntervalSince(loadedAt) > 60 else { return }
        loading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { Self.scan() }.value
            if found != apps { apps = found }
            loaded = true; loading = false; loadedAt = Date()
        }
    }

    /// The app's icon, from its install location or from Launch Services when it was chosen elsewhere.
    func icon(for bundleID: String, path: String? = nil) -> NSImage {
        let key = bundleID.lowercased()
        if let cached = icons[key] { return cached }
        let location = path ?? app(for: bundleID)?.path
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        let image = location.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        image.size = NSSize(width: 64, height: 64)
        icons[key] = image
        return image
    }

    /// Reads an app bundle the way the service does, including iPhone and iPad apps.
    nonisolated static func describe(_ url: URL, includeAgents: Bool = true) -> InstalledApp? {
        // The same reader the service uses, so the picker and enforcement agree on identifiers.
        guard let info = SafeFile.infoPlistLocations.lazy.compactMap({ SafeFile.infoPlist(atPath: url.path + "/" + $0) }).first,
              let raw = info["CFBundleIdentifier"] as? String,
              let valid = try? AppRule.validated(BlockedApp(bundleID: raw, name: "app")) else { return nil }
        func flag(_ key: String) -> Bool { (info[key] as? Bool) ?? ((info[key] as? String).map { $0 == "1" || $0.lowercased() == "yes" } ?? false) }
        // Menu bar helpers and background agents are not apps people open to get distracted.
        if !includeAgents, flag("LSUIElement") || flag("LSBackgroundOnly") { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        let shown = (try? AppRule.validated(BlockedApp(bundleID: valid.bundleID, name: name)).name) ?? valid.bundleID
        return InstalledApp(bundleID: valid.bundleID, name: shown, path: url.path,
                            category: AppPresets.category(bundleID: valid.bundleID, declared: info["LSApplicationCategoryType"] as? String))
    }

    nonisolated static func scan() -> [InstalledApp] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let roots = [URL(filePath: "/Applications"), URL(filePath: "/System/Applications"), home.appending(path: "Applications")]
        var found: [String: InstalledApp] = [:]
        var visited = 0
        func visit(_ folder: URL, depth: Int) {
            guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                                 options: [.skipsHiddenFiles]) else { return }
            for entry in entries {
                // Bounded, so a huge folder can't make the picker hang.
                visited += 1
                guard visited <= 5000 else { return }
                if entry.pathExtension.lowercased() == "app" {
                    guard let app = describe(entry, includeAgents: false), found[app.id] == nil else { continue }
                    found[app.id] = app
                } else if depth < 2, (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(entry, depth: depth + 1)
                }
            }
        }
        for root in roots { visit(root, depth: 0) }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// An app's real icon, at a size that matches the row it sits in.
struct AppIcon: View {
    let bundleID: String
    var path: String? = nil
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: AppCatalog.shared.icon(for: bundleID, path: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
