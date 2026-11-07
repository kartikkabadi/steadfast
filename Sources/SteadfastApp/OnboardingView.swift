import SwiftUI
import AppKit
import SteadfastCore

struct OnboardingView: View {
    @Bindable var model: Model

    enum Page: Int, CaseIterable {
        case welcome, aim, activity, blocklist, start
        var name: String {
            switch self {
            case .welcome: "Welcome"
            case .aim: "Your time"
            case .activity: "Activity history"
            case .blocklist: "Distractions"
            case .start: "First block"
            }
        }
    }

    private enum Purpose: String, CaseIterable {
        case think = "Time to think", project = "A project", rest = "Time off", custom = "Something else"

        var symbol: String {
            switch self {
            case .think: "lightbulb"
            case .project: "pencil.and.outline"
            case .rest: "leaf"
            case .custom: "ellipsis"
            }
        }
    }

    @State private var page: Page
    @State private var title: String
    @State private var customPurpose: Bool
    @FocusState private var purposeFocused: Bool
    @State private var customDuration = false
    @State private var customDomain = ""
    @State private var showApps: Bool
    @State private var forward = true
    private let catalog = AppCatalog.shared

    init(model: Model, appsExpanded: Bool = false) {
        self.model = model
        _page = State(initialValue: model.onboardingStep.flatMap(Page.init(rawValue:)) ?? .welcome)
        let savedTitle = model.outcomes.aim?.title ?? ""
        _title = State(initialValue: savedTitle)
        _customPurpose = State(initialValue: !savedTitle.isEmpty && Purpose(rawValue: savedTitle) == nil)
        _showApps = State(initialValue: appsExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PauseMark().frame(width: 14, height: 17).foregroundStyle(Palette.accent).accessibilityHidden(true)
                Text("Steadfast").font(TypeScale.body.weight(.semibold))
                Spacer()
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            ScrollViewReader { scroll in
                ScrollView {
                    Group {
                        switch page {
                        case .welcome: welcome
                        case .aim: aim
                        case .activity: activity
                        case .blocklist: distractions
                        case .start: start
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 32).padding(.vertical, 36)
                    .frame(maxWidth: .infinity)
                    .id(page)
                    .transitioned(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: forward ? .trailing : .leading)),
                        removal: .opacity
                    ))
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.top)
                .onChange(of: showApps) { _, expanded in
                    if expanded { scroll.scrollTo("onboarding-apps", anchor: .top) }
                }
            }

