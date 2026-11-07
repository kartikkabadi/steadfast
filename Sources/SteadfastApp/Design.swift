import SwiftUI
import AppKit

/// The Steadfast mark: two leaning bars, drawn in proportion to its frame so
/// it reads the same at 12 points in the menu as at 26 in the block ring.
struct PauseMark: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let bar = w * 0.36, gap = w - bar * 2
            HStack(spacing: gap) {
                Capsule().frame(width: bar)
                Capsule().frame(width: bar)
            }
            .frame(width: w, height: h * 0.88)
            .rotationEffect(.degrees(5))
            .frame(width: w, height: h)
        }
    }
}

struct WindowBridge: NSViewRepresentable {
    final class Access: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false; window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.titlebarSeparatorStyle = .none
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView { Access() }
    func updateNSView(_ view: NSView, context: Context) {}
}
/// Shared size for every text button, so paired buttons always match.
enum ButtonMetrics {
    static let height: CGFloat = 32
    static let minWidth: CGFloat = 76
    static let font = TypeScale.body.weight(.medium)
}

/// A compact action aligned to the trailing edge of a settings row.
struct RowActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .font(TypeScale.chrome.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(configuration.role == .destructive ? Palette.danger : Palette.ink)
            .padding(.horizontal, 12)
            .frame(minWidth: 76, minHeight: 28)
            .background(shape.fill(configuration.isPressed ? Palette.hover : hovering ? Palette.hover.opacity(0.7) : Palette.wash))
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.35)
            .onHover { hovering = enabled && $0 }
            .animated(.quick, value: hovering)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ButtonMetrics.font)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minWidth: ButtonMetrics.minWidth, minHeight: ButtonMetrics.height)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(PressStyle(.row, rest: Palette.wash))
    }
}

/// A text-only action for the way out of a moment, where a second filled
/// button would compete with the one that matters.
struct QuietLink: View {
    let title: String
    /// Leading: the text, not its hover plate, meets the column's left edge.
    var leading = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TypeScale.body.weight(.medium))
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(.control))
        .padding(.leading, leading ? -10 : 0)
        .onHover { hovering = $0 }
        .animated(.quick, value: hovering)
    }
}

extension View {
    func sheetLayout(width: CGFloat = Sheet.width) -> some View {
        padding(28).frame(width: width)
            .focusEffectDisabled()
            .font(TypeScale.body).foregroundStyle(Palette.ink).tint(Palette.accent.color)
            .background(Palette.ground)
    }

    func sheetTitle() -> some View {
        font(.system(size: 20, weight: .semibold)).tracking(-0.3)
            .accessibilityAddTraits(.isHeader)
    }

    func formField() -> some View {
        textFieldStyle(.plain).padding(.horizontal, Inset.row).frame(height: 32)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(Palette.hairline).allowsHitTesting(false))
    }
}
struct ShieldMark: View {
    var size: CGFloat = 88
    @Environment(\.restrainedTransparency) private var opaque
    private static let artwork: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()
    var body: some View {
        Group {
            if let artwork = Self.artwork {
                Image(nsImage: artwork).resizable().interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.34, weight: .regular))
                    .foregroundStyle(Palette.accent)
                    .frame(width: size, height: size)
                    .background(opaque ? Palette.wash.color : .clear, in: Circle())
                    .glassEffect(opaque ? .identity : .regular, in: Circle())
            }
        }.accessibilityHidden(true)
    }
}
extension View {
    func quietGroup() -> some View { Card { self } }
}
struct PanelHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(TypeScale.display.weight(.semibold)).tracking(-0.6).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(TypeScale.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

/// A small heading over a card — how a page with more than a handful of
/// rows says which ones go together, instead of a sentence on each.
struct Titled<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(TypeScale.chrome.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.leading, Inset.row)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// The hairline between two lines of a card, inset like the text.
struct Rule: View {
    var inset: CGFloat = Inset.row
    var body: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, inset)
    }
}

