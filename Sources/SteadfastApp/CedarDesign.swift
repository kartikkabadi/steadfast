// Cedar template components, reused with the owner's authorization.
// Source: Cedar Sources/Search/Design.swift.
// Browser theme plumbing omitted; Swift 6 isolation and Clarity storage adapted.
import SwiftUI
import AppKit
import Synchronization

nonisolated enum Palette {
    static let ground = Tone(NS.ground), ink = Tone(NS.ink), muted = Tone(NS.muted)
    static let faint = Tone(NS.faint), hairline = Tone(NS.hairline), wash = Tone(NS.wash)
    static let hover = Tone(NS.hover), danger = Tone(NS.danger), accent = Tone(NS.accent)
    static let accentFill = Tone(NS.accentFill), card = Tone(NS.card)
    nonisolated enum NS {
        static let ground = pair(1, 0x1C / 255.0)
        static let ink = pair(0x17 / 255.0, 0xED / 255.0)
        static let muted = pair(0x62 / 255.0, 0xDC / 255.0, contrast: (0.37, 0.90))
        static let faint = pair(0.62, 0.38, contrast: (0.45, 0.62))
        static let hairline = pair(0.91, 0.20, contrast: (0.55, 0.50))
        static let wash = pair(0xEF / 255.0, 0x2D / 255.0, veil: (0.065, 0.11))
        static let hover = pair(0xF6 / 255.0, 0x26 / 255.0, veil: (0.04, 0.065))
        static let danger = tint(light: (0.86, 0.15, 0.15), dark: (0.97, 0.44, 0.44))
        static let accent = tint(light: (43 / 255.0, 101 / 255.0, 201 / 255.0), dark: (141 / 255.0, 175 / 255.0, 255 / 255.0))
        static let accentFill = tint(light: (43 / 255.0, 101 / 255.0, 201 / 255.0), dark: (43 / 255.0, 101 / 255.0, 201 / 255.0))
        static let card = NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if Contrast.on { return NSColor(white: dark ? 0.18 : 0.94, alpha: 1) }
            return NSColor(white: 1, alpha: dark ? 0.055 : 0.50)
        }
        static let panel = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.09, green: 0.094, blue: 0.10, alpha: Clarity.panel(dark: true))
                : NSColor(white: 1, alpha: Clarity.panel(dark: false))
        }
        static func tint(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            NSColor(name: nil) { appearance in
                let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }
        private static func pair(_ light: CGFloat, _ dark: CGFloat, contrast: (CGFloat, CGFloat)? = nil, veil: (CGFloat, CGFloat)? = nil) -> NSColor {
            NSColor(name: nil) { appearance in
                let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                if Contrast.on { return NSColor(white: dim ? contrast?.1 ?? dark : contrast?.0 ?? light, alpha: 1) }
                if let veil { return NSColor(white: dim ? 1 : 0, alpha: dim ? veil.1 : veil.0) }
                return NSColor(white: dim ? dark : light, alpha: 1)
            }
        }
    }
}
nonisolated enum Contrast {
    static var on: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
}
nonisolated struct Tone: ShapeStyle, Hashable {
    let ns: NSColor
    var strength: Double = 1

    init(_ ns: NSColor) { self.ns = ns }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let key = Resolution(color: ObjectIdentifier(ns),
                             dark: environment.colorScheme == .dark,
                             contrast: environment.colorSchemeContrast == .increased,
                             generation: 0)
        var resolved = Self.resolutions.withLock { $0[key] } ?? {
            let fresh = Color(nsColor: ns).resolve(in: environment)
            Self.resolutions.withLock { $0[key] = fresh }
            return fresh
        }()
        if strength != 1 { resolved.opacity *= Swift.Float(strength) }
        return resolved
    }

    private struct Resolution: Hashable {
        let color: ObjectIdentifier
        let dark: Bool
        let contrast: Bool
        let generation: Int
    }

    private static let resolutions = Mutex<[Resolution: Color.Resolved]>([:])

    func opacity(_ strength: Double) -> Tone {
        var tone = self
        tone.strength *= strength
        return tone
    }

    var color: Color { Color(nsColor: ns).opacity(strength) }

    static let clear = Tone(.clear)
    static let white = Tone(.white)
}

extension Tone: View {
    var body: some View { Rectangle().fill(self) }
}

