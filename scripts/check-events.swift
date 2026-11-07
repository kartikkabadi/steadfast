import Foundation
import SteadfastCore

@main struct ObserveEvents {
    static func main() async throws {
        let service = CommandLine.arguments[1]
        let updates = try ServiceEvents.updates(for: service)
        print("observing")
        fflush(stdout)
        for await _ in updates {
            do {
                let snapshot = try await Client.send(Request(action: "status"), service: service)
                print("active:\(snapshot.policy.active(at: snapshot.now).count)")
                fflush(stdout)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
            }
        }
    }
}
