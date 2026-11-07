import Foundation
import Synchronization
import XPC

private final class Pending: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Data, any Error>?
        var timeout: Task<Void, Never>?
    }
    private let state: Mutex<State>
    init(_ continuation: CheckedContinuation<Data, any Error>) { state = Mutex(State(continuation: continuation)) }
    func expire(after seconds: Double, action: @escaping @Sendable () -> Void) {
        let task = Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            action()
        }
        state.withLock { saved in
            if saved.continuation == nil { task.cancel() }
            else { saved.timeout = task }
        }
    }
    func finish(_ result: Result<Data, any Error>) {
        let (continuation, timeout) = state.withLock { saved in
            let values = (saved.continuation, saved.timeout)
            saved.continuation = nil; saved.timeout = nil
            return values
        }
        timeout?.cancel()
        continuation?.resume(with: result)
    }
}
private final class Session: @unchecked Sendable {
    private struct State {
        var available = true
        var authenticated = false
        var pending: [UUID: Pending] = [:]
    }
    private let state = Mutex(State())
    private let connection: XPCSession
    private let service: String
    var available: Bool { state.withLock { $0.available } }

    init(service: String) throws {
        self.service = service
        connection = try XPCSession(machService: service, options: service == ServiceName.production ? [.inactive, .privileged] : .inactive)
        connection.setCancellationHandler { [weak self] _ in self?.close(Failure("the background service disconnected")) }
        try connection.activate()
    }
    deinit { connection.cancel(reason: "client closed") }

    private func close(_ error: any Error, ifPending id: UUID? = nil) {
        let pending = state.withLock { saved -> [Pending]? in
            guard saved.available else { return nil }
            if let id, saved.pending[id] == nil { return nil }
            saved.available = false
            let pending = Array(saved.pending.values)
            saved.pending.removeAll()
            return pending
        }
        guard let pending else { return }
        connection.cancel(reason: "connection closed")
        for request in pending { request.finish(.failure(error)) }
        NotificationCenter.default.post(name: ServiceEvents.disconnected, object: service)
    }

    private func complete(_ id: UUID, result: Result<Data, any Error>, authenticated: Bool = false) {
        let pending = state.withLock { saved in
            if authenticated { saved.authenticated = true }
            return saved.pending.removeValue(forKey: id)
        }
        pending?.finish(result)
    }

    private func expire(_ id: UUID) {
        close(Failure("the background service did not respond"), ifPending: id)
    }

    func send(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let pending = Pending(continuation)
            let id = UUID()
            let timeout = state.withLock { saved -> Double? in
                guard saved.available else { return nil }
                saved.pending[id] = pending
                // Allow a cold service launch; later messages reuse the authenticated session.
                return saved.authenticated ? 5 : 60
            }
            guard let timeout else { pending.finish(.failure(Failure("the background service is not available"))); return }
            pending.expire(after: timeout) { [weak self] in self?.expire(id) }
            do {
                try connection.send(data) { [weak self] (result: Result<ServiceReply, any Error>) in
                    switch result {
                    case .failure(let error): self?.close(error)
                    case .success(let reply):
                        if let error = reply.error { self?.complete(id, result: .failure(Failure(error)), authenticated: true) }
                        else if let response = reply.data { self?.complete(id, result: .success(response), authenticated: true) }
                        else { self?.complete(id, result: .failure(Failure("empty service response")), authenticated: true) }
                    }
                }
            } catch { close(error) }
        }
    }
}

public enum Client {
    private static let sessions = Mutex<[String: Session]>([:])
    @concurrent public static func send(_ request: Request, service: String = ServiceName.production) async throws -> Snapshot {
        let session = try sessions.withLock { saved in
            if let existing = saved[service], existing.available { return existing }
            let session = try Session(service: service)
            saved[service] = session
            return session
        }
        let data = try JSONEncoder().encode(request)
        let response = try await session.send(data)
        return try JSONDecoder().decode(Snapshot.self, from: response)
    }
}
