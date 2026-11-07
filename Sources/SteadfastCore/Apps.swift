import Foundation

/// A Mac app chosen for a block, identified by its bundle identifier.
/// Bundle identifiers are case-insensitive to macOS, so identity ignores case.
public struct BlockedApp: Codable, Hashable, Identifiable, Sendable {
    public let bundleID: String
    public let name: String
    public var id: String { key }
    /// The case-folded identifier used for matching.
    public var key: String { bundleID.lowercased() }

    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
    public static func == (lhs: BlockedApp, rhs: BlockedApp) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

public enum AppRule {
    public static let maximumApps = 100
    /// How long an app that is open when its block starts has to save before it closes.
    public static let gracePeriod: TimeInterval = 10

    /// Parts of macOS, and Steadfast itself, that a block may never close.
    /// Terminal stays available because Steadfast's own update and uninstall run in it.
    static let protectedIDs: Set<String> = [
        "dev.local.steadfast", "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
        "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.systempreferences", "com.apple.settings", "com.apple.terminal", "com.apple.activitymonitor",
        "com.apple.securityagent", "com.apple.windowmanager", "com.apple.spotlight", "com.apple.wallpaper",
        "com.apple.installer", "com.apple.softwareupdate", "com.apple.keychainaccess", "com.apple.diskutility",
        "com.apple.screensaver.engine", "com.apple.accessibility.universalaccessauthwarn",
        "com.apple.voiceover", "com.apple.voiceoverutility", "com.apple.backgroundtaskmanagementagent",
        "com.apple.screentimeagent", "com.apple.passwords", "com.apple.migrateassistant",
        "com.apple.bootcampassistant", "com.apple.systemprofiler", "com.apple.console",
        "com.apple.inputmethodkit.textreplacementservice"
    ]
    static let protectedPrefixes = [
        "dev.local.steadfast.", "com.apple.coreservices.", "com.apple.security.", "com.apple.loginwindow.",
        "com.apple.accessibility.", "com.apple.dock.", "com.apple.systemuiserver."
    ]

    public static func isProtected(_ bundleID: String) -> Bool {
        let key = bundleID.lowercased()
        return protectedIDs.contains(key) || protectedPrefixes.contains { key.hasPrefix($0) }
    }

    public static func validated(_ app: BlockedApp) throws -> BlockedApp {
        let id = app.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = id.utf8.allSatisfy { (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }
        guard (1...255).contains(id.utf8.count), characters, !id.hasPrefix("."), !id.hasSuffix("."), !id.contains("..") else {
            throw Failure("\(app.name.isEmpty ? "this app" : app.name) has no valid bundle identifier")
        }
        let name = displayName(app.name)
        guard !isProtected(id) else { throw Failure("\(name.isEmpty ? id : name) is part of macOS or Steadfast and can't be blocked") }
        return BlockedApp(bundleID: id, name: name.isEmpty ? id : name)
    }

    /// A name safe to show anywhere: no control, formatting or bidirectional override
    /// characters, single-spaced, and at most 80 characters.
    static func displayName(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                scalars.append(" ")
            default: scalars.append(scalar)
            }
        }
        let words = String(scalars).split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(80))
    }

    /// Validates, removes duplicates, and sorts by name.
    public static func normalized(_ apps: [BlockedApp]) throws -> [BlockedApp] {
        var seen = Set<String>()
        return try apps.map(validated).filter { seen.insert($0.key).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending || ($0.name == $1.name && $0.key < $1.key) }
    }
}

/// Decides which app bundles own a running executable.
public enum AppBundles {
    /// Locations that hold the operating system. Nothing running from here is ever closed,
    /// whatever its bundle identifier, so a bad rule can't take down part of macOS.
    static let systemLocations = [
        "/System/Library/", "/System/iOSSupport/", "/System/Volumes/Preboot/Cryptexes/OS/", "/System/Cryptexes/OS/",
        "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/Library/PrivilegedHelperTools/", "/private/var/db/"
    ]

