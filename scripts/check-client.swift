import Foundation
import Synchronization
import XPC

final class TestServer: Sendable {
    let accepted = Mutex(0)
}
// The handoff API transfers this immutable message to the supplied queue.
final class DeferredReply: @unchecked Sendable {
    let message: XPCReceivedMessage
    init(_ message: XPCReceivedMessage) { self.message = message }
}
final class Endpoint: XPCPeerHandler, @unchecked Sendable {
    let server: TestServer
    weak var connection: XPCSession?
    init(server: TestServer, connection: XPCSession) { self.server = server; self.connection = connection }
    func handleIncomingRequest(_ message: XPCReceivedMessage) -> (any Encodable)? {
        let data = try! message.decode(as: Data.self)
        let request = try! JSONDecoder().decode(Request.self, from: data)
        if request.action == "drop" {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.connection?.cancel(reason: "expected disconnect") }
            return nil
        }
        if request.action == "reject" { return ServiceReply(error: "expected business rejection") }
        var policy = Policy()
        policy.lastObserved = Date(timeIntervalSince1970: Double(server.accepted.withLock { $0 }))
        let response = ServiceReply(data: try! JSONEncoder().encode(Snapshot(policy: policy, now: Date(), sandbox: true, enforcementError: nil)))
        if request.action == "slow" {
            let deferred = DeferredReply(message)
            return message.handoffReply(to: .global()) {
                Thread.sleep(forTimeInterval: 6)
                deferred.message.reply(response)
            }
        }
        return response
    }
}

@main struct CheckClient {
    static func main() {
        let service = CommandLine.arguments[2]
        if CommandLine.arguments[1] == "--server" {
            let server = TestServer()
            let listener = try! XPCListener(service: service) { incoming in
                server.accepted.withLock { $0 += 1 }
                return incoming.accept { session in Endpoint(server: server, connection: session) }
            }
            withExtendedLifetime((server, listener)) { RunLoop.main.run() }
        } else {
            Task {
                do { try await check(service); exit(0) }
                catch { print("FAIL: \(error)"); exit(1) }
            }
            RunLoop.main.run()
        }
    }
    static func check(_ service: String) async throws {
        func status() async throws -> Int {
            Int(try await Client.send(Request(action: "status"), service: service).policy.lastObserved.timeIntervalSince1970)
        }
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(message) }
            print("PASS: \(message)")
        }
        try expect(try await status() == 1, "first request creates one session")
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<12 { group.addTask { try await status() } }
            var counts: [Int] = []
            for try await count in group { counts.append(count) }
            return counts
        }
        try expect(counts.count == 12 && counts.allSatisfy { $0 == 1 }, "concurrent requests reuse the authenticated connection")
        do { _ = try await Client.send(Request(action: "reject"), service: service); throw Failure("business rejection was lost") }
        catch let error as Failure where error.message == "expected business rejection" {}
        try expect(try await status() == 1, "business rejection keeps the session usable")
        let disconnected = await withTaskGroup(of: Bool.self) { group in
            for action in ["slow", "slow", "slow", "slow", "drop"] {
                group.addTask {
                    do { _ = try await Client.send(Request(action: action), service: service); return false }
                    catch { return true }
                }
            }
            var failures = 0
            for await failed in group where failed { failures += 1 }
            return failures
        }
        try expect(disconnected == 5, "disconnect completes every concurrent pending request")
        try expect(try await status() == 2, "next send reconnects after interruption")
        let start = ContinuousClock.now
        do { _ = try await Client.send(Request(action: "slow"), service: service); throw Failure("timeout was ignored") }
        catch let error as Failure where error.message == "the background service did not respond" {}
        let elapsed = start.duration(to: .now)
        try expect(elapsed >= .seconds(5) && elapsed < .seconds(10), "authenticated requests retain the five-second timeout")
        try expect(try await status() == 3, "timeout discards the old connection without retrying the request")
        try await Task.sleep(for: .seconds(2))
        try expect(try await status() == 3, "late reply cannot close the replacement connection")
    }
}