@MainActor
final class Clarity: ObservableObject {
    static let shared = Clarity()

    @Published var frost: Double = 0.9 {
        didSet { Self.current = Self.clamp(frost) }
    }

    private nonisolated static let stored = Mutex<Double>(0.9)
    nonisolated static var current: Double {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }

    nonisolated static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    nonisolated static func veil(dark: Bool, frost: Double = current) -> CGFloat {
        dark ? mix(0.32, 0.92, frost) : mix(0.48, 1.0, frost)
    }

    nonisolated static func panel(dark: Bool, frost: Double = current) -> CGFloat {
        dark ? mix(0.44, 0.88, frost) : mix(0.56, 1.0, frost)
    }

    private nonisolated static func mix(_ clear: CGFloat, _ frosted: CGFloat, _ frost: Double) -> CGFloat {
        clear + (frosted - clear) * CGFloat(clamp(frost))
    }
}

enum TypeScale {
    static let caption = Font.system(size: Size.caption)
    static let chrome = Font.system(size: Size.chrome)
    static let body = Font.system(size: Size.body)
    static let title = Font.system(size: Size.title, weight: .semibold)
    static let display = Font.system(size: Size.display)
    static let hero = Font.system(size: Size.hero, weight: .medium)

    enum Size {
        static let caption: CGFloat = 11
        static let chrome: CGFloat = 12
        static let body: CGFloat = 13
        static let title: CGFloat = 15
        static let display: CGFloat = 26
        static let hero: CGFloat = 34
    }

    enum NS {
        static let chrome = NSFont.systemFont(ofSize: Size.chrome)
        static let chromeMedium = NSFont.systemFont(ofSize: Size.chrome, weight: .medium)
        static let body = NSFont.systemFont(ofSize: Size.body)
        static let bodyMedium = NSFont.systemFont(ofSize: Size.body, weight: .medium)
    }
}

enum Symbols {
    static let small = Font.system(size: 9, weight: .medium)
    static let row = Font.system(size: 11, weight: .medium)
    static let door = Font.system(size: 13)
    static let header = Font.system(size: 15)
}

/// The one horizontal inset for anything inside a card or tile — rows, tiles,
/// group labels and notes — so every left edge in a column lines up.
enum Inset {
    static let row: CGFloat = 14
    /// Height of a plain list row inside a card.
    static let rowHeight: CGFloat = 36
}

/// Every sheet is one width, so moving between them never changes the frame.
enum Sheet {
    static let width: CGFloat = 520
}

enum Radius {
    static let control: CGFloat = 6
    static let row: CGFloat = 8
    static let card: CGFloat = 12
    static let panel: CGFloat = 24
}

enum Depth {
    case raised
    case floating
    case overlay

    var opacity: Double {
        switch self {
        case .raised: return 0.08
        case .floating: return 0.12
        case .overlay: return 0.18
        }
    }
    var radius: CGFloat {
        switch self {
        case .raised: return 8
        case .floating: return 18
        case .overlay: return 32
        }
    }
    var y: CGFloat {
        switch self {
        case .raised: return 2
        case .floating: return 6
        case .overlay: return 12
        }
    }
    var color: Color { .black.opacity(opacity) }

    var hairline: Bool { self != .raised }
}

private struct DepthStyle: ViewModifier {
    let depth: Depth?
    var corner: CGFloat?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.restrainedTransparency) private var opaque

    func body(content: Content) -> some View {
        content
            .shadow(
                color: opaque ? .clear : depth?.color ?? .clear,
                radius: opaque ? 0 : depth?.radius ?? 0,
                y: opaque ? 0 : depth?.y ?? 0
            )
            .overlay {
                if let depth, let corner, depth.hairline, scheme == .dark {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func depth(_ depth: Depth?) -> some View {
        modifier(DepthStyle(depth: depth, corner: nil))
    }

    func depth(_ depth: Depth, cornerRadius: CGFloat) -> some View {
        modifier(DepthStyle(depth: depth, corner: cornerRadius))
    }
}


struct Glass: View {
    var cornerRadius: CGFloat = 0
    var veiled = true

    @ObservedObject private var clarity = Clarity.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.restrainedTransparency) private var opaque

    var body: some View {
        if opaque { Palette.ground } else { ZStack {
            Backing(cornerRadius: cornerRadius)
            if veiled {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(veil)
                    .allowsHitTesting(false)
            }
        } }
    }

    private var veil: Color {
        let dark = scheme == .dark
        let alpha = Double(Clarity.veil(dark: dark, frost: clarity.frost))
        return dark
            ? Color(.sRGB, red: 0.075, green: 0.078, blue: 0.086, opacity: alpha)
            : Color(.sRGB, red: 0.975, green: 0.975, blue: 0.98, opacity: alpha)
    }

    private struct Backing: NSViewRepresentable {
        let cornerRadius: CGFloat

        private final class Inert: NSGlassEffectView {
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }

        func makeNSView(context: Context) -> NSGlassEffectView {
            let view = Inert()
            view.style = .regular
            view.cornerRadius = cornerRadius
            return view
        }

        func updateNSView(_ view: NSGlassEffectView, context: Context) {
            if view.cornerRadius != cornerRadius { view.cornerRadius = cornerRadius }
        }
    }
}


struct Dim: View {
    let strength: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.black.opacity(scheme == .dark ? strength * 1.6 + 0.08 : strength * 0.8)
    }
}