    /// The app bundles an executable counts toward, outermost first, or nothing.
    ///
    /// Only an app's own executables count: the program in `Contents/MacOS`, or at the root
    /// of an iPhone or iPad app, of the innermost bundle. Helpers such as
    /// `Discord.app/Contents/Frameworks/Discord Helper.app/Contents/MacOS/Discord Helper`
    /// count toward Discord as well. Command-line tools that ship inside a bundle, such as
    /// compilers inside Xcode, do not, so blocking an app never breaks the shell.
    public static func owningBundles(forExecutable path: String) -> [String] {
        guard path.hasPrefix("/"), !path.contains("/../"), !path.contains("/./"), !path.contains("//"),
              !systemLocations.contains(where: { path.hasPrefix($0) }) else { return [] }
        let bundles = bundlePaths(forExecutable: path)
        guard let innermost = bundles.last else { return [] }
        let folder = String(path[..<(path.lastIndex(of: "/") ?? path.startIndex)])
        guard folder == innermost || folder == innermost + "/Contents/MacOS" else { return [] }
        return bundles
    }

    /// Whether a path is part of the operating system, where enforcement never acts.
    public static func isSystemLocation(_ path: String) -> Bool {
        let folder = path.hasSuffix("/") ? path : path + "/"
        return systemLocations.contains { folder.hasPrefix($0) }
    }

    static func bundlePaths(forExecutable path: String) -> [String] {
        var result: [String] = []
        var searchStart = path.startIndex
        while let range = path.range(of: ".app/", options: .caseInsensitive, range: searchStart..<path.endIndex) {
            result.append(String(path[..<path.index(before: range.upperBound)]))
            searchStart = range.upperBound
        }
        return result
    }
}

/// Decides which processes a block closes. The bundle reader is injected so the
/// rules can be checked without real processes.
public struct AppMatcher: Sendable {
    public let blocked: Set<String>
    public init(blocked: Set<String>) { self.blocked = Set(blocked.map { $0.lowercased() }.filter { !AppRule.isProtected($0) }) }

    /// The blocked app key that owns this executable, if any.
    public func match(executable path: String, bundleID: (String) -> String?) -> String? {
        guard !blocked.isEmpty else { return nil }
        for bundle in AppBundles.owningBundles(forExecutable: path) {
            if let key = bundleID(bundle)?.lowercased(), blocked.contains(key) { return key }
        }
        return nil
    }
}

/// An app that was open when its block started. It gets a moment to save before closing.
public struct ClosingApp: Codable, Equatable, Sendable {
    public let app: BlockedApp
    public let deadline: Date
    public init(app: BlockedApp, deadline: Date) { self.app = app; self.deadline = deadline }
}

/// A launch that a block stopped.
public struct BlockedLaunch: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let app: BlockedApp
    public let at: Date
    public let until: Date
    public init(app: BlockedApp, at: Date, until: Date) { id = UUID(); self.app = app; self.at = at; self.until = until }
}

public struct AppActivity: Codable, Equatable, Sendable {
    public var closing: [ClosingApp]
    public var recent: [BlockedLaunch]
    public var error: String?
    public init(closing: [ClosingApp] = [], recent: [BlockedLaunch] = [], error: String? = nil) {
        self.closing = closing; self.recent = recent; self.error = error
    }
}

public struct AppBlock: Sendable, Equatable {
    public let app: BlockedApp
    public let until: Date
    public init(app: BlockedApp, until: Date) { self.app = app; self.until = until }
}

extension Policy {
    /// Every app blocked at this moment, keyed by case-folded bundle identifier, with its latest end.
    public func blockedApps(at date: Date) -> [String: AppBlock] {
        var result: [String: AppBlock] = [:]
        for commitment in active(at: date) {
            for app in commitment.apps where !AppRule.isProtected(app.bundleID) {
                if let existing = result[app.key], existing.until >= commitment.endsAt { continue }
                result[app.key] = AppBlock(app: app, until: commitment.endsAt)
            }
        }
        return result
    }

    public func blocksApp(_ bundleID: String, at date: Date) -> Bool { blockedApps(at: date)[bundleID.lowercased()] != nil }
}

/// Reads small files from places other users control, without following a final symlink
/// or blocking on a pipe or device. The root service also answers DNS on its thread, so a
/// planted file must never stall it.
public enum SafeFile {
    public static func read(_ path: String, limit: Int) -> Data? {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else { return nil }
        let size = Int(info.st_size)
        var data = Data(count: size)
        var total = 0
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return size == 0 }
            while total < size {
                let count = Darwin.read(descriptor, base + total, size - total)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                total += count
            }
            return true
        }
        return complete ? data : nil
    }

    /// Where an app keeps its Info.plist: macOS apps, iPhone and iPad app wrappers, and their inner bundle.
    public static let infoPlistLocations = ["Contents/Info.plist", "WrappedBundle/Info.plist", "Info.plist"]

    public static func infoPlist(atPath path: String) -> [String: Any]? {
        guard let data = read(path, limit: 4_000_000) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
