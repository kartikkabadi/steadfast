import SwiftUI
import SteadfastCore

struct DailyLimitsView: View {
    @Bindable var model: Model
    @State private var website = ""
    @State private var minutes = "30"
    @State private var editing: String?
    @State private var removing: DailyLimit?
    @FocusState private var editingWebsite: Bool
    @FocusState private var editingMinutes: Bool

    private var duration: Int? { Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var inputReady: Bool {
        !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (duration.map { (1...1440).contains($0) } ?? false)
    }

    var body: some View {
        Plate(
            "Daily Limits",
            subtitle: "Block a website for the rest of the day once its time is used",
            width: Sheet.width,
            close: { model.closeComposer() }
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !model.websiteUsage.authorized {
                            Card {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(Symbols.header)
                                        .foregroundStyle(Palette.muted)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Allow Accessibility access")
                                            .font(TypeScale.body.weight(.semibold))
                                            .foregroundStyle(Palette.ink)
                                        Text("Steadfast reads the domain of the page in front to count time. Page addresses and history aren't saved.")
                                            .font(TypeScale.caption)
                                            .foregroundStyle(Palette.muted)
                                        Button("Allow Access…") {
                                            model.websiteUsage.requestAccess()
                                        }
                                        .buttonStyle(RowActionStyle())
                                        .padding(.top, 2)
                                    }
                                }
                                .padding(12)
                            }
                        } else if !model.dailyLimits.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                    .font(Symbols.small)
                                    .foregroundStyle(Palette.muted)
                                Text(model.limitTrackingLabel)
                                    .font(TypeScale.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.leading, 4)
                        }

                        Titled(editing == nil ? "Add a limit" : "Edit limit") {
                            Card {
                                HStack(alignment: .center, spacing: 10) {
                                    FormField("reddit.com", text: $website)
                                        .focused($editingWebsite)
                                        .accessibilityLabel("website")
                                        .disabled(editing != nil)

                                    // The same field as the website's, with its unit inside on the right.
                                    TextField("Minutes", text: $minutes, prompt: Text("30").foregroundStyle(Palette.faint))
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                        .padding(.trailing, 26)
                                        .formField()
                                        .overlay(alignment: .trailing) {
                                            Text("min")
                                                .font(TypeScale.chrome)
                                                .foregroundStyle(Palette.muted)
                                                .padding(.trailing, Inset.row)
                                                .allowsHitTesting(false)
                                        }
                                        .frame(width: 96)
                                        .focused($editingMinutes)
                                        .accessibilityLabel("minutes per day")

                                    if editing != nil {
                                        SecondaryButton(title: "Cancel") { reset() }
                                    }
                                    Button(editing == nil ? "Add" : "Save") {
                                        Task { await save() }
                                    }
                                    .buttonStyle(PrimaryStyle())
                                    .disabled(!inputReady || !model.serviceReady || model.busy)
                                }
                                .padding(10)
                                .id("limit-form")
                                .onSubmit {
                                    if inputReady && model.serviceReady && !model.busy { Task { await save() } }
                                }
                            }
                        }

                        if let message = model.error { ErrorNote(message) }

                        Titled("Limits") {
                            if model.dailyLimits.isEmpty {
                                Card {
                                    Text("No limits yet")
                                        .font(TypeScale.chrome)
                                        .foregroundStyle(Palette.muted)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 24)
                                }
                            } else {
                                Card {
                                    VStack(spacing: 0) {
                                        ForEach(Array(model.dailyLimits.enumerated()), id: \.element.id) { index, limit in
                                            if index > 0 { Rule() }
                                            limitRow(limit)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 380)
                .onChange(of: editing) { _, domain in
                    if domain != nil { proxy.scrollTo("limit-form", anchor: .top) }
                }
            }
        } foot: {
            HStack(spacing: 8) {
                Spacer()
                Button("Done") { model.closeComposer() }
                    .buttonStyle(PrimaryStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .disabled(model.busy)
        }
        .interactiveDismissDisabled(model.busy)
        .confirmationDialog("Remove this daily limit?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { limit in
            Button("Remove Limit", role: .destructive) {
                Task { if await model.changeDailyLimit(limit, deleting: true), editing == limit.domain { reset() } }
            }
        } message: { limit in
            Text(limit.blockedUntil(at: model.currentTime) != nil
                 ? "\(limit.domain) unblocks right away, and today’s time total is cleared."
                 : "This clears today’s time total for \(limit.domain).")
        }
    }

    private func limitRow(_ limit: DailyLimit) -> some View {
        let now = model.currentTime
        let blocked = limit.blockedUntil(at: now) != nil
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(limit.domain).font(TypeScale.body.weight(.medium)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                    if blocked {
                        Tag(text: "Limit reached", tone: Palette.danger)
                    }
                }
                Text(blocked ? "Unblocks at midnight" : limit.usage(at: now) < 60
                     ? "\(limit.minutes) min a day"
                     : "\(limit.remainingLabel(at: now)) today · \(limit.minutes) min a day")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Menu {
                Button("Edit Limit") {
                    editing = limit.domain; website = limit.domain; minutes = String(limit.minutes)
                    editingMinutes = true
                }
                Divider()
                Button("Remove Limit…", role: .destructive) { removing = limit }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Symbols.row)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Palette.muted)
                    .contentShape(Rectangle())
                    .accessibilityLabel("actions for \(limit.domain)")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Palette.muted.color)
            .fixedSize()
            .disabled(model.busy || !model.serviceReady)
        }
        .padding(.horizontal, Inset.row)
        .padding(.vertical, 10)
    }

    private func save() async {
        guard let duration else { return }
        let target = (try? Domain.normalized([website]).first) ?? website.trimmingCharacters(in: .whitespacesAndNewlines)
        if await model.changeDailyLimit(DailyLimit(domain: target, minutes: duration)) { reset() }
    }

    private func reset() {
        editing = nil; website = ""; minutes = "30"; model.error = nil; editingWebsite = true
    }
}