/// One thing to set or do: what it is on the left, the control on the right.
struct Line<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: () -> Control
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, _ detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail)
                        .font(TypeScale.chrome)
                        .foregroundStyle(Palette.muted)
                        .opacity(scheme == .dark ? 0.8 : 1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, Inset.row)
        .padding(.vertical, 10)
    }
}

/// The button that leaves a panel.
struct Door: View {
    static let size: CGFloat = 28
    /// Space between the plate's edge and the 13-point X drawn in its middle.
    static let glyphInset: CGFloat = 9
    var icon = "xmark"
    var help = "Close   esc"
    var act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(Symbols.door)
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .frame(width: Self.size, height: Self.size)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(hovering ? Palette.hover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { hovering = $0 }
        .animated(.quick, value: hovering)
        .keyboardShortcut(.cancelAction)
        .help(help)
        .accessibilityLabel(help.components(separatedBy: "   ").first ?? help)
    }
}

/// The plate: a rounded card with a title, a close door, whatever the panel is
/// about, and — when there is one — a foot below a hairline.
struct Plate<Content: View, Foot: View>: View {
    let title: String
    var subtitle: String? = nil
    var width: CGFloat = Sheet.width
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let foot: () -> Foot
    @Environment(\.colorScheme) private var scheme

    init(
        _ title: String,
        subtitle: String? = nil,
        width: CGFloat = Sheet.width,
        close: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder foot: @escaping () -> Foot = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.close = close
        self.content = content
        self.foot = foot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .sheetTitle()
                        .foregroundStyle(Palette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(TypeScale.chrome)
                            .foregroundStyle(Palette.muted)
                            .opacity(scheme == .dark ? 0.8 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Door(icon: "xmark", help: "Close   esc", act: close)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            content()
                .padding(.horizontal, 24)

            if Foot.self != EmptyView.self {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .padding(.top, 18)
                foot()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .frame(width: width, alignment: .leading)
        .background(Palette.ground)
        .focusEffectDisabled()
        .font(TypeScale.body)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent.color)
    }
}

/// Toolbar/header icon action button.
struct FrostedIconButton: View {
    let icon: String
    let help: String
    var isFocused: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Symbols.row)
                .foregroundStyle(isFocused ? Palette.ink : Palette.muted)
                .frame(width: 28, height: 28)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(PressStyle(.control))
        .help(help)
        .accessibilityLabel(help.components(separatedBy: "   ").first ?? help)
    }
}

/// The look every pickable option shares — website tiles, durations, weekdays:
/// a wash at rest, the accent tint once picked.
private struct ChoiceLook: ViewModifier {
    let selected: Bool
    let radius: CGFloat

    @Environment(\.restrainedMotion) private var still

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .foregroundStyle(Palette.ink)
            .background(selected ? Palette.accent.opacity(0.14) : Palette.wash, in: shape)
            .overlay(shape.strokeBorder(selected ? Palette.accent.opacity(0.55) : Palette.hairline, lineWidth: 1))
            .contentShape(shape)
            .animation(still ? nil : .easeOut(duration: 0.15), value: selected)
    }
}

extension View {
    func choice(_ selected: Bool, radius: CGFloat = Radius.control) -> some View {
        modifier(ChoiceLook(selected: selected, radius: radius))
    }
}

/// The one pickable tile: what it is on the left, whether it's picked on the
/// right. Websites, apps, aims and categories all use it, so picking anything in
/// Steadfast looks and behaves the same.
struct ChoiceTile: View {
    enum Glyph {
        case symbol(String)
        case app(bundleID: String, path: String?)
    }
    enum Mark { case off, on, partial, locked }

    let title: String
    let glyph: Glyph
    let mark: Mark
    var help: String? = nil
    let action: () -> Void

    init(_ title: String, glyph: Glyph, mark: Mark, help: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.glyph = glyph; self.mark = mark; self.help = help; self.action = action
    }

    init(_ title: String, symbol: String, selected: Bool, help: String? = nil, action: @escaping () -> Void) {
        self.init(title, glyph: .symbol(symbol), mark: selected ? .on : .off, help: help, action: action)
    }

