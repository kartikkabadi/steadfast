import SwiftUI

private struct OnboardingHost: ViewModifier {
    let model: Model
    func body(content: Content) -> some View {
        Group {
            if model.panel == .onboarding {
                OnboardingView(model: model).transition(.opacity)
            } else {
                content.transition(.opacity)
            }
        }
        .animation(Motion.still ? nil : .easeOut(duration: 0.2), value: model.panel == .onboarding)
    }
}

extension View {
    func onboardingStage(_ model: Model) -> some View { modifier(OnboardingHost(model: model)) }
}

extension RootView {
    var sheetPanel: Binding<Panel?> {
        Binding(get: { model.panel == .onboarding ? nil : model.panel },
                set: { if $0 == nil, model.panel != .onboarding { model.dismissPanel() } })
    }
}
