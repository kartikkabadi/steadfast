import Foundation
import SteadfastCore

@main struct BenchmarkSpeed {
    @MainActor static func main() throws {
        var results: [String: Any] = [:]
        func measure(_ action: () throws -> Void) rethrows -> [Double] {
            try action()
            return try (0..<11).map { _ in
                let start = ContinuousClock.now
                try action()
                let elapsed = start.duration(to: .now).components
                return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
            }
        }
        for count in [20, 100, 500] {
            let domains = (0..<count).map { "site\($0).example" }
            results["normalize_\(count)_ms"] = try measure { let normalized = try Domain.normalized(domains); precondition(normalized.count == count) }
            let model = Model()
            results["model_validate_\(count)_ms"] = measure {
                model.chosen = Set(domains)
                precondition(model.validateSites())
            }
        }
        let now = Date()
        var original = Policy()
        try original.commit((0..<250).map { "old\($0).example" }, minutes: 60, at: now)
        let additional = (0..<250).map { "new\($0).example" }
        results["append_250_to_250_ms"] = try measure {
            var policy = original
            try policy.commit(additional, minutes: 60, at: now)
            precondition(policy.active(at: now).count == 2)
        }
        var policy = Policy()
        try policy.commit((0..<500).map { "site\($0).example" }, minutes: 60, at: now)
        let index = DomainIndex(policy: policy)
        let packet = Data([0xab,0xcd,1,0,0,1,0,0,0,0,0,0,3] + Array("API".utf8) + [7] + Array("site499".utf8) + [7] + Array("example".utf8) + [0,0,1,0,1])
        results["dns_10000_ms"] = measure {
            var count = 0
            for _ in 0..<10_000 {
                if let reply = DNS.reply(to: packet, blocks: { index.blocks($0, at: now) }), reply[3] == 3 { count += 1 }
            }
            precondition(count == 10_000)
        }
        results["scope"] = "11 samples after warmup; actual optimized core and app Model; model timing excludes SwiftUI rendering"
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        print("")
    }
}