    private var selected: Bool { mark == .on }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    switch glyph {
                    case let .symbol(name):
                        Image(systemName: name).font(Symbols.header)
                            .foregroundStyle(selected ? Palette.accent : Palette.muted)
                    case let .app(bundleID, path):
                        AppIcon(bundleID: bundleID, path: path, size: 20)
                    }
                }
                .frame(width: 20)
                .accessibilityHidden(true)
                Text(title).font(TypeScale.body.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                // Only a decided state earns a mark; an empty circle on every
                // unpicked tile is noise that makes the whole grid look like a form.
                if let indicator {
                    Group {
                        if mark == .on {
                            Image(systemName: indicator)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Palette.accentFill.color)
                        } else {
                            Image(systemName: indicator).foregroundStyle(mark == .locked ? Palette.muted : Palette.accent)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                        .transition(.scale(scale: 0.25).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0), value: mark)
            .padding(.horizontal, Inset.row).frame(height: 40)
            .choice(selected, radius: Radius.row)
        }
        .buttonStyle(PressStyle(.row))
        .disabled(mark == .locked)
        .help(mark == .locked ? "Already blocked" : help ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var indicator: String? {
        switch mark {
        case .off: return nil
        case .on: return "checkmark.circle.fill"
        case .partial: return "minus.circle"
        case .locked: return "lock.fill"
        }
    }

    private var value: String {
        switch mark {
        case .off: return "not selected"
        case .on: return "selected"
        case .partial: return "partly selected"
        case .locked: return "already blocked"
        }
    }
}

/// The trailing mark on a pickable list row: a filled check once picked,
/// nothing otherwise — the same mark ChoiceTile uses.
struct PickMark: View {
    let on: Bool
    var body: some View {
        ZStack {
            if on {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Palette.accentFill.color)
                    .transition(.scale(scale: 0.25).combined(with: .opacity))
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(width: 16, height: 16)
        .animation(.spring(duration: 0.3, bounce: 0), value: on)
        .accessibilityHidden(true)
    }
}

/// A text field whose placeholder reads as one: muted, never mistaken for an answer.
struct FormField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder; _text = text
    }

    var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.muted)).formField()
    }
}

/// Tiles in even columns, the same gaps everywhere.
struct TileGrid<Content: View>: View {
    var columns = 3
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            content()
        }
    }
}

extension VerticalAlignment {
    private enum TitleLine: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    /// The centre of a page title's first line.
    static let titleLine = VerticalAlignment(TitleLine.self)
}

/// The heading at the top of each page, with its one action on the right.
struct PageHeading<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        // The action centres on the title line, never on title + detail, so it
        // sits at the same height on every page whether or not there's a detail.
        HStack(alignment: .titleLine, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TypeScale.display.weight(.semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
                if let detail {
                    Text(detail).font(TypeScale.body).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 8)
            trailing()
                .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
        }
    }
}

/// A section label inside a page: a step of the form, not a card title.
struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(TypeScale.title)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A small caption pill for a duration or status beside a name.
struct Tag: View {
    let text: String
    var tone: Tone = Palette.muted

