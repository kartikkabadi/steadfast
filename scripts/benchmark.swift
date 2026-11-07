import Foundation

@main struct Benchmark {
    static func main() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var policy = Policy()
        try policy.commit((0..<500).map { "site\($0).example" }, minutes: 60, at: now)
        let index = DomainIndex(policy: policy)
        let names = ["www.site499.example", "unblocked.example", "site0.example", "deep.sub.site250.example"]
        func measure(_ blocks: (String) -> Bool) -> [Double] {
            var samples: [Double] = []
            for _ in 0..<5 {
                var hits = 0
                let start = ContinuousClock.now
                for i in 0..<10_000 { if blocks(names[i % names.count]) { hits += 1 } }
                let duration = start.duration(to: .now).components
                precondition(hits == 7_500)
                samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            }
            return samples
        }
        let reference = measure { policy.blocks($0, at: now) }
        let indexed = measure { index.blocks($0, at: now) }
        let report: [String: Any] = ["rules": 500, "lookups_per_sample": 10_000, "reference_ms": reference, "indexed_ms": indexed,
                                   "scope": "optimized local rule lookup; excludes DNS transport, signing and UI"]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        print("")
    }
}
