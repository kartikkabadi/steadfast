import SwiftUI
import Charts
import AppKit
import SteadfastCore

struct WebsitePicker: View {
    @Bindable var model: Model
    var body: some View {
        Plate("Choose Websites", subtitle: "Blocked websites and their subdomains won't load until the block ends", width: Sheet.width, close: { model.dismissPanel() }) {
            WebsiteEditor(model: model)
        } foot: {
            WebsiteEditorFoot(model: model)
        }
    }
}

struct RoutinesView: View {
    @Bindable var model: Model
    @State private var deleting: Routine?
    let focus: FocusState<RootView.Control?>.Binding
    @Binding var returnFocus: RootView.Control?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading("Routines", detail: model.routines.isEmpty ? nil : summary) {
                if !model.routines.isEmpty { newRoutine }
            }

            if model.connecting && model.snapshot == nil {
                ProgressView().controlSize(.small).accessibilityLabel("Loading routines")
            } else if model.snapshot == nil && !model.connected {
                Text("Connect to blocking to see your routines.").foregroundStyle(Palette.muted)
            } else if model.routines.isEmpty {
                EmptyState(
                    icon: "calendar.badge.clock",
                    title: "No routines yet",
                    detail: "Save websites, apps and a duration to start them again in one click, or on a weekly schedule."
                ) { newRoutine }
            } else {
                if !model.serviceReady {
                    Text("Last known routines").font(TypeScale.chrome).foregroundStyle(Palette.muted)
                }
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(model.routines.enumerated()), id: \.element.id) { index, routine in
                            if index > 0 { Rule() }
                            routineRow(routine)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "routine")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { routine in
            Button("Delete Routine", role: .destructive) {
                deleting = nil
                Task { _ = await model.deleteRoutine(routine) }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { _ in Text("Future starts will stop. Any active block will finish at its original time.") }
    }

    private var summary: String? {
        let scheduled = model.routines.filter { $0.schedule?.enabled == true }.count
        guard scheduled > 0 else { return nil }
        if let next = model.nextRun { return "Next: \(next.name), \(next.start.blockTime)" }
        return "\(scheduled) on a schedule"
    }

    private func routineRow(_ routine: Routine) -> some View {
        let favorite = model.isFavorite(routine)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name).font(TypeScale.title.weight(.semibold)).tracking(-0.2).lineLimit(1)
                    Text("\(Text(DurationLabel.text(routine.minutes)).foregroundStyle(Palette.ink.opacity(0.8)))\(Text("  ·  ").foregroundStyle(Palette.faint))\(Text((routine.domains + routine.apps.map(\.name)).joined(separator: ", ")).foregroundStyle(Palette.muted))")
                        .monospacedDigit()
                        .font(TypeScale.chrome)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help((routine.domains + routine.apps.map(\.name)).joined(separator: "\n"))
                }
                Spacer(minLength: 8)

                QuietToolButton(icon: favorite ? "star.fill" : "star",
                                help: favorite ? "Remove from quick start" : "Add to quick start", on: favorite) {
                    model.toggleFavorite(routine)
                }
                .accessibilityLabel(favorite ? "Remove \(routine.name) from favorites" : "Favorite \(routine.name)")
                .accessibilityAddTraits(favorite ? .isSelected : [])

                Menu {
                    Button("Edit…") {
                        returnFocus = .routineOptions(routine.id)
                        model.editRoutine(routine)
                    }
                    Button("Duplicate…") {
                        returnFocus = .routineOptions(routine.id)
                        model.duplicateRoutine(routine)
                    }
                    if routine.schedule?.enabled == true,
                       let skipped = routine.skippedStart, skipped > model.currentTime {
                        Button("Restore Skipped Run") {
                            Task { await model.setSkippedRun(routine, start: skipped, skip: false) }
                        }
                    } else if let next = routine.nextStart(after: model.currentTime) {
                        Button("Skip Next Run") {
                            Task { await model.setSkippedRun(routine, start: next, skip: true) }
                        }
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { deleting = routine }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Symbols.row)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(Palette.muted.color)
                .fixedSize()
                .help("More")
                .accessibilityLabel("Options for \(routine.name)")
                .focused(focus, equals: .routineOptions(routine.id))
                .disabled(model.busy || !model.serviceReady)

                SecondaryButton(title: "Start") {
                    model.prepareRoutine(routine)
                    if model.panel == .commitment { returnFocus = .routineStart(routine.id) }
                }
                .focusable().focused(focus, equals: .routineStart(routine.id))
                .accessibilityLabel("Start \(routine.name)")
                .disabled(model.busy || !model.serviceReady)
                .padding(.leading, 4)
            }