    var body: some View {
        Text(text)
            .font(TypeScale.caption)
            .monospacedDigit()
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tone == Palette.danger ? Palette.danger.opacity(0.12) : Palette.wash,
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// Navigation bar capsule segmented control.
struct PageNavPill: View {
    @Binding var selected: AppPage
    var disabled: Bool = false
    @Namespace private var navSpace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppPage.allCases, id: \.self) { page in
                let isCurrent = selected == page
                Button {
                    Motion.with(.quick) {
                        selected = page
                    }
                } label: {
                    Text(page.title)
                        .font(TypeScale.chrome.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Palette.ink : Palette.muted)
                        .padding(.horizontal, Inset.row)
                        .frame(height: 28)
                        .background {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .fill(Palette.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                            .strokeBorder(Palette.hairline, lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "nav-active", in: navSpace)
                            }
                        }
                }
                .buttonStyle(PressStyle(.control))
                .disabled(disabled)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}


// Cedar toolbar control.
struct QuietToolButton: View {
    let icon: String
    let help: String
    var disabled = false
    /// On: the filled glyph takes the accent, as a picked star does.
    var on = false
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(Symbols.row)
                .foregroundStyle(disabled ? Palette.faint : on ? Palette.accent : (hovering ? Palette.ink : Palette.muted))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(hovering && !disabled ? Palette.hover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animated(.quick, value: hovering)
        .help(help)
        // The tip may carry the key after three spaces; the name is the words.
        .accessibilityLabel(help.components(separatedBy: "   ").first ?? help)
    }
}


// Cedar panel search field; its clear button uses the shared toolbar control.
struct Hunt<Focus: Hashable>: View {
    @Binding var text: String
    var prompt = "Search"
    var focus: FocusState<Focus?>.Binding
    var field: Focus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Symbols.row)
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Palette.muted))
                .textFieldStyle(.plain)
                .foregroundStyle(Palette.ink)
                .font(TypeScale.body)
                .accessibilityLabel(prompt)
                .focused(focus, equals: field)
            QuietToolButton(icon: "xmark.circle.fill", help: "Clear search", disabled: text.isEmpty) { text = "" }
                .opacity(text.isEmpty ? 0 : 1).accessibilityHidden(text.isEmpty)
        }
        .padding(.horizontal, Inset.row)
        .padding(.vertical, 8)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}


struct ServiceSetup: View {
    @Bindable var model: Model
    @State private var repairing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.connecting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to the background service…").font(TypeScale.chrome).foregroundStyle(Palette.muted)
                }
            } else if CommandLine.arguments.contains("--preview") {
                Text("The preview service is unavailable.").font(TypeScale.body.weight(.semibold))
                Button("Retry Connection") { Task { await model.refresh(showProgress: true) } }
                    .buttonStyle(PrimaryStyle())
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.installationNeedsUpdate ? "arrow.triangle.2.circlepath" : model.needsBlockingSetup ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                        .font(Symbols.header)
                        .foregroundStyle(model.needsBlockingSetup ? Palette.accent : Palette.danger)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.installationNeedsUpdate ? "Service update required" : model.needsBlockingSetup ? "Turn on blocking" : "Protection needs attention")
                            .font(TypeScale.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)

                        Text(model.installationNeedsUpdate ? "Install the latest background service version to reconnect." : model.needsBlockingSetup ? "A small background service does the blocking, so a block holds even when Steadfast is closed." : model.snapshot?.enforcementError?.asSentence ?? "Could not connect to the background service. Retry or run the installer to repair it.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        HStack(spacing: 8) {
                            if model.installationNeedsUpdate {
                                Button("Install Update") { model.install() }
                                    .buttonStyle(PrimaryStyle())
                            } else if model.needsBlockingSetup {
                                Button("Turn On Blocking…") { model.panel = .onboarding }
                                    .buttonStyle(PrimaryStyle())
                            } else {
                                Button("Retry Connection") { Task { await model.refresh(showProgress: true) } }
                                    .buttonStyle(PrimaryStyle())
                                SecondaryButton(title: "Repair Service…") { repairing = true }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Repair Blocking Service?", isPresented: $repairing, titleVisibility: .visible) {
            Button("Open Installer") { model.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The installer will open in Terminal and request administrator approval to restore local DNS enforcement.")
        }
    }
}

extension String {
    /// Service and validation messages are written as lowercase fragments so they
    /// can be joined into other text. Shown on their own they read as sentences:
    /// each one capitalised (unless it opens with a domain) and closed with a stop.
    var asSentence: String {
        let parts = components(separatedBy: ". ").map { part -> String in
            guard let first = part.first, first.isLowercase else { return part }
            let word = part.prefix { !$0.isWhitespace }
            if word.contains(".") || word.contains("@") || word.contains("/") { return part }
            return first.uppercased() + part.dropFirst()
        }
        var text = parts.joined(separator: ". ").trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = text.last, !".!?…”\"".contains(last) { text += "." }
        return text
    }
}

/// A problem under the thing it's about: one danger line, readable and selectable.
struct ErrorNote: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label(message.asSentence, systemImage: "exclamationmark.circle")
            .font(TypeScale.chrome)
            .foregroundStyle(Palette.danger)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
