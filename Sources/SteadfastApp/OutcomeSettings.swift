import SwiftUI
import SteadfastCore

/// Settings for what Steadfast is protecting time for and how it learns where
/// time goes through its own local activity history.
struct OutcomeSettings: View {
    @Bindable var model: Model
    /// UI checks open the aim editor directly.
    static var startsEditing = false

    var body: some View {
        AimSettings(store: model.outcomes, editing: Self.startsEditing)
        TallySettings(model: model, store: model.outcomes)
        if let error = model.outcomes.saveError {
            ErrorNote(error)
            Button("Try Saving Again") { model.outcomes.save() }.buttonStyle(RowActionStyle())
        }
    }
}

private struct AimSettings: View {
    let store: OutcomeStore
    @State var editing: Bool
    @State private var title = ""
    @State private var kind = AimKind.build
    @State private var cost = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var removing = false
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Titled("What matters to you") {
            Card {
                if editing { editor } else if let aim = store.aim { summary(aim) } else {
                    Line("Make room for something", "A few words to keep in view. This is optional.") {
                        Button("Set…") { begin(nil) }.buttonStyle(RowActionStyle())
                    }
                }
            }
        }
        .onAppear { if editing { begin(store.aim) } }
    }

    @ViewBuilder private func summary(_ aim: Aim) -> some View {
        let detail = ([aim.kind.label] + (aim.deadline.map { ["by " + $0.formatted(.dateTime.day().month(.wide).year())] } ?? []))
            .joined(separator: " · ")
        Line(aim.title, detail) {
            Button("Edit…") { begin(aim) }.buttonStyle(RowActionStyle())
        }
        if let cost = aim.cost, !cost.isEmpty {
            Rule()
            Line("“\(cost)”", "Your private reason for making a change") { EmptyView() }
        }
    }

    @ViewBuilder private var editor: some View {
        Line("Kind") {
            Picker("Kind", selection: $kind) {
                ForEach(AimKind.allCases, id: \.self) { kind in Label(kind.label, systemImage: kind.symbol).tag(kind) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
            .onChange(of: kind) { old, new in
                if trimmedTitle.isEmpty || trimmedTitle == old.suggestedTitle { title = new.suggestedTitle }
            }
        }
        Rule()
        Line("In your words") {
            FormField("Ship my app", text: $title).frame(width: 260).focused($titleFocused)
                .accessibilityLabel("Your aim, in your words")
        }
        Rule()
        Line("Your reason · optional", "What made you want a change?") {
            FormField("A sentence is enough", text: $cost).frame(width: 260)
                .accessibilityLabel("Your private reason for making a change, optional")
        }
        Rule()
        Line("By a date") {
            HStack(spacing: 8) {
                if hasDeadline {
                    DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.field).labelsHidden()
                }
                Toggle("By a date", isOn: $hasDeadline).toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
        }
        Rule()
        HStack(spacing: 8) {
            if store.aim != nil {
                Button("Remove…", role: .destructive) { removing = true }
                    .buttonStyle(RowActionStyle())
                    .confirmationDialog("Remove your aim?", isPresented: $removing, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) { store.aim = nil; editing = false }
                    } message: { Text("Your tally and estimates stay.") }
            }
            Spacer(minLength: 8)
            Button("Cancel") { Motion.with(.settle) { editing = false } }.buttonStyle(RowActionStyle())
            Button("Save") { commit() }.buttonStyle(RowActionStyle()).disabled(trimmedTitle.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, Inset.row).padding(.vertical, 10)
    }

    private func begin(_ aim: Aim?) {
        title = aim?.title ?? AimKind.build.suggestedTitle
        kind = aim?.kind ?? .build
        cost = aim?.cost ?? ""
        hasDeadline = aim?.deadline != nil
        if let date = aim?.deadline { deadline = date }
        Motion.with(.settle) { editing = true }
        titleFocused = true
    }

    private func commit() {
        func clean(_ text: String) -> String? {
            let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            return value.isEmpty ? nil : value
        }
        guard let name = clean(title) else { return }
        store.aim = Aim(title: name, kind: kind, cost: clean(cost), deadline: hasDeadline ? deadline : nil,
                        createdAt: store.aim?.createdAt ?? Date())
        Motion.with(.settle) { editing = false }
    }
}

private struct TallySettings: View {
    @Bindable var model: Model
    @Bindable var store: OutcomeStore

    var body: some View {
        Titled("Activity history") {
            Card {
                ActivityControls(store: store).padding(Inset.row)
                Rule()
                Line("Your activity", "App and website totals, with a recent timeline.") {
                    Button("Open History") {
                        model.panel = nil
                        model.progressActivity = true
                        model.page = .history
                    }.buttonStyle(RowActionStyle())
                }
            }
        }
    }
}
