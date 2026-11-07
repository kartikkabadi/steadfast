import Foundation
import Testing
@testable import SteadfastCore

@Test func domainNormalization() throws {
    #expect(try Domain.parse(" HTTPS://WWW.X.com/home ") == "x.com")
    #expect(try Domain.parse("bücher.de") == "xn--bcher-kva.de")
    #expect(try Domain.normalized(["x.com", "www.x.com", "api.x.com", "twitter.com"]) == ["twitter.com", "x.com"])
    #expect(!Domain.matches("notx.com", rule: "x.com"))
    #expect(!Domain.matches("x.com.evil.com", rule: "x.com"))
    #expect(Domain.matches("api.x.com", rule: "x.com"))
}
@Test func largeNormalizationKeepsParentsAndDistinctDomainBoundaries() throws {
    let roots = (0..<100).map { "site\($0).example" }
    let neighbors = roots.map { "not" + $0 }
    let input = roots.flatMap { ["https://www." + $0.uppercased() + "/path", "deep.sub." + $0, $0 + "."] } + neighbors
    #expect(try Domain.normalized(Array(input.reversed())) == (roots + neighbors).sorted())
    #expect(try Domain.normalized(["bücher.de", "sub.xn--bcher-kva.de", "otherbücher.de"]) == (try [Domain.parse("bücher.de"), Domain.parse("otherbücher.de")]).sorted())
}
@Test func overlapAndCapacityChecksKeepCommitmentsImmutable() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for (existing, incoming) in [("x.com", "sub.x.com"), ("deep.x.com", "x.com"), ("x.com", "x.com")] {
        var policy = Policy()
        try policy.commit([existing], minutes: 1, at: now)
        let original = policy.commitments
        #expect(throws: (any Error).self) { try policy.commit([incoming], minutes: 2, at: now) }
        #expect(policy.commitments == original)
        try policy.commit(["notx.com"], minutes: 1, at: now)
    }
    var policy = Policy()
    try policy.commit((0..<250).map { "old\($0).example" }, minutes: 1, at: now)
    try policy.commit((0..<250).map { "new\($0).example" }, minutes: 1, at: now)
    let full = policy.commitments
    #expect(throws: (any Error).self) { try policy.commit(["extra.example"], minutes: 1, at: now) }
    #expect(policy.commitments == full)
    try policy.commit(["extra.example"], minutes: 1, at: now.addingTimeInterval(60))
    #expect(policy.active(at: now.addingTimeInterval(60)).count == 1)
}
@Test(arguments: ["", "localhost", "127.0.0.1", "foo..com", "-x.com", "javascript:alert(1)", "https://u:p@x.com"])
func rejectsInvalidDomains(_ input: String) { #expect(throws: (any Error).self) { try Domain.parse(input) } }
@Test func commitmentIsAppendOnlyAndExpires() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = Policy()
    try policy.commit(["x.com", "twitter.com"], minutes: 60, at: now)
    let original = policy
    #expect(policy.blocks("api.x.com", at: now))
    #expect(!policy.blocks("example.com", at: now))
    #expect(throws: (any Error).self) { try policy.commit(["x.com"], minutes: 1, at: now) }
    #expect(policy.commitments == original.commitments)
    #expect(throws: (any Error).self) { try policy.commit(["api.x.com"], minutes: 120, at: now) }
    try policy.commit(["reddit.com"], minutes: 1, at: now)
    #expect(policy.active(at: now.addingTimeInterval(60)).count == 1)
    #expect(!policy.blocks("x.com", at: now.addingTimeInterval(3600)))
    let decoded = try JSONDecoder().decode(Policy.self, from: JSONEncoder().encode(policy))
    #expect(decoded.commitments == policy.commitments)
}
@Test func indexedBlockingMatchesPolicyAcrossDeadlinesAndSubdomainBoundaries() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = Policy()
    try policy.commit(["x.com", "short.example"], minutes: 1, at: now)
    try policy.commit((0..<498).map { "site\($0).example" }, minutes: 60, at: now)
    let index = DomainIndex(policy: policy)
    let names = ["x.com", "www.x.com", "api.deep.x.com", "notx.com", "x.com.evil.com", "short.example", "unrelated.example"]
        + (0..<498).flatMap { ["site\($0).example", "sub.site\($0).example", "notsite\($0).example"] }
    for date in [now, now.addingTimeInterval(60), now.addingTimeInterval(3599), now.addingTimeInterval(3600)] {
        for name in names { #expect(index.blocks(name, at: date) == policy.blocks(name, at: date)) }
    }
    try policy.commit(["new.example"], minutes: 2, at: now.addingTimeInterval(60))
    let updated = DomainIndex(policy: policy)
    #expect(updated.blocks("sub.new.example", at: now.addingTimeInterval(61)))
    #expect(!updated.blocks("x.com", at: now.addingTimeInterval(61)))
}
@Test func maintenanceSleepsWhenIdleAndKeepsDeadlineAndRecoveryChecks() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var policy = Policy()
    #expect(policy.maintenanceDelay(at: now) == nil)
    #expect(policy.maintenanceDelay(at: now, retrying: true) == 60)
    try policy.commit(["x.com"], minutes: 2, at: now)
    #expect(policy.maintenanceDelay(at: now) == 60)
    #expect(policy.maintenanceDelay(at: now.addingTimeInterval(119)) == 1)
    #expect(policy.maintenanceDelay(at: now.addingTimeInterval(120)) == nil)
    #expect(policy.maintenanceDelay(at: now.addingTimeInterval(120), retrying: true) == 60)
}
@Test(arguments: [0.0, -1, .infinity, .nan, 525_601]) func rejectsInvalidDuration(_ duration: Double) {
    var policy = Policy()
    #expect(throws: (any Error).self) { try policy.commit(["x.com"], minutes: duration, at: Date()) }
    #expect(policy.commitments.isEmpty)
}
func query(_ name: String, type: UInt8 = 1) -> Data {
    var bytes: [UInt8] = [0xab,0xcd,1,0,0,1,0,0,0,0,0,0]
    for label in name.split(separator: ".") { bytes.append(UInt8(label.utf8.count)); bytes.append(contentsOf: label.utf8) }
    bytes += [0,0,type,0,1]
    return Data(bytes)
}
@Test func dnsRejectsBlockedIPv4IPv6AndHTTPSRecords() throws {
    for type: UInt8 in [1,28,65] {
        let answer = try #require(DNS.reply(to: query("api.x.com", type: type)) { Domain.matches($0, rule: "x.com") })
        #expect(answer[0] == 0xab && answer[1] == 0xcd)
        #expect(answer[3] & 15 == 3)
        #expect(answer.count == query("api.x.com").count)
    }
    let unrelated = try #require(DNS.reply(to: query("example.com")) { _ in false })
    #expect(unrelated[3] & 15 == 2)
    #expect(DNS.reply(to: Data([0,1,2])) { _ in true } == nil)
    var bad = query("x.com"); bad[12] = 0xc0
    #expect(DNS.reply(to: bad) { _ in true } == nil)
    for count in 0..<512 { _ = DNS.reply(to: Data((0..<count).map { _ in UInt8.random(in: 0...255) })) { _ in true } }
}
@Test func enforcementPreservesUnrelatedConfigurationAndCleansOnlyOwnedRules() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let hosts = directory.appendingPathComponent("hosts")
    let original = "127.0.0.1 localhost\n10.0.0.1 internal.test\n"
    try original.write(to: hosts, atomically: true, encoding: .utf8)
    let resolver = directory.appendingPathComponent("resolver")
    let engine = Enforcement(resolverDirectory: resolver, hostsURL: hosts, port: 53535)
    #expect(try engine.apply(domains: ["x.com"]))
    #expect(try String(contentsOf: hosts, encoding: .utf8).hasPrefix(original))
    #expect(try String(contentsOf: hosts, encoding: .utf8).contains(":: x.com"))
    #expect(try !engine.apply(domains: ["x.com"]))
    let other = resolver.appendingPathComponent("example.com")
    try "nameserver 10.0.0.1\n".write(to: other, atomically: true, encoding: .utf8)
    #expect(throws: (any Error).self) { try engine.validate(domains: ["example.com"]) }
    #expect(try engine.apply(domains: []))
    #expect(try String(contentsOf: hosts, encoding: .utf8) == original)
    #expect(FileManager.default.fileExists(atPath: other.path))
    #expect(!FileManager.default.fileExists(atPath: resolver.appendingPathComponent("x.com").path))
}
@Test func rejectsBrokenManagedHostsSection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let hosts = directory.appendingPathComponent("hosts")
    try "127.0.0.1 localhost\n# BEGIN STEADFAST DNS\n".write(to: hosts, atomically: true, encoding: .utf8)
    let engine = Enforcement(resolverDirectory: directory, hostsURL: hosts, port: 53535)
    #expect(throws: (any Error).self) { try engine.hostsContent(domains: ["x.com"]) }
}
