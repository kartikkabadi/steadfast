import SwiftUI
import Dispatch

@main struct CheckMemory {
    @MainActor static func main() {
        let state = MemoryPressure()
        if CommandLine.arguments.contains("--expect-critical-start") {
            precondition(state.level == .critical, "a new observer must immediately detect existing critical pressure")
            print("pass: startup detects the current critical kernel pressure level")
        }
        state.receive(.normal)
        precondition(!state.constrained && state.level == .normal)
        state.receive(.warning)
        precondition(state.constrained && state.level == .warning)
        state.receive(.critical)
        precondition(state.constrained && state.level == .critical)
        state.receive([])
        precondition(state.level == .critical, "empty events cannot clear critical pressure")
        state.receive([.normal, .critical])
        precondition(state.level == .critical, "coalesced pressure must retain the more severe level")
        state.receive(.normal)
        precondition(!state.constrained && state.level == .normal, "relief must restore normal rendering")
        var environment = EnvironmentValues()
        precondition(!environment.memoryConstrained)
        environment.memoryConstrained = true
        precondition(environment.restrainedMotion && environment.restrainedTransparency)
        environment.memoryConstrained = false
        precondition(environment.restrainedMotion == environment.accessibilityReduceMotion)
        precondition(environment.restrainedTransparency == environment.accessibilityReduceTransparency)
        weak var released: MemoryPressure?
        autoreleasepool { let temporary = MemoryPressure(); released = temporary }
        precondition(released == nil, "the source callback must not retain the observer")
        print("pass: normal/warning/critical/coalesced/empty/recovery transitions, environment fallback and observer lifetime")
    }
}
