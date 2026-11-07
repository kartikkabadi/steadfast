import Foundation

public struct Enforcement {
    public static let marker = "# managed by steadfast dns"
    public let resolverDirectory: URL
    public let hostsURL: URL
    public let port: UInt16
    public init(resolverDirectory: URL, hostsURL: URL, port: UInt16) { self.resolverDirectory = resolverDirectory; self.hostsURL = hostsURL; self.port = port }
    public func validate(domains: [String]) throws {
        for domain in domains {
            let path = resolverDirectory.appendingPathComponent(domain)
            if (try? FileManager.default.attributesOfItem(atPath: path.path)) != nil {
                guard try isManagedResolver(path) else {
                    throw Failure("an existing dns configuration owns \(domain); it was left unchanged")
                }
            }
        }
        _ = try hostsContent(domains: domains)
    }
    public func apply(domains: [String]) throws -> Bool {
        try validate(domains: domains)
        let manager = FileManager.default
        try manager.createDirectory(at: resolverDirectory, withIntermediateDirectories: true)
        var changed = false
        for domain in domains {
            let path = resolverDirectory.appendingPathComponent(domain)
            let desired = "\(Self.marker)\nnameserver 127.0.0.1\nport \(port)\ntimeout 1\n"
            changed = try writeIfDifferent(desired, to: path) || changed
        }
        let active = Set(domains)
        for path in try manager.contentsOfDirectory(at: resolverDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        where !active.contains(path.lastPathComponent) {
            if try isManagedResolver(path) { try manager.removeItem(at: path); changed = true }
        }
        changed = try writeIfDifferent(hostsContent(domains: domains), to: hostsURL) || changed
        return changed
    }
    private func isManagedResolver(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false else { return false }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let marker = Data((Self.marker + "\n").utf8)
        return try file.read(upToCount: marker.count) == marker
    }

    private func writeIfDifferent(_ content: String, to url: URL) throws -> Bool {
        if FileManager.default.fileExists(atPath: url.path), try String(contentsOf: url, encoding: .utf8) == content { return false }
        // In production these paths live in root-owned directories; callers cannot substitute links.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if attributes?[.type] as? FileAttributeType == .typeSymbolicLink { throw Failure("refusing a symbolic link at \(url.path)") }
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        return true
    }
    public func hostsContent(domains: [String]) throws -> String {
        let original = try String(contentsOf: hostsURL, encoding: .utf8)
        let begin = "# BEGIN STEADFAST DNS\n", end = "# END STEADFAST DNS\n"
        var clean = original
        if let start = clean.range(of: begin) {
            guard let finish = clean.range(of: end, range: start.upperBound..<clean.endIndex) else { throw Failure("the steadfast hosts section is incomplete; repair it before continuing") }
            clean.removeSubrange(start.lowerBound..<finish.upperBound)
        } else if clean.contains(end) { throw Failure("the steadfast hosts section is incomplete") }
        guard !clean.contains(begin), !clean.contains(end) else { throw Failure("duplicate steadfast hosts sections") }
        guard !domains.isEmpty else { return clean }
        if !clean.hasSuffix("\n") { clean += "\n" }
        let names = Set(domains.flatMap { [$0, "www." + $0] }).sorted()
        return clean + begin + names.map { "0.0.0.0 \($0)\n:: \($0)\n" }.joined() + end
    }
}
