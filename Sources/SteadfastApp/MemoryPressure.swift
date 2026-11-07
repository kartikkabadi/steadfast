import SwiftUI
import Observation
import Dispatch
import Darwin

@Observable @MainActor final class MemoryPressure {
    enum Level { case normal, warning, critical }
    private(set) var level: Level
    var constrained: Bool { level != .normal }
    @ObservationIgnored private let source: any DispatchSourceMemoryPressure

    init() {
        var raw: Int32 = 1
        var size = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &raw, &size, nil, 0)
        level = Self.level(for: .init(rawValue: UInt(max(1, raw))))
        source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.receive(self.source.data)
            }
        }
        source.activate()
    }

    isolated deinit { source.cancel() }

    func receive(_ event: DispatchSource.MemoryPressureEvent) {
        guard !event.isEmpty else { return }
        let next = Self.level(for: event)
        guard level != next else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { level = next }
    }

    private static func level(for event: DispatchSource.MemoryPressureEvent) -> Level {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return .normal
    }
}

extension EnvironmentValues {
    @Entry var memoryConstrained = false
    var restrainedMotion: Bool { accessibilityReduceMotion || memoryConstrained }
    var restrainedTransparency: Bool { accessibilityReduceTransparency || memoryConstrained }
}
