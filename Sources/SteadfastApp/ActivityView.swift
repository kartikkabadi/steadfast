import SwiftUI
import SteadfastCore

enum ActivityTime {
    static func short(_ seconds: Double) -> String {
        seconds > 0 && seconds < 60 ? "<1 min" : ProtectedTime.short(hours: seconds / 3600)
    }
}

struct ActivityControls: View {
    @Bindable var store: OutcomeStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $store.activityEnabled) {
                Text("Save activity on this Mac")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                .toggleStyle(.switch).controlSize(.small)
            Text("App and website time only. Nothing is uploaded.")
                .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if store.trackingEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    if store.websiteAccessGranted {
                        Label("Website access allowed", systemImage: "checkmark")
                            .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                    } else {
                        SecondaryButton(title: "Allow Website Access") { store.requestWebsiteAccess() }
                    }
                    Text("Website activity includes private tabs.")
                        .font(TypeScale.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { store.refreshWebsiteAccess() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshWebsiteAccess() } }
    }
}

struct ActivityView: View {
    let model: Model
    @Bindable var store: OutcomeStore
    @State private var day = Date()
    @State private var websites = false
    @State private var search = ""
    @State private var deleting = false

    private var key: String { Ledger.dayKey(day) }
    private var totals: [UsageTotal] { UsageSummary.totals(store.days.filter { $0.day == key }, since: key) }
    private var selectedTotals: [UsageTotal] {
        totals.filter { $0.isApp != websites && matches(store.name(for: $0)) }
    }
    private var timeline: [ActivitySession] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return store.sessions.compactMap { session in
            guard session.startedAt < interval.end, session.endedAt > interval.start,
                  matches(session.appName + " " + (session.domain ?? "")) else { return nil }
            var clipped = session
            clipped.startedAt = max(session.startedAt, interval.start)
            clipped.endedAt = min(session.endedAt, interval.end)
            return clipped
        }
    }
    private var total: Double { totals.filter(\.isApp).reduce(0) { $0 + $1.seconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading("Where your time goes", detail: "A local record of active app and website time.")
            if store.days.isEmpty && store.sessions.isEmpty {
                ActivityControls(store: store)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(store.trackingEnabled ? liveStatus : "History is paused.")
                        .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(store.trackingEnabled ? "Pause" : "Resume") { store.activityEnabled.toggle() }
                        .buttonStyle(RowActionStyle())
                }
                DisclosureGroup("Activity settings") {
                    ActivityControls(store: store).padding(.top, 12)
                }.font(TypeScale.chrome)
            }
            Rule(inset: 0)
            HStack {
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.field).fixedSize()
                Spacer()
                Text(ActivityTime.short(total))
                    .font(TypeScale.title.weight(.medium)).monospacedDigit()
                    .accessibilityLabel("\(ActivityTime.short(total)) of active computer time")
            }
            FormField("Find an app or website", text: $search).accessibilityLabel("Find recorded activity")
            Picker("Activity kind", selection: $websites) {
                Text("Apps").tag(false)
                Text("Websites").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
            VStack(alignment: .leading, spacing: 0) {
                if selectedTotals.isEmpty {
                    Text(emptyMessage).font(TypeScale.body).foregroundStyle(Palette.muted)
                        .padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(selectedTotals) { item in
                    HStack(spacing: 12) {
                        Group {
                            if item.isApp { AppIcon(bundleID: item.key, size: 24) }
                            else { Image(systemName: "globe").foregroundStyle(Palette.muted) }
                        }.frame(width: 24).accessibilityHidden(true)
                        Text(store.name(for: item)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(ActivityTime.short(item.seconds)).monospacedDigit().foregroundStyle(Palette.muted)
                        Button("Block…") { addToDraft(item) }.buttonStyle(RowActionStyle())
                            .accessibilityLabel("Choose a block for \(store.name(for: item))")
                            .disabled(model.busy || !model.serviceReady)
                    }.padding(.vertical, 12)
                    Rule(inset: 0)
                }
            }
            if !timeline.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel("Recent activity")
                    ForEach(Array(timeline.suffix(200).reversed())) { session in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(session.startedAt.formatted(.dateTime.hour().minute()))
                                .monospacedDigit().foregroundStyle(Palette.muted).frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.domain ?? session.appName).lineLimit(1).truncationMode(.middle)
                                if session.domain != nil { Text(session.appName).font(TypeScale.caption).foregroundStyle(Palette.muted) }
                            }
                            Spacer()
                            Text(ActivityTime.short(session.seconds)).monospacedDigit().foregroundStyle(Palette.muted)
                        }.font(TypeScale.chrome)
                    }
                }
            }
            Text("Time is sampled while this app is running and the Mac is in use. Website time is part of browser time, not extra time. Daily totals stay for 400 days; recent activity stays for 30 days, up to 20,000 entries.")
                .font(TypeScale.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if !store.days.isEmpty || !store.sessions.isEmpty {
                Button("Delete Activity History…", role: .destructive) { deleting = true }
                    .buttonStyle(RowActionStyle())
                    .confirmationDialog("Delete all activity history?", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Delete Activity History", role: .destructive) { store.eraseTally() }
                    } message: { Text("Your aim, blocks, and routines stay. This can't be undone.") }
            }
            if let error = store.saveError { ErrorNote(error) }
        }
    }

    private var liveStatus: String {
        if store.websiteTrackingEnabled && !store.websiteAccessGranted { return "App time is saved. Allow access to include websites." }
        if store.websiteUnreadable { return "App time is recorded. This browser has not shared a website domain." }
        if let domain = store.currentDomain { return "Now: \(domain)" }
        if let app = store.currentApp { return "Now: \(app)" }
        return "Ready. Activity appears as you use other apps."
    }

    private var emptyMessage: String {
        if !search.isEmpty { return "No matching activity on this day." }
        if websites && !store.trackingEnabled { return "Resume activity to see time by website." }
        if websites && !store.websiteAccessGranted { return "Website history starts after you allow access." }
        return store.trackingEnabled ? "No recorded \(websites ? "websites" : "apps") on this day yet." : "History is paused."
    }

    private func matches(_ value: String) -> Bool {
        search.isEmpty || value.localizedCaseInsensitiveContains(search)
    }

    private func addToDraft(_ item: UsageTotal) {
        model.startDraft()
        if item.isApp { model.chosenApps.insert(BlockedApp(bundleID: item.key, name: store.name(for: item))) }
        else { model.chosen.insert(item.key) }
    }
}
