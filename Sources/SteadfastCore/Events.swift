import Foundation
import notify

public enum ServiceEvents {
    public static let disconnected = Notification.Name("steadfast.service.disconnected")

    public static func updates(for service: String) throws -> AsyncStream<Void> { try stream(service + ".changed") }

    /// Blocked app launches and apps asked to close. Posted separately so the menu bar app can
    /// react without refreshing every view.
    public static func appActivity(for service: String) throws -> AsyncStream<Void> { try stream(service + ".apps") }

    public static func postAppActivity(for service: String) { notify_post(service + ".apps") }

    private static func stream(_ name: String) throws -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var token: Int32 = 0
        let result = notify_register_dispatch(name, &token, .main) { _ in continuation.yield(()) }
        guard result == NOTIFY_STATUS_OK else {
            continuation.finish()
            throw Failure("could not observe service changes")
        }
        let registration = token
        continuation.onTermination = { _ in notify_cancel(registration) }
        return stream
    }

    public static func postChange(for service: String) {
        notify_post(service + ".changed")
    }
}