private struct Surface<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.restrainedTransparency) private var opaque
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var clarity = Clarity.shared

    private var tint: Color {
        let dark = scheme == .dark
        let alpha = Double(Clarity.panel(dark: dark, frost: clarity.frost))
        return dark
            ? Color(.sRGB, red: 0.09, green: 0.094, blue: 0.10, opacity: alpha)
            : Color(.sRGB, white: 1, opacity: alpha)
    }

    func body(content: Content) -> some View {
        content
            .background(shape.fill(opaque ? Palette.ground.color : tint))
            .glassEffect(opaque ? .identity : .regular, in: shape)
            .overlay {
                if opaque { shape.strokeBorder(Palette.hairline, lineWidth: 1).allowsHitTesting(false) }
            }
    }
}

extension View {
    func surface(_ material: Material = .regularMaterial, in shape: some InsettableShape) -> some View {
        modifier(Surface(shape: shape))
    }
}

enum Motion {
    enum Kind {
        case snap
        case quick
        case slide
        case glide
        case settle
    }

    static let snapTime: TimeInterval = 0.10
    static let quickTime: TimeInterval = 0.14
    static let slideTime: TimeInterval = 0.22
    static let glideResponse: Double = 0.34
    static let glideDamping: Double = 0.82
    static let settleResponse: Double = 0.30
    static let settleDamping: Double = 0.86
    static let handoff: TimeInterval = 0.42

    static let snap = Animation.easeOut(duration: snapTime)
    static let quick = Animation.easeOut(duration: quickTime)
    static let slide = Animation.easeOut(duration: slideTime)
    static let glide = Animation.spring(response: glideResponse, dampingFraction: glideDamping)
    static let settle = Animation.spring(response: settleResponse, dampingFraction: settleDamping)

    static var forceStill: Bool?

    static var still: Bool {
        forceStill ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var reduced: Bool { still }

    static func animation(_ kind: Kind) -> Animation {
        switch kind {
        case .snap: return snap
        case .quick: return quick
        case .slide: return slide
        case .glide: return glide
        case .settle: return settle
        }
    }

    static func resolve(_ kind: Kind, still: Bool = Motion.still) -> Animation {
        still ? quick : animation(kind)
    }

    static func with(_ kind: Kind, still: Bool = Motion.still, _ changes: () -> Void) {
        withAnimation(interaction(kind, still: still), changes)
    }

    static func interaction(_ kind: Kind, still: Bool = Motion.still) -> Animation? {
        NSApp.currentEvent?.type == .keyDown ? nil : resolve(kind, still: still)
    }

    static func delay(_ seconds: TimeInterval, still: Bool = Motion.still) -> TimeInterval {
        still ? 0 : seconds
    }
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    let kind: Motion.Kind
    let value: Value
    @Environment(\.restrainedMotion) private var still

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(kind, still: still), value: value)
    }
}

private struct MotionTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.restrainedMotion) private var still

    func body(content: Content) -> some View {
        content.transition(still ? .opacity : transition)
    }
}

private struct MotionMatch<ID: Hashable>: ViewModifier {
    let id: ID
    let space: Namespace.ID
    var properties: MatchedGeometryProperties = .frame
    var anchor: UnitPoint = .center
    @Environment(\.restrainedMotion) private var still

