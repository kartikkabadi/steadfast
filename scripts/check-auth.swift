import Foundation
import Synchronization
import XPC

final class ProbeHandler: XPCPeerHandler {
    let accepted = Mutex(false)
    func handleIncomingRequest(_ message: String) -> (any Encodable)? {
        accepted.withLock { $0 = true }
        return "pong"
    }
}
let denied = CommandLine.arguments.contains("--deny")
let hash = denied ? String(repeating: "0", count: 40) : CommandLine.arguments[1]
let requirement = try RuntimeAuthorization.requirement(from: "cdhash H\"\(hash)\"")
for invalid in ["", "identifier foo", "cdhash H\"abc\"", "cdhash H\"" + String(repeating: "a", count: 40) + "\" or true"] {
    do { _ = try RuntimeAuthorization.requirement(from: invalid); fatalError("invalid authorization accepted") }
    catch {}
}
let handler = ProbeHandler()
let listener = XPCListener { incoming in
    incoming.accept { session in
        session.setPeerRequirement(requirement)
        return handler
    }
}
let connection = try XPCSession(endpoint: listener.endpoint)
let finished = Mutex(false)
func finish(_ allowed: Bool) {
    let first = finished.withLock { value in let first = !value; value = true; return first }
    guard first else { return }
    let handlerCalled = handler.accepted.withLock { $0 }
    let passed = denied ? !allowed && !handlerCalled : allowed && handlerCalled
    print("\(passed ? "PASS" : "FAIL"): lightweight XPC \(denied ? "rejects a mismatched hash before the handler" : "accepts the exact signed executable")")
    exit(passed ? 0 : 1)
}
try connection.send("ping") { (result: Result<String, any Error>) in
    switch result { case .success(let value): finish(value == "pong"); case .failure: finish(false) }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
    fputs("FAIL: native XPC authentication timed out\n", stderr)
    exit(1)
}
RunLoop.main.run()