            if let schedule = routine.schedule {
                HStack(spacing: 6) {
                    Image(systemName: schedule.enabled ? "calendar.badge.clock" : "calendar")
                        .font(Symbols.row)
                        .foregroundStyle(schedule.enabled ? Palette.accent : Palette.faint)
                        .accessibilityHidden(true)
                    Text(scheduleSummary(schedule)).font(TypeScale.chrome.weight(.medium))
                        .foregroundStyle(schedule.enabled ? Palette.ink : Palette.muted)
                    Spacer(minLength: 8)
                    Text(scheduleDetail(routine, schedule)).font(TypeScale.chrome).monospacedDigit().foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    Toggle("Repeat weekly", isOn: Binding(
                        get: { schedule.enabled },
                        set: { enabled in Task { await model.setSchedule(routine, enabled: enabled) } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("Schedule for \(routine.name)")
                    .help(schedule.enabled ? "Turn off the schedule" : "Turn on the schedule")
                    .disabled(model.busy || !model.serviceReady)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
            }
        }
        .padding(.horizontal, Inset.row)
        .padding(.vertical, 14)
    }

    private var newRoutine: some View {
        Button("New Routine") {
            returnFocus = .newRoutine
            model.newRoutine()
        }.buttonStyle(PrimaryStyle()).focusable().focused(focus, equals: .newRoutine)
            .help("New routine   ⇧⌘N")
            .disabled(model.busy || !model.serviceReady)
    }

    private func scheduleDetail(_ routine: Routine, _ schedule: WeeklySchedule) -> String {
        if schedule.enabled, let skipped = routine.skippedStart, skipped > model.currentTime {
            return "Skipping \(skipped.blockTime)"
        }
        if let next = routine.nextStart(after: model.currentTime) { return "Next \(next.blockTime)" }
        return "Off"
    }

    private func scheduleSummary(_ schedule: WeeklySchedule) -> String {
        WeeklySchedule.describe(days: Set(schedule.weekdays), startMinute: schedule.startMinute)
    }
}

extension WeeklySchedule {
    /// "Weekdays at 09:00", "Every day at 07:30", "Mon, Wed at 18:00".
    static func describe(days: Set<Int>, startMinute: Int) -> String {
        let calendar = Calendar.current
        let time = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: Date()) ?? Date()
        let at = time.formatted(date: .omitted, time: .shortened)
        let label: String
        switch days {
        case Set(1...7): label = "Every day"
        case [2, 3, 4, 5, 6]: label = "Weekdays"
        case [1, 7]: label = "Weekends"
        default:
            let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            label = order.filter(days.contains).map { calendar.shortStandaloneWeekdaySymbols[$0 - 1].capitalized }
                .joined(separator: ", ")
        }
        return label.isEmpty ? "No days chosen" : "\(label) at \(at)"
    }
}

/// What a page shows before it has anything: one glyph, one line, one way forward.
struct EmptyState<Action: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder var action: () -> Action