    func body(content: Content) -> some View {
        if still {
            content
        } else {
            content.matchedGeometryEffect(id: id, in: space, properties: properties, anchor: anchor)
        }
    }
}

extension View {
    func animated<Value: Equatable>(_ kind: Motion.Kind, value: Value) -> some View {
        modifier(MotionAnimation(kind: kind, value: value))
    }

    func transitioned(_ transition: AnyTransition) -> some View {
        modifier(MotionTransition(transition: transition))
    }

    func matched<ID: Hashable>(
        id: ID,
        in space: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center
    ) -> some View {
        modifier(MotionMatch(id: id, space: space, properties: properties, anchor: anchor))
    }
}

/// The one filled button on a surface. Disabled, it steps back to a quiet wash
/// instead of a dimmed slab of accent, so "not yet" never reads as "broken".
/// `.controlSize(.large)` gives the hero size used where a page has one action.
struct PrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.restrainedMotion) private var still
    @Environment(\.controlSize) private var size
    @State private var hovering = false

    private var large: Bool { size == .large || size == .extraLarge }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: large ? Radius.row + 2 : Radius.row, style: .continuous)
        let pressed = enabled && configuration.isPressed
        return configuration.label
            .font((large ? Font.system(size: 14) : TypeScale.body).weight(.semibold))
            .foregroundStyle(enabled ? Color.white : Palette.faint.color)
            .lineLimit(1)
            .padding(.horizontal, large ? 22 : 16)
            .frame(minWidth: 76, minHeight: large ? 40 : ButtonMetrics.height)
            .background {
                if enabled {
                    shape.fill(Palette.accentFill)
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center)))
                        .overlay(shape.fill(Color.white.opacity(hovering && !pressed ? 0.08 : 0)))
                        .overlay(shape.fill(Color.black.opacity(pressed ? 0.14 : 0)))
                        .shadow(color: Palette.accentFill.color.opacity(hovering ? 0.38 : 0.24), radius: hovering ? 10 : 6, y: 2)
                } else {
                    shape.fill(Palette.wash)
                }
            }
            .overlay(shape.strokeBorder(enabled ? Color.white.opacity(0.16) : Palette.hairline.color, lineWidth: 1))
            .scaleEffect(!still && pressed ? 0.96 : 1)
            .contentShape(shape)
            .onHover { hovering = enabled && $0 }
            .animation(pressed ? .easeOut(duration: 0.15) : Motion.resolve(.settle, still: still), value: pressed)
            .animated(.quick, value: hovering)
            .animated(.quick, value: enabled)
    }
}

struct PressStyle: ButtonStyle {
    enum Shape {
        case control, row, card, panel, capsule

        var radius: CGFloat {
            switch self {
            case .control: return Radius.control
            case .row: return Radius.row
            case .card: return Radius.card
            case .panel: return Radius.panel
            case .capsule: return .infinity
            }
        }
    }

    var shape: Shape = .row
    var icon = false
    var rest: Tone = .clear

    init(_ shape: Shape = .row, icon: Bool = false, rest: Tone = .clear) {
        self.shape = shape
        self.icon = icon
        self.rest = rest
    }

    @Environment(\.isEnabled) private var enabled
    @Environment(\.restrainedMotion) private var still
    @State private var hovering = false
    private func fill(pressed: Bool) -> Tone {
        if pressed { return Palette.wash }
        if hovering { return Palette.hover }
        return rest
    }

    private var corners: RoundedRectangle {
        RoundedRectangle(cornerRadius: shape.radius, style: .continuous)
    }

    /// Small controls press to 0.96; wide tiles and rows to 0.98, since the same
    /// ratio on a 200-point tile moves its edges far more than on a button.
    private var pressScale: CGFloat {
        switch shape {
        case .control, .capsule: return 0.96
        case .row: return icon ? 0.96 : 0.98
        case .card, .panel: return 0.99
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(corners.fill(fill(pressed: configuration.isPressed).opacity(0.55)))
            .scaleEffect(!still && enabled && configuration.isPressed ? pressScale : 1)
            .opacity(enabled ? 1 : 0.35)
            .animated(.quick, value: hovering)
            .animation(configuration.isPressed ? .easeOut(duration: 0.15) : Motion.resolve(.settle, still: still), value: configuration.isPressed)
            .onHover { hovering = enabled && $0 }
    }
}
