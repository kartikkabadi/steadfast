import Foundation
import SteadfastCore

@main struct ProbeLatency {
    static func main() async throws {
        let name = CommandLine.arguments[1]
        func milliseconds(_ start: ContinuousClock.Instant) -> Double {
            let delta = start.duration(to: .now).components
            return Double(delta.seconds) * 1000 + Double(delta.attoseconds) / 1e15
        }
        let first = ContinuousClock.now
        let initial = try await Client.send(Request(action: "status"), service: name)
        precondition(initial.enforcementError == nil)
        let cold = milliseconds(first)
        let commitStart = ContinuousClock.now
        let saved = try await Client.send(Request(action: "commit", domains: (0..<500).map { "site\($0).example" }, minutes: 10), service: name)
        precondition(saved.enforcementError == nil && saved.policy.active(at: saved.now).count == 1)
        let commit = milliseconds(commitStart)
        var times: [Double] = []
        for _ in 0..<50 {
            let start = ContinuousClock.now
            let snapshot = try await Client.send(Request(action: "status"), service: name)
            precondition(snapshot.enforcementError == nil && snapshot.policy.commitments[0].domains.count == 500)
            times.append(milliseconds(start))
        }
        let report: [String: Any] = ["first_status_ms": cold, "commit_500_ms": commit, "warm_status_500_ms": times]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
        print("")
    }
}