    init(icon: String, title: String, detail: String, @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(title).font(TypeScale.title).accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
            action().padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

struct RoutineEditor: View {
    @Bindable var model: Model
    private let original: Routine?
    @State private var id: UUID
    @State private var draft: Model
    @State private var name: String
    @State private var repeats: Bool
    @State private var customDuration = false
    @State private var weekdays: Set<Int>
    @State private var startTime: Date
    private enum Field: Hashable { case name, websites, apps }
    @FocusState private var focused: Field?

    init(model: Model, routine: Routine?, seed: Routine? = nil) {
        self.model = model; original = routine
        _id = State(initialValue: routine?.id ?? UUID())
        let source = routine ?? seed
        let draft = Model()
        draft.chosen = Set(source?.domains ?? model.chosen.sorted())
        draft.chosenApps = Set(source?.apps ?? Array(model.chosenApps))
        draft.setDuration(source?.minutes ?? (model.minutes.isFinite ? model.minutes : 60))
        _draft = State(initialValue: draft)
        _name = State(initialValue: source?.name ?? "")
        _repeats = State(initialValue: routine?.schedule?.enabled ?? false)
        _weekdays = State(initialValue: Set(routine?.schedule?.weekdays ?? [2, 3, 4, 5, 6]))
        let minute = routine?.schedule?.startMinute ?? 540
        let time = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        _startTime = State(initialValue: time)
    }

    var body: some View {
        Plate(
            original == nil ? "New Routine" : "Edit Routine",
            subtitle: "Start it from Routines, or let it repeat each week",
            width: Sheet.width,
            close: { model.closeComposer() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Titled("Name") {
                        FormField("Morning focus", text: $name)
                            .focused($focused, equals: .name)
                            .accessibilityLabel("routine name")
                    }

                    Titled("Websites") {
                        Button { draft.openComposer() } label: {
                            HStack(spacing: 12) {
                                Text(draft.chosen.isEmpty ? "Choose websites…" : draft.chosen.sorted().joined(separator: ", "))
                                    .font(TypeScale.body)
                                    .foregroundStyle(draft.chosen.isEmpty ? Palette.muted : Palette.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if !draft.chosen.isEmpty { Tag(text: "\(draft.chosen.count)") }
                                Image(systemName: "chevron.right").font(Symbols.row).foregroundStyle(Palette.faint).accessibilityHidden(true)
                            }
                            .padding(.horizontal, Inset.row)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .choice(false, radius: Radius.row)
                        }
                        .buttonStyle(PressStyle(.row))
                        .focusable().focused($focused, equals: .websites)
                        .accessibilityLabel("choose websites").accessibilityValue(draft.chosen.sorted().joined(separator: ", "))
                    }

                    Titled("Apps") {
                        let apps = draft.chosenApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                        Button { draft.openAppPicker() } label: {
                            HStack(spacing: 12) {
                                if !apps.isEmpty {
                                    HStack(spacing: -6) {
                                        ForEach(apps.prefix(3)) { app in AppIcon(bundleID: app.bundleID, size: 18) }
                                    }
                                }
                                Text(apps.isEmpty ? "Choose apps…" : apps.map(\.name).joined(separator: ", "))
                                    .font(TypeScale.body)
                                    .foregroundStyle(apps.isEmpty ? Palette.muted : Palette.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if !apps.isEmpty { Tag(text: "\(apps.count)") }
                                Image(systemName: "chevron.right").font(Symbols.row).foregroundStyle(Palette.faint).accessibilityHidden(true)
                            }
                            .padding(.horizontal, Inset.row)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .choice(false, radius: Radius.row)
                        }
                        .buttonStyle(PressStyle(.row))
                        .focusable().focused($focused, equals: .apps)
                        .accessibilityLabel("choose apps").accessibilityValue(apps.map(\.name).joined(separator: ", "))
                    }

                    Titled("Duration") {
                        BlockDurationControls(model: draft, custom: $customDuration)
                    }

                    Titled("Schedule") {
                        Card {
                            VStack(alignment: .leading, spacing: 0) {
                                Line("Repeat weekly", repeats ? WeeklySchedule.describe(days: weekdays, startMinute: startMinute) : "Starts automatically, even with the window closed") {
                                    Toggle("Repeat weekly", isOn: Binding(get: { repeats }, set: { value in Motion.with(.settle) { repeats = value } }))
                                        .toggleStyle(.switch)
                                        .controlSize(.small)
                                        .labelsHidden()
                                }
                                if repeats {
                                    Rule()
                                    HStack(spacing: 4) {
                                        ForEach(weekdayOrder, id: \.self) { day in
                                            let isPicked = weekdays.contains(day)
                                            Button {
                                                if isPicked { weekdays.remove(day) } else { weekdays.insert(day) }
                                            } label: {
                                                Text(Calendar.current.shortStandaloneWeekdaySymbols[day - 1].capitalized)
                                                    .font(TypeScale.chrome.weight(isPicked ? .semibold : .regular))
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 28)
                                                    .choice(isPicked)
                                            }
                                            .buttonStyle(PressStyle(.control))
                                            .help(Calendar.current.standaloneWeekdaySymbols[day - 1])
                                            .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[day - 1])
                                            .accessibilityValue(isPicked ? "selected" : "not selected")
                                            .accessibilityAddTraits(isPicked ? .isSelected : [])
                                        }
                                    }
                                    .padding(.horizontal, Inset.row)
                                    .padding(.vertical, 10)

                                    Rule()
                                    Line("Start time") {
                                        DatePicker("Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                                            .datePickerStyle(.field)
                                            .labelsHidden()
                                    }
                                }
                            }
                        }
                    }

                    if let error = model.error { ErrorNote(error) }
                    if !model.serviceReady { ServiceSetup(model: model) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 440)
        } foot: {
            HStack(spacing: 8) {
                Spacer()
                SecondaryButton(title: "Cancel") { model.closeComposer() }.keyboardShortcut(.cancelAction)
                Button(model.busy ? "Saving…" : "Save Routine") { Task { await save() } }
                    .buttonStyle(PrimaryStyle()).keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.busy || !model.serviceReady)
            }
        }
        .disabled(model.busy).interactiveDismissDisabled(model.busy)
        .onAppear { focused = .name }
        .onChange(of: name) { model.error = nil }
        .onChange(of: draft.amountText) { model.error = nil }
        .onChange(of: draft.multiplier) { model.error = nil }
        .onChange(of: draft.chosen) { model.error = nil }
        .onChange(of: draft.chosenApps) { model.error = nil }
        .onChange(of: repeats) { model.error = nil }
        .onChange(of: weekdays) { model.error = nil }
        .onChange(of: startTime) { model.error = nil }
        .sheet(isPresented: Binding(get: { draft.panel == .websites }, set: { if !$0 { draft.dismissPanel() } }),
               onDismiss: { focused = .websites }) {
            WebsitePicker(model: draft)
        }
        .sheet(isPresented: Binding(get: { draft.panel == .apps }, set: { if !$0 { draft.dismissPanel() } }),
               onDismiss: { focused = .apps }) {
            AppPicker(model: draft)
        }
    }

    private var startMinute: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
    private var weekdayOrder: [Int] { (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 } }
    private func save() async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let recurrence = repeats || original?.schedule != nil
            ? WeeklySchedule(weekdays: weekdays.sorted(), startMinute: (components.hour ?? 0) * 60 + (components.minute ?? 0), enabled: repeats) : nil
        let routine = Routine(id: id, name: name, domains: draft.chosen.sorted(),
                              apps: draft.chosenApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                              minutes: draft.minutes, schedule: recurrence)
        if await model.saveRoutine(routine) { model.closeComposer() }
    }
}

struct HistoryView: View {
    @Bindable var model: Model
    let focus: FocusState<RootView.Control?>.Binding
    @Binding var returnFocus: RootView.Control?
    var compact = false
    var narrow = false
    @AppStorage("historyChartExpanded") private var showChart = false
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Progress view", selection: $model.progressActivity) {
                Text("Blocks").tag(false)
                Text("Activity").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
            if model.progressActivity { ActivityView(model: model, store: model.outcomes) }
            else { blocksBody }
        }
    }