            if page != .welcome {
                ZStack {
                    Text("\(page.rawValue) of 4").font(TypeScale.caption).foregroundStyle(Palette.muted)
                    HStack {
                        QuietLink(title: "Back", leading: true) { move(-1) }
                        Spacer()
                        Button(primaryTitle, action: advance)
                            .buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
                            .disabled(model.busy || (page == .start && model.connecting))
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .font(TypeScale.body).foregroundStyle(Palette.ink).tint(Palette.accent.color)
        .background(Glass(cornerRadius: 0, veiled: true).ignoresSafeArea())
        .onExitCommand { finish(review: false) }
        .task { catalog.load() }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Make room for what you want to do.")
                    .font(.system(size: 32, weight: .semibold)).tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Text("Choose the distractions to block. Keep time for yourself.")
                    .font(.system(size: 17)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ExampleBlock()
            HStack(spacing: 16) {
                Button("Get Started") { move(1) }
                    .buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
                QuietLink(title: "Skip Setup") { finish(review: false) }
            }
            Text("No account. Your choices stay on this Mac.")
                .font(TypeScale.chrome).foregroundStyle(Palette.muted)
        }
    }

    private var aim: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading("What do you want time for?")
            VStack(spacing: 8) {
                ForEach(Purpose.allCases, id: \.self) { purpose in
                    let selected = purpose == .custom ? customPurpose : !customPurpose && title == purpose.rawValue
                    Button {
                        if purpose == .custom {
                            if !customPurpose { title = "" }
                            customPurpose = true
                        } else {
                            customPurpose = false
                            title = purpose.rawValue
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: purpose.symbol)
                                .font(.system(size: 18)).frame(width: 24)
                                .foregroundStyle(selected ? Palette.accent : Palette.muted)
                                .accessibilityHidden(true)
                            Text(purpose.rawValue).font(TypeScale.body.weight(.medium))
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? Palette.accent : Palette.faint)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 48)
                        .choice(selected, radius: Radius.row)
                    }
                    .buttonStyle(PressStyle(.row))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                if customPurpose {
                    FormField("Read more", text: $title)
                        .accessibilityLabel("What you want time for, optional")
                        .focused($purposeFocused)
                        .onAppear { purposeFocused = true }
                        .onChange(of: title) { _, value in title = String(value.prefix(200)) }
                        .padding(.top, 4)
                }
            }
        }
    }

    private var distractions: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading("What distracts you?")
            QuickWebsites(model: model, columns: 2)
            HStack(spacing: 8) {
                FormField("Another website", text: $customDomain)
                    .accessibilityLabel("Add another website").onSubmit(addDomain)
                Button("Add", action: addDomain).buttonStyle(RowActionStyle())
                    .disabled(customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let custom = model.chosen.subtracting(QuickWebsites.domains).sorted()
            if !custom.isEmpty {
                ForEach(custom, id: \.self) { domain in
                    HStack {
                        Text(domain).lineLimit(1)
                        Spacer()
                        Button("Remove") { model.chosen.remove(domain) }.buttonStyle(RowActionStyle())
                            .accessibilityLabel("Remove \(domain)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Motion.with(.settle) { showApps.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(Symbols.small).foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(showApps ? 90 : 0))
                            .accessibilityHidden(true)
                        Text("Apps on this Mac")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showApps ? "Expanded" : "Collapsed")
                .id("onboarding-apps")
                if showApps {
                    LazyVStack(spacing: 0) {
                        ForEach(catalog.apps) { app in
                            AppRow(model: model, app: app.blocked, path: app.path)
                        }
                    }
                }
            }
            if let error = model.error { ErrorNote(error) }
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading("See where your time goes")
            ExampleActivity()
            ActivityControls(store: model.outcomes)
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading("How long?", detail: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title)
            if model.serviceReady {
                HStack {
                    Text(model.hasDraftTargets ? model.draftTargetLabel : "No distractions chosen")
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    QuietLink(title: "Change") { move(-1) }
                }
                BlockDurationControls(model: model, custom: $customDuration)
                Text("You can't pause or end a block early.")
                    .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Palette.accent)
                    Text("Service ready").font(TypeScale.chrome)
                    Spacer()
                    QuietLink(title: "Check Browser") {
                        saveAim()
                        model.completeOnboarding()
                        model.panel = .browserCheck
                    }
                    .disabled(model.snapshot?.sandbox != false)
                }
            } else {
                ServiceSetup(model: model)
            }
            if let error = model.error { ErrorNote(error) }
        }
    }

    private var primaryTitle: String {
        if page == .aim, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Skip" }
        guard page == .start else { return "Continue" }
        if !model.serviceReady { return model.connecting ? "Checking…" : "Done" }
        return model.hasDraftTargets ? "Review Block" : "Done"
    }

    private func addDomain() {
        model.text = customDomain
        if model.addCustomSites() { customDomain = "" }
        else { model.text = "" }
    }

    @discardableResult private func move(_ offset: Int) -> Bool {
        guard let next = Page(rawValue: page.rawValue + offset) else { return false }
        saveAim()
        model.error = nil
        forward = offset > 0
        model.onboardingStep = next.rawValue
        Motion.with(.settle) { page = next }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: next.name, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }

    private func advance() {
        if page == .start { finish(review: model.serviceReady && model.hasDraftTargets) }
        else { move(1) }
    }

    private func saveAim() {
        let value = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !value.isEmpty else {
            if model.outcomes.aim != nil { model.outcomes.aim = nil }
            return
        }
        var aim = model.outcomes.aim ?? Aim(title: value, kind: .other)
        aim.title = value
        if aim != model.outcomes.aim { model.outcomes.aim = aim }
    }

    private func finish(review: Bool) {
        saveAim()
        model.completeOnboarding(startFirstBlock: review)
    }
}
