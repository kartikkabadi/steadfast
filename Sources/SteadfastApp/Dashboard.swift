import SwiftUI
import AppKit
import SteadfastCore

struct RootView: View {
    @Bindable var model: Model
    @State private var offerBrowserCheck = CommandLine.arguments.contains("--first-install")
    @State private var customDuration = false
    @State private var compactLayout = false
    @State private var windowWidth: CGFloat = 900

    enum Control: Hashable {
        case websites, apps, review, repeatLast, favorite(UUID), addBlock, limits, settings
        case purpose, newRoutine, routineStart(UUID), routineOptions(UUID), repeatBlock(UUID), saveAsRoutine(UUID)
    }

    @FocusState private var focused: Control?
    @State private var returnFocus: Control?
    @State private var showAllUnlocks = false
    private let contentWidth: CGFloat = 640
    private let sideInset: CGFloat = 32
    private var drafting: Bool { model.composing }
    /// Keeps the wordmark clear of the traffic lights when the column reaches the window edge.
    private var brandClearance: CGFloat {
        let column = min(windowWidth - sideInset * 2, contentWidth)
        return max(0, 78 - (windowWidth - column) / 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: compactLayout ? 20 : 28) {
                        if model.snapshot?.sandbox == true, CommandLine.arguments.contains("--preview") {
                            Text("Preview · websites and apps on this Mac stay available")
                                .font(TypeScale.caption).foregroundStyle(Palette.muted)
                        }
                        if let error = model.error, model.panel == nil {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").font(Symbols.row).foregroundStyle(Palette.danger)
                                    .padding(.top, 1)
                                Text(error.asSentence).font(TypeScale.chrome).foregroundStyle(Palette.danger).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, Inset.row)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        }

                        switch model.page {
                        case .block:
                            if !model.serviceReady {
                                Card { ServiceSetup(model: model).padding(16) }
                            }
                            if model.hasActiveBlocks, !model.composing {
                                commitments
                            }
                            if model.serviceReady {
                                if drafting { composer.id("draft") }
                                else if !model.hasActiveBlocks { home }
                            }
                            if !model.dailyLimits.isEmpty, model.snapshot != nil {
                                limitsSummary
                            }
                        case .routines:
                            RoutinesView(model: model, focus: $focused, returnFocus: $returnFocus)
                        case .history:
                            HistoryView(model: model, focus: $focused, returnFocus: $returnFocus, compact: compactLayout, narrow: windowWidth < 720)
                        }
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .padding(.horizontal, sideInset)
                    .padding(.top, compactLayout ? 4 : 12)
                    .padding(.bottom, compactLayout ? 16 : 32)
                    .frame(maxWidth: .infinity)
                    .id("page-content")
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.page == .block, drafting, model.serviceReady {
                        draftBar.transition(.opacity)
                    }
                }
                .onChange(of: model.composing) { _, composing in
                    if composing { Motion.with(.slide) { proxy.scrollTo("draft", anchor: .top) } }
                }
                .onChange(of: model.page) { _, _ in
                    proxy.scrollTo(model.page == .block && model.composing ? "draft" : "page-content", anchor: .top)
                }
                .onChange(of: customDuration) { _, custom in
                    if custom { Motion.with(.slide) { proxy.scrollTo("draft", anchor: .bottom) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            compactLayout = size.height < 625
            windowWidth = size.width
        }
        .font(TypeScale.body).foregroundStyle(Palette.ink).tint(Palette.accent.color)
        .background(Glass(cornerRadius: 0, veiled: true).ignoresSafeArea()).background(WindowBridge())
        .onboardingStage(model)
        .sheet(item: sheetPanel, onDismiss: {
            model.clearCompletedDraft()
            if model.editingReview {
                model.editingReview = false
                focused = .review
            } else if let returnFocus {
                if model.page == .block && !drafting && returnFocus != .limits && returnFocus != .settings {
                    focused = .addBlock
                } else {
                    focused = returnFocus
                }
            }
            returnFocus = nil
        }) { panel in
            switch panel {
            case .websites: WebsitePicker(model: model)
            case .apps: AppPicker(model: model)
            case .routine: RoutineEditor(model: model, routine: model.editingRoutine, seed: model.routineSeed)
            case .settings: SettingsView(model: model)
            case .browserCheck: BrowserCheckView(model: model)
            case .commitment: CommitmentFlow(model: model)
            case .dailyLimits: DailyLimitsView(model: model)
            case .onboarding: EmptyView() // Shown over the whole window by onboardingStage.
            }
        }
        .task {
            if !model.hasCompletedOnboarding, model.panel == nil {
                model.panel = .onboarding
            }
        }
        .alert("Couldn't open setup", isPresented: Binding(get: { model.setupError != nil }, set: { if !$0 { model.setupError = nil } })) {
            Button("OK", role: .cancel) { model.setupError = nil }
        } message: { Text((model.setupError ?? "").asSentence) }
        .onChange(of: model.error) { _, message in
            if let message { NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]) }
        }
        .onChange(of: model.amountText) { model.error = nil }
        .onChange(of: model.multiplier) { model.error = nil }
        .onChange(of: model.hasDraftTargets) { _, selected in
            if !selected { customDuration = false }
        }
        .onChange(of: model.hasActiveBlocks) { _, active in
            if !active { showAllUnlocks = false }
        }
        .task { AppCatalog.shared.load() }
        .focusEffectDisabled()
        .onChange(of: model.searchRequested) { model.openComposer() }
        .onChange(of: model.serviceReady, initial: true) { _, ready in
            guard ready, offerBrowserCheck, model.panel == nil, model.snapshot?.sandbox == false else { return }
            offerBrowserCheck = false
            model.panel = .browserCheck
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            PageNavPill(selected: $model.page, disabled: model.busy)
            HStack(spacing: 8) {
                PauseMark().frame(width: 14, height: 17).foregroundStyle(Palette.accent).accessibilityHidden(true)
                Text("Steadfast")
                    .font(TypeScale.body.weight(.semibold))
                    .tracking(-0.2)
                Spacer()
                FrostedIconButton(
                    icon: "gearshape",
                    help: "Settings   ⌘,",
                    isFocused: focused == .settings,
                    action: { openHeaderPanel(.settings, from: .settings) }
                )
                .focusable().focused($focused, equals: .settings)
            }
            .padding(.leading, brandClearance)
        }
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, sideInset)
        .frame(maxWidth: .infinity)
        .padding(.top, compactLayout ? 12 : 16)
        .padding(.bottom, compactLayout ? 12 : 20)
    }

    // MARK: - Home

    private var home: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.outcomes.aim?.title ?? "Time for what you choose.")
                    .font(.system(size: 36, weight: .semibold)).tracking(-0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(homeDetail).font(TypeScale.body).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(homeAction, action: repeatOrCreate)
                        .buttonStyle(PrimaryStyle())
                        .focusable().focused($focused, equals: .addBlock).disabled(model.busy)
                    if model.lastBlock != nil || !model.favorites.isEmpty {
                        QuietLink(title: "New Block") { model.startDraft() }
                            .disabled(model.busy)
                    }
                }.padding(.top, 6)
            }
            .padding(.vertical, compactLayout ? 12 : 28)

            if !model.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Your routines")
                    ForEach(model.favorites.prefix(3)) { routine in
                        Button {
                            returnFocus = .favorite(routine.id)
                            model.prepareRoutine(routine)
                        } label: {
                            HStack {
                                Text(routine.name).font(TypeScale.body.weight(.medium))
                                Spacer()
                                Text(DurationLabel.text(routine.minutes)).foregroundStyle(Palette.muted)
                                Image(systemName: "arrow.right").foregroundStyle(Palette.muted).accessibilityHidden(true)
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).focusable().focused($focused, equals: .favorite(routine.id))
                        .disabled(model.busy)
                        Rule(inset: 0)
                    }
                }
            }

            if let block = model.latestUnreviewedBlock {
                BlockReflectionView(store: model.outcomes, block: block)
            }
            activitySummary
            if let next = model.nextRun {
                Text("Next: \(next.name) · \(next.start.blockTime)")
                    .font(TypeScale.chrome).foregroundStyle(Palette.muted)
            }
            if let error = model.outcomes.saveError { ErrorNote(error) }
        }
    }

    private var activitySummary: some View {
        let today = model.outcomes.days.filter { $0.day == Ledger.dayKey(Date()) }
        let totals = UsageSummary.totals(today, since: Ledger.dayKey(Date()))
        let appSeconds = totals.filter(\.isApp).reduce(0) { $0 + $1.seconds }
        let sites = totals.filter { !$0.isApp }
        return VStack(alignment: .leading, spacing: 14) {
            Rule(inset: 0)
            HStack {
                Text(model.outcomes.trackingEnabled ? "Today on this Mac" : "Your activity history")
                    .font(TypeScale.body.weight(.medium))
                Spacer()
                QuietLink(title: "Open") { model.progressActivity = true; model.page = .history }
                    .accessibilityLabel("Open app and website activity history")
            }
            if appSeconds > 0 {
                Text("\(ActivityTime.short(appSeconds)) of recorded active time")
                    .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                ForEach(Array((sites.isEmpty ? totals.filter(\.isApp) : sites).prefix(3))) { item in
                    HStack {
                        Text(model.outcomes.name(for: item)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(ActivityTime.short(item.seconds)).monospacedDigit()
                    }.font(TypeScale.chrome).foregroundStyle(Palette.muted)
                }
            } else {
                Text(model.outcomes.trackingEnabled ? "Activity appears as you use other apps." : "See where your time goes. Recording is optional.")
                    .font(TypeScale.chrome).foregroundStyle(Palette.muted)
            }
        }
    }

    private var homeDetail: String {
        if let last = model.lastBlock {
            return "\(last.name ?? "Your last setup") · \(last.targetLabel) · \(DurationLabel.text(last.durationMinutes))"
        }
        if let first = model.favorites.first {
            return "Your routine is ready: \(first.name) · \(DurationLabel.text(first.minutes))."
        }
        return "Choose the apps and websites you want to block."
    }

    private var homeAction: String {
        if model.lastBlock != nil { return "Review Last Setup" }
        return model.favorites.isEmpty ? "Choose Distractions" : "Review Routine"
    }

    private func repeatOrCreate() {
        if let last = model.lastBlock {
            returnFocus = .addBlock
            model.reuseBlock(last)
        } else if let first = model.favorites.first {
            returnFocus = .addBlock
            model.prepareRoutine(first)
        } else { model.startDraft() }
    }

    // MARK: - Active blocks

    private var commitments: some View {
        let unlocks = model.websiteUnlocks
        let appUnlocks = model.appUnlocks
        let total = unlocks.count + appUnlocks.count
        let shownApps = showAllUnlocks ? appUnlocks : Array(appUnlocks.prefix(6))
        let shown = showAllUnlocks ? unlocks : Array(unlocks.prefix(max(0, 6 - shownApps.count)))
        // A used-up daily limit runs to midnight; the countdown is for the blocks themselves.
        let blockEnds = model.active.map(\.endsAt)
        let ends = blockEnds.isEmpty ? unlocks.map(\.end) + appUnlocks.map(\.end) : blockEnds
        let sameEnd = Set(ends).count == 1
        return VStack(alignment: .leading, spacing: 20) {
            PageHeading(model.serviceReady ? "Active blocks" : "Last known blocks") {
                if model.serviceReady {
                    SecondaryButton(title: "Add Another Block") { model.startDraft() }
                        .focusable().focused($focused, equals: .addBlock).disabled(model.busy)
                        .help("New block   ⌘N")
                }
            }

            if let last = ends.max(), let next = ends.min() {
                TimelineView(.countdown(to: last)) { context in
                    let now = max(context.date, model.currentTime)
                    if let block = model.holdingBlock {
                        BlockHold(block: block, end: last, now: now,
                                  aim: model.outcomes.aim,
                                  unlocks: unlockSentence(last: last, next: next, sameEnd: sameEnd),
                                  verified: model.serviceReady)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(Remaining.text(until: last, from: now)) left")
                                .font(TypeScale.hero)
                                .monospacedDigit()
                                .tracking(-0.8)
                                .contentTransition(.numericText(countsDown: true))
                            Text(unlockSentence(last: last, next: next, sameEnd: sameEnd))
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Titled(total == 1 ? "Blocked" : "Blocked · \(total)") {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(shownApps.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Rule() }
                            HStack(alignment: .center, spacing: 12) {
                                AppIcon(bundleID: item.app.bundleID, size: 18)
                                    .frame(width: 16)
                                Text(item.app.name)
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                if !sameEnd {
                                    Text(item.end.blockTime)
                                        .font(TypeScale.chrome)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            .padding(.horizontal, Inset.row)
                            .frame(minHeight: 36)
                            .help(item.app.bundleID)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(model.serviceReady ? "app, unlocks \(item.end.blockDeadline)" : "app, expected to unlock \(item.end.blockDeadline)")
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            if index > 0 || !shownApps.isEmpty { Rule() }
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .font(Symbols.row)
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 16)
                                    .accessibilityHidden(true)
                                Text(item.domain)
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                if item.dailyLimitReached {
                                    Tag(text: "Daily limit", tone: Palette.danger)
                                }
                                Spacer(minLength: 8)
                                if !sameEnd || item.dailyLimitReached {
                                    Text(item.end.blockTime)
                                        .font(TypeScale.chrome)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            .padding(.horizontal, Inset.row)
                            .frame(minHeight: 36)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(model.serviceReady ? "unlocks \(item.end.blockDeadline)" : "expected to unlock \(item.end.blockDeadline)")
                        }
                        if total > 6 {
                            Rule(inset: 0)
                            Button {
                                Motion.with(.settle) { showAllUnlocks.toggle() }
                            } label: {
                                Text(showAllUnlocks ? "Show Fewer" : "Show All \(total)")
                                    .font(TypeScale.chrome.weight(.medium))
                                    .foregroundStyle(Palette.muted)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(.row))
                        }
                    }
                }
            }
        }
    }

    private func unlockSentence(last: Date, next: Date, sameEnd: Bool) -> String {
        let websites = !model.websiteUnlocks.isEmpty, apps = !model.appUnlocks.isEmpty
        if sameEnd {
            let subject = websites && apps ? "Everything" : apps ? "Apps" : "Websites"
            let verb = model.serviceReady ? (subject == "Everything" ? "unlocks" : "unlock") : "expected to unlock"
            return "\(subject) \(verb) \(last.blockDeadline)"
        }
        let verb = model.serviceReady ? "unlocks" : "expected to unlock"
        let first = websites && apps ? "The first block" : apps ? "The first app" : "The first website"
        return "\(first) \(verb) \(next.blockDeadline), the last \(last.blockDeadline)"
    }

    // MARK: - Draft

    private var composer: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 16 : 24) {
            PageHeading("New block", detail: model.hasActiveBlocks ? "Existing blocks keep their end times." : nil) {
                if drafting {
                    SecondaryButton(title: "Cancel") {
                        model.composing = false
                        focused = .addBlock
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("What this time is for · optional")
                FormField("Think, make something, or take a break", text: $model.draftPurpose)
                    .focused($focused, equals: .purpose)
                    .accessibilityLabel("What this time is for, optional")
                    .onSubmit(review)
            }

            VStack(alignment: .leading, spacing: 0) {
                distractionRow("Websites", detail: model.chosen.isEmpty ? "None chosen" : model.chosen.sorted().joined(separator: ", "),
                               control: .websites) { model.openComposer() }
                Rule(inset: 0)
                distractionRow("Apps", detail: model.chosenApps.isEmpty ? "None chosen" : model.chosenApps.map(\.name).sorted().joined(separator: ", "),
                               control: .apps) { model.openAppPicker() }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Duration")
                BlockDurationControls(model: model, custom: $customDuration, onSubmit: review)
            }

        }
    }

    /// The draft's one action, pinned under the scroll so it never leaves the
    /// window however long the page grows. The page scrolls beneath it.
    private var draftBar: some View {
        HStack(alignment: .center, spacing: 12) {
            TimelineView(.everyMinute) { _ in
                Text(draftSummary)
                    .font(TypeScale.body)
                    .monospacedDigit()
                    .foregroundStyle(model.hasDraftTargets ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animated(.quick, value: draftSummary)
            }
            Spacer()
            Button(action: review) {
                Text("Review Block").frame(minWidth: 120)
            }
            .buttonStyle(PrimaryStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .focusable().focused($focused, equals: .review)
            .disabled(!model.hasDraftTargets || model.busy)
            .help("Review before blocking   ⌘↩")
        }
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, sideInset)
        .padding(.vertical, compactLayout ? 10 : 14)
        .frame(maxWidth: .infinity)
        .background {
            Glass(cornerRadius: 0, veiled: true)
                .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
                .ignoresSafeArea()
        }
    }

    private var draftSummary: String {
        guard model.hasDraftTargets else { return "Choose at least one website or app" }
        var parts = [model.draftTargetLabel, model.durationLabel]
        if model.minutes.isFinite, (1...525_600).contains(model.minutes) {
            parts.append("ends \(model.currentTime.addingTimeInterval(model.minutes * 60).blockDeadline)")
        }
        return parts.joined(separator: " · ")
    }

    private func distractionRow(_ title: String, detail: String, control: Control, action: @escaping () -> Void) -> some View {
        Button {
            returnFocus = control
            action()
        } label: {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(TypeScale.body.weight(.medium)).foregroundStyle(Palette.ink)
                    Text(detail).font(TypeScale.chrome).foregroundStyle(Palette.muted)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text("Choose…").font(TypeScale.chrome.weight(.medium)).foregroundStyle(Palette.accent)
                Image(systemName: "chevron.right").font(Symbols.small).foregroundStyle(Palette.muted).accessibilityHidden(true)
            }
            .padding(.vertical, 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable().focused($focused, equals: control)
        .accessibilityLabel("Choose \(title.lowercased())").accessibilityValue(detail)
    }

    // MARK: - Daily limits

    private var limitsSummary: some View {
        let limits = model.dailyLimits
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Daily limits")
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(limits.prefix(3).enumerated()), id: \.element.id) { index, limit in
                        if index > 0 { Rule() }
                        let reached = limit.blockedUntil(at: model.currentTime) != nil
                        HStack(spacing: 12) {
                            Text(limit.domain).font(TypeScale.body).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(limit.remainingLabel(at: model.currentTime))
                                .font(TypeScale.chrome)
                                .monospacedDigit()
                                .foregroundStyle(reached ? Palette.danger : Palette.muted)
                        }
                        .padding(.horizontal, Inset.row)
                        .frame(minHeight: 36)
                        .accessibilityElement(children: .combine)
                    }
                    Rule(inset: 0)
                    Button {
                        openHeaderPanel(.dailyLimits, from: .limits)
                    } label: {
                        HStack {
                            Text(model.websiteUsage.authorized
                                 ? (limits.count > 3 ? "All \(limits.count) Limits" : "Edit Limits")
                                 : "Allow Accessibility to Count Time")
                                .font(TypeScale.chrome.weight(.medium))
                                .foregroundStyle(model.websiteUsage.authorized ? Palette.muted : Palette.accent)
                            Spacer()
                            Image(systemName: "chevron.right").font(Symbols.row).foregroundStyle(Palette.faint)
                        }
                        .padding(.horizontal, Inset.row)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(.row))
                    .focusable().focused($focused, equals: .limits)
                }
            }
        }
    }

    private func openHeaderPanel(_ panel: Panel, from control: Control) {
        returnFocus = control
        model.error = nil
        model.panel = panel
    }

    private func review() {
        guard model.serviceReady, model.hasDraftTargets else { return }
        returnFocus = .review
        _ = model.reviewDraft()
    }
}

struct AboutBlocking: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active blocks cannot be shortened or deleted in Steadfast. Closing the app leaves the background service running.")
                .font(TypeScale.chrome)
            Text("System DNS and hosts rules cover browsers using the Mac's resolver. Encrypted DNS, VPN DNS, cached connections, and administrator changes can bypass them.")
                .font(TypeScale.caption).foregroundStyle(Palette.muted)
            Text("Blocked apps close as soon as they start, matched by bundle identifier. An administrator can still stop the background service, or run a re-signed copy under a different identifier.")
                .font(TypeScale.caption).foregroundStyle(Palette.muted)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