    private var blocksBody: some View {
        VStack(alignment: .leading, spacing: compact ? 24 : 32) {
            let facts = model.progressFacts
            PageHeading("Progress", detail: progressDetail(facts)) {
                if model.outcomes.aim == nil {
                    SecondaryButton(title: "Set an Aim…") { model.error = nil; model.panel = .settings }
                        .disabled(model.busy || model.panel != nil)
                        .help("Say what you're protecting time for")
                } else if !facts.hasAny {
                    SecondaryButton(title: "New Block") { model.startDraft() }
                        .disabled(model.busy || !model.serviceReady)
                        .help("New block   ⌘N")
                }
            }

            if model.connecting && model.snapshot == nil {
                ProgressView().controlSize(.small).accessibilityLabel("Loading progress")
            } else if model.snapshot == nil && !model.connected {
                Text("Connect to blocking to see your progress.").foregroundStyle(Palette.muted)
            } else {
                YearRing(facts: facts, aim: model.outcomes.aim, diameter: compact || narrow ? 340 : 384)
                    .frame(maxWidth: .infinity)
                Text("Recorded block coverage, including overnight. Overlaps count once. This is not a measure of focus or time saved.")
                    .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                sessions
            }
        }
    }

    private func progressDetail(_ facts: ProgressFacts) -> String {
        guard facts.hasAny else { return "A record of the boundaries you chose." }
        return "\(ProtectedTime.short(hours: facts.weekHours)) with blocks active in the past 7 days"
    }

    @ViewBuilder private var sessions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionLabel("Past blocks")
                if let weekSummary {
                    Text(weekSummary).font(TypeScale.chrome).monospacedDigit().foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !model.history.isEmpty {
                    Button(showChart ? "Hide Chart" : "Last 7 Days") {
                        Motion.with(.settle) { showChart.toggle() }
                    }
                    .buttonStyle(RowActionStyle())
                    .accessibilityLabel(showChart ? "Hide last 7 days chart" : "Show last 7 days chart")
                }
            }

            if model.history.isEmpty {
                Text("Finished blocks are listed here, ready to use again. Up to 200 completed blocks stay on this Mac.")
                    .font(TypeScale.chrome)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !model.serviceReady {
                    Text("Last known history").font(TypeScale.chrome).foregroundStyle(Palette.muted)
                }

                if showChart {
                    Card {
                        HistoryChart(sessions: model.history.filter { !model.isBrowserCheck($0) }, now: model.currentTime).padding(16)
                    }
                    .transitioned(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayTitle(group.day))
                            .font(TypeScale.chrome.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                            .padding(.leading, Inset.row)
                            .accessibilityAddTraits(.isHeader)
                        Card {
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Rule() }
                                    historyRow(item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var groups: [(day: Date, items: [Commitment])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.history) { calendar.startOfDay(for: $0.endsAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private var weekSummary: String? {
        let since = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: model.currentTime)) ?? .distantPast
        let week = model.history.filter { $0.endsAt >= since && !model.isBrowserCheck($0) }
        guard !week.isEmpty else { return nil }
        return "\(week.count) \(week.count == 1 ? "block" : "blocks") in the past 7 days"
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func historyRow(_ item: Commitment) -> some View {
        let open = expanded == item.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    Motion.with(.settle) { expanded = open ? nil : item.id }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(Symbols.small)
                            .foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .frame(width: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName).font(TypeScale.title.weight(.semibold)).tracking(-0.2)
                                .foregroundStyle(Palette.ink).lineLimit(1)
                            // Same shape as a routine row: duration first, then the rest.
                            Text("\(Text(DurationLabel.text(item.durationMinutes)).foregroundStyle(Palette.ink.opacity(0.8)))\(Text("  ·  ").foregroundStyle(Palette.faint))\(Text("\(item.createdAt.formatted(date: .omitted, time: .shortened))–\(item.endsAt.formatted(date: .omitted, time: .shortened)) · \(item.targetLabel)").foregroundStyle(Palette.muted))")
                                .font(TypeScale.chrome)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.displayName)
                .accessibilityValue(open ? "expanded" : "collapsed")
                .accessibilityHint("Shows what was blocked and when")

                if !model.isBrowserCheck(item) {
                    SecondaryButton(title: "Use Again") {
                        model.reuseBlock(item)
                        if model.panel == .commitment { returnFocus = .repeatBlock(item.id) }
                    }
                    .focusable().focused(focus, equals: .repeatBlock(item.id))
                    .accessibilityLabel("Use again: \(item.displayName)")
                    .disabled(model.busy || !model.serviceReady)
                    .padding(.leading, 4)
                }
            }

            if open {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.targetList)
                        .font(TypeScale.chrome)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Started \(item.createdAt.blockDeadline) · ended \(item.endsAt.blockDeadline)")
                        .font(TypeScale.caption).foregroundStyle(Palette.muted)
                    if let reflection = model.outcomes.reflections.first(where: { $0.id == item.id }), reflection.answer != .skipped {
                        Text(reflection.answer == .helped ? "You said this helped." : "You said this didn't help.")
                            .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                        if let note = reflection.note {
                            Text(note).font(TypeScale.body).textSelection(.enabled)
                        }
                    }
                    if !model.isBrowserCheck(item) {
                        Button("Save as Routine…") {
                            returnFocus = .saveAsRoutine(item.id)
                            model.saveAsRoutine(item)
                        }
                        .buttonStyle(RowActionStyle())
                        .focusable().focused(focus, equals: .saveAsRoutine(item.id))
                        .disabled(model.busy || !model.serviceReady)
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
                .padding(.leading, 20)
                .transitioned(.opacity)
            }
        }
        .padding(.horizontal, Inset.row)
        .padding(.vertical, 14)
    }
}

private struct HistoryChart: View {
    let sessions: [Commitment]
    let now: Date

    var body: some View {
        let days = dailyCounts
        Chart(days) { day in
            BarMark(x: .value("Day", day.label), y: .value("Completed Blocks", day.count))
                .foregroundStyle(Palette.accent.color)
                .cornerRadius(4)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue("\(day.count) completed blocks")
        }
        .chartXScale(domain: days.map(\.label))
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine(); AxisValueLabel() } }
        .frame(height: 110)
        .accessibilityLabel("completed blocks by day")
    }

    private struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let count: Int
        var label: String { date.formatted(.dateTime.weekday(.abbreviated)) }
    }

    private var dailyCounts: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let counts = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.endsAt) }
        return (-6...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map {
                Day(date: $0, count: counts[$0]?.count ?? 0)
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var model: Model
    @State private var uninstalling = false
    @State private var installingUpdate = false
    @State private var choosingSync = false

    private var uninstallDetail: String {
        if !model.active.isEmpty || model.routines.contains(where: { $0.schedule?.enabled == true }) {
            return "Available once blocks finish and schedules are off"
        }
        if model.hasExhaustedLimit { return "Available at midnight, or after removing used-up limits" }
        return "Removes the app, service and its DNS rules"
    }

    var body: some View {
        Plate("Settings", width: Sheet.width, close: { model.closeComposer() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OutcomeSettings(model: model)
                    Titled("Blocking") {
                        Card {
                            VStack(spacing: 0) {
                                Line("Background service", model.connecting ? "Checking…" : model.serviceReady ? (model.snapshot?.sandbox == true ? "Preview · system DNS unchanged" : "Running") : "Not connected") {
                                    let statusTone = model.connecting ? Palette.muted : model.serviceReady ? Palette.accent : Palette.danger
                                    HStack(spacing: 6) {
                                        Image(systemName: model.connecting ? "clock" : model.serviceReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        Text(model.connecting ? "Checking" : model.serviceReady ? "Healthy" : "Offline")
                                            .font(TypeScale.chrome.weight(.medium))
                                    }
                                    .foregroundStyle(statusTone)
                                }

                                if model.serviceReady {
                                    Rule()
                                    Line("Connection") {
                                        Button(model.connecting ? "Checking…" : "Check Now") {
                                            Task { await model.refresh(showProgress: true) }
                                        }
                                        .buttonStyle(RowActionStyle())
                                        .disabled(model.busy || model.connecting)
                                    }

                                    Rule()
                                    Line("Browser test", "One-minute block on example.com") {
                                        Button("Test…") { model.panel = .browserCheck }
                                            .buttonStyle(RowActionStyle())
                                            .disabled(model.busy || model.snapshot?.sandbox != false)
                                    }
                                } else {
                                    Rule()
                                    Line(model.needsBlockingSetup ? "Set up blocking" : "Reconnect", model.needsBlockingSetup ? "Needs administrator approval" : nil) {
                                        Button(model.needsBlockingSetup ? "Set Up…" : "Retry") {
                                            if model.needsBlockingSetup { model.panel = .onboarding }
                                            else { Task { await model.refresh(showProgress: true) } }
                                        }
                                        .buttonStyle(RowActionStyle())
                                    }
                                }

                                Rule()
                                DisclosureGroup("What blocking covers") {
                                    AboutBlocking().padding(.top, 6).padding(.bottom, 2)
                                }
                                .font(TypeScale.chrome)
                                .padding(.horizontal, Inset.row)
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    Titled("Daily limits") {
                        Card {
                            Line("Time per website", model.dailyLimits.isEmpty ? "None set" : "\(model.dailyLimits.count) \(model.dailyLimits.count == 1 ? "limit" : "limits") · reset at midnight") {
                                Button(model.dailyLimits.isEmpty ? "Add…" : "Edit…") { model.panel = .dailyLimits }
                                    .buttonStyle(RowActionStyle())
                                    .disabled(model.snapshot == nil)
                            }
                        }
                    }

                    Titled("Routine sync") {
                        Card {
                            VStack(spacing: 0) {
                                Line("Shared folder", model.routineSync.status?.asSentence ?? model.routineSync.folder?.path ?? "Off") {
                                    if model.routineSync.folder == nil {
                                        Button("Choose Folder…") { choosingSync = true }
                                            .buttonStyle(RowActionStyle())
                                            .disabled(!model.serviceReady)
                                            .confirmationDialog("Sync routines with a shared folder?", isPresented: $choosingSync, titleVisibility: .visible) {
                                                Button("Choose Folder…") { Task { await model.routineSync.chooseFolder(for: model) } }
                                            } message: { Text("Use the same private folder on each Mac. Routine names, websites and durations are stored there.") }
                                    } else {
                                        VStack(alignment: .trailing, spacing: 6) {
                                            Button(model.routineSync.busy ? "Syncing…" : "Sync Now") {
                                                Task { await model.routineSync.sync(for: model) }
                                            }
                                            .buttonStyle(RowActionStyle())
                                            .disabled(model.routineSync.busy || !model.serviceReady)

                                            Button("Disconnect") { model.routineSync.stop() }
                                                .buttonStyle(RowActionStyle())
                                                .disabled(model.routineSync.busy)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Titled("About") {
                        Card {
                            VStack(spacing: 0) {
                                Line("Version", "Steadfast \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")") {
                                    if let update = model.availableUpdate {
                                        Button("Install \(update)…") { installingUpdate = true }
                                            .buttonStyle(RowActionStyle())
                                            .confirmationDialog("Install the Steadfast update?", isPresented: $installingUpdate, titleVisibility: .visible) {
                                                Button("Open Installer") { model.install() }
                                            } message: { Text("Steadfast will quit and open the installer in Terminal. Administrator approval is required.") }
                                    } else if Bundle.main.bundleURL.path == "/Applications/Steadfast.app" {
                                        Button(model.checkingForUpdate ? "Checking…" : "Check for Updates") {
                                            Task { await model.checkForUpdate(manual: true) }
                                        }
                                        .buttonStyle(RowActionStyle())
                                        .disabled(model.checkingForUpdate)
                                    } else {
                                        Text("Development build").font(TypeScale.caption).foregroundStyle(Palette.muted)
                                    }
                                }

                                Rule()
                                Line("Setup") {
                                    Button("Show…") { model.panel = .onboarding }
                                        .buttonStyle(RowActionStyle())
                                }

                                Rule()
                                Line("Uninstall", uninstallDetail) {
                                    Button("Uninstall…", role: .destructive) { uninstalling = true }
                                        .buttonStyle(RowActionStyle())
                                        .disabled(!model.serviceReady || !model.active.isEmpty || model.hasExhaustedLimit || model.routines.contains { $0.schedule?.enabled == true })
                                        .confirmationDialog("Uninstall Steadfast?", isPresented: $uninstalling, titleVisibility: .visible) {
                                            Button("Uninstall", role: .destructive) { model.uninstall() }
                                        } message: { Text("This removes Steadfast, saved routines, and session history. Administrator approval is required.") }
                                }
                            }
                        }
                    }

                    if let status = model.updateStatus {
                        Text(status.asSentence).font(TypeScale.caption).foregroundStyle(Palette.muted).padding(.leading, Inset.row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)
        } foot: {
            HStack {
                Spacer()
                Button("Done") { model.closeComposer() }
                    .buttonStyle(PrimaryStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
