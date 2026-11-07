import SwiftUI
import SteadfastCore

/// The picker's foot: what's selected on the left, the two actions together on the right.
struct WebsiteEditorFoot: View {
    @Bindable var model: Model

    var body: some View {
        HStack(spacing: 8) {
            Text(model.chosen.isEmpty ? "Nothing selected" : "\(model.chosen.count) selected")
                .font(TypeScale.body).monospacedDigit().foregroundStyle(Palette.muted)
            Spacer()
            SecondaryButton(title: "Clear") { model.chosen = []; model.error = nil }
                .disabled(model.chosen.isEmpty)
            Button("Done") { model.dismissPanel() }
                .buttonStyle(PrimaryStyle()).keyboardShortcut(.cancelAction)
        }
    }
}

struct WebsiteEditor: View {
    @Bindable var model: Model
    @FocusState private var searching: Bool
    @State private var expanded = Set<String>()
    private var query: String { model.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var results: [String] {
        Set(Presets.searchableDomains).union(model.chosen)
            .filter { Presets.matches($0, query: query) }.sorted()
    }
    private var domainsToAdd: [String] {
        guard !query.isEmpty else { return [] }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        let parts = query.components(separatedBy: separators).filter { !$0.isEmpty }
        guard let domains = try? Domain.normalized(parts) else { return [] }
        return domains.allSatisfy(model.chosen.contains) ? [] : domains
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
                TextField("Search websites or paste a domain", text: $model.text)
                    .textFieldStyle(.plain).focused($searching).accessibilityLabel("search websites or paste a domain")
                    .onSubmit { if !domainsToAdd.isEmpty { model.addCustomSites() } }
                if !model.text.isEmpty {
                    QuietToolButton(icon: "xmark.circle.fill", help: "Clear search") { model.text = "" }
                }
            }.padding(.horizontal, Inset.row).frame(height: 36)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if query.isEmpty {
                        Titled("Popular") {
                            QuickWebsites(model: model)
                        }

                        let custom = model.chosen.subtracting(Presets.searchableDomains).sorted()
                        if !custom.isEmpty {
                            Titled("Added by you") {
                                Card {
                                    ForEach(Array(custom.enumerated()), id: \.element) { index, domain in
                                        if index > 0 { Rule() }
                                        websiteRow(domain)
                                    }
                                }
                            }
                        }

                        ForEach(Presets.groups) { group in
                            let domains = group.domains.filter { !QuickWebsites.domains.contains($0) }
                            if !domains.isEmpty { category(group.name, domains) }
                        }
                    } else {
                        let matches = results
                        let added = domainsToAdd
                        if !added.isEmpty, added.count > 1 || !matches.contains(added[0]) {
                            Button { model.addCustomSites() } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus").font(Symbols.header).frame(width: 20).foregroundStyle(Palette.accent)
                                        .accessibilityHidden(true)
                                    Text("Add \(added.joined(separator: ", "))").font(TypeScale.body.weight(.medium))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text("↩").font(TypeScale.chrome).foregroundStyle(Palette.faint).accessibilityHidden(true)
                                }
                                .padding(.horizontal, Inset.row)
                                .frame(height: 40)
                                .choice(false, radius: Radius.card)
                            }
                            .buttonStyle(PressStyle(.card))
                            .help("Add to this block   ↩")
                        }
                        if !matches.isEmpty {
                            Card {
                                ForEach(Array(matches.enumerated()), id: \.element) { index, domain in
                                    if index > 0 { Rule() }
                                    websiteRow(domain)
                                }
                            }
                        } else if added.isEmpty {
                            Text("No matching websites").foregroundStyle(Palette.muted).padding(.vertical, 16)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 200, maxHeight: 380)

            if let error = model.error {
                ErrorNote(error)
            }
        }
        .onAppear { searching = true }
        .onChange(of: model.searchRequested) { searching = true }
        .onChange(of: model.text) { model.error = nil }
    }

    private func category(_ name: String, _ domains: [String]) -> some View {
        let open = expanded.contains(name)
        let picked = domains.filter(model.chosen.contains).count
        let available = domains.filter { domain in
            !model.active.contains { $0.domains.contains { Domain.matches(domain, rule: $0) || Domain.matches($0, rule: domain) } }
        }
        let all = !available.isEmpty && available.allSatisfy(model.chosen.contains)
        return Card {
            HStack(spacing: 8) {
                Button {
                    Motion.with(.settle) {
                        if open { expanded.remove(name) } else { expanded.insert(name) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(Symbols.small).foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(name.prefix(1).uppercased() + name.dropFirst()).font(TypeScale.body.weight(.medium))
                        Text(picked == 0 ? "\(domains.count)" : "\(picked) of \(domains.count)")
                            .font(TypeScale.caption).monospacedDigit()
                            .foregroundStyle(picked == 0 ? Palette.muted : Palette.accent)
                        Spacer()
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "expanded" : "collapsed")
                Button(all ? "Remove All" : "Add All") {
                    if all { model.chosen.subtract(available) } else { model.chosen.formUnion(available) }
                    model.error = nil
                }
                .buttonStyle(RowActionStyle())
                .disabled(available.isEmpty)
                .accessibilityLabel("\(all ? "Remove" : "Add") all \(name)")
            }
            .padding(.horizontal, Inset.row)
            if open {
                Rule(inset: 0)
                ForEach(Array(domains.enumerated()), id: \.element) { index, domain in
                    if index > 0 { Rule() }
                    websiteRow(domain)
                }
            }
        }
    }

    private func websiteRow(_ domain: String) -> some View {
        let blocked = model.active.first { item in
            item.domains.contains { Domain.matches(domain, rule: $0) || Domain.matches($0, rule: domain) }
        }
        let selected = model.chosen.contains(domain)
        return Button {
            if blocked != nil && !selected { return }
            if selected { model.chosen.remove(domain) } else { model.chosen.insert(domain) }
            model.error = nil
        } label: {
            HStack(spacing: 10) {
                Text(domain).font(TypeScale.body).foregroundStyle(Palette.ink)
                Spacer()
                if let blocked {
                    Label("Blocked until \(blocked.endsAt.blockTime)", systemImage: "lock")
                        .font(TypeScale.caption).foregroundStyle(Palette.muted)
                } else {
                    PickMark(on: selected)
                }
            }
            .padding(.horizontal, Inset.row)
            .frame(height: Inset.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(domain)
        .accessibilityValue(blocked != nil && !selected ? "already blocked" : selected ? "selected" : "not selected")
        .disabled(blocked != nil && !selected)
    }
}

struct QuickWebsites: View {
    struct Option: Identifiable {
        let name: String
        let symbol: String
        let domains: [String]
        var id: String { name }
    }
    static let options = [
        Option(name: "YouTube", symbol: "play.rectangle", domains: ["youtube.com", "youtu.be"]),
        Option(name: "Instagram", symbol: "camera", domains: ["instagram.com"]),
        Option(name: "X / Twitter", symbol: "bubble", domains: ["x.com", "twitter.com"]),
        Option(name: "Reddit", symbol: "text.bubble", domains: ["reddit.com"]),
        Option(name: "TikTok", symbol: "music.note", domains: ["tiktok.com"]),
        Option(name: "Netflix", symbol: "tv", domains: ["netflix.com"])
    ]
    static let domains = Set(options.flatMap(\.domains))

    @Bindable var model: Model
    var columns = 2

    var body: some View {
        TileGrid(columns: columns) {
            ForEach(Self.options) { option in
                let selected = Set(option.domains).isSubset(of: model.chosen)
                let partial = !selected && option.domains.contains(where: model.chosen.contains)
                let blocked = model.active.contains { item in item.domains.contains { rule in option.domains.contains { !model.chosen.contains($0) && (Domain.matches($0, rule: rule) || Domain.matches(rule, rule: $0)) } } }
                ChoiceTile(option.name, glyph: .symbol(option.symbol),
                           mark: selected ? .on : blocked ? .locked : partial ? .partial : .off,
                           help: option.domains.joined(separator: ", ")) {
                    if selected { model.chosen.subtract(option.domains) }
                    else { model.chosen.formUnion(option.domains) }
                    model.error = nil
                }
            }
        }
    }
}

struct CommitmentFlow: View {
    @Bindable var model: Model
    @State private var confirmedEndDay: Date?
    private var isLongBlock: Bool { model.minutes > 1440 }
    private var endDate: Date { model.currentTime.addingTimeInterval(model.minutes * 60) }
    private func confirmed(_ end: Date) -> Bool {
        confirmedEndDay.map { Calendar.current.isDate($0, inSameDayAs: end) } ?? false
    }

    var body: some View {
        TimelineView(.everyMinute) { _ in review(ending: endDate) }
    }

    private func review(ending end: Date) -> some View {
        Plate(
            model.draftName.map { "Start \($0)?" } ?? "Review Block",
            subtitle: isLongBlock
                ? "Ends \(end.formatted(date: .complete, time: .shortened))"
                : "\(model.reviewedTargetLabel) · ends \(end.blockDeadline)",
            width: Sheet.width,
            close: { model.closeComposer() }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if !model.reviewedDomains.isEmpty {
                Titled("Websites") {
                    Card {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(model.reviewedDomains.enumerated()), id: \.element) { index, domain in
                                    if index > 0 { Rule() }
                                    HStack(spacing: 8) {
                                        Image(systemName: "lock.fill").font(Symbols.row).foregroundStyle(Palette.muted)
                                            .frame(width: 16).accessibilityHidden(true)
                                        Text(domain).font(TypeScale.body).foregroundStyle(Palette.ink).textSelection(.enabled)
                                        Spacer()
                                    }
                                    .padding(.horizontal, Inset.row)
                                    .frame(minHeight: Inset.rowHeight)
                                }
                            }
                        }
                        .frame(height: min(model.reviewedApps.isEmpty ? 168 : 132, CGFloat(model.reviewedDomains.count) * (Inset.rowHeight + 1)))
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
                }

                if !model.reviewedApps.isEmpty {
                    Titled("Apps") {
                        Card {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) { AppList(apps: model.reviewedApps) }
                            }
                            .frame(height: min(model.reviewedDomains.isEmpty ? 172 : 136, CGFloat(model.reviewedApps.count) * (Inset.rowHeight + 1)))
                            .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "hourglass").font(Symbols.row).foregroundStyle(Palette.muted).accessibilityHidden(true)
                    Text(model.reviewedApps.isEmpty
                         ? "Once it starts, this block can't be ended early. It keeps running even if you quit Steadfast."
                         : "Once it starts, this block can't be ended early. Open apps get \(Int(AppRule.gracePeriod)) seconds to save, then close.")
                        .font(TypeScale.chrome)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Inset.row)

                if isLongBlock {
                    Toggle("I've checked the end date", isOn: Binding(
                        get: { confirmed(end) },
                        set: { confirmedEndDay = $0 ? end : nil }
                    ))
                        .toggleStyle(.checkbox).disabled(model.busy)
                }

                if !model.serviceReady { ServiceSetup(model: model) }
                if let error = model.error {
                    ErrorNote(error)
                }
            }
        } foot: {
            HStack(spacing: 8) {
                Spacer()
                SecondaryButton(title: model.canEditReview ? "Cancel" : "Back") { model.closeComposer() }
                    .keyboardShortcut(.cancelAction).disabled(model.busy)
                if model.canEditReview {
                    SecondaryButton(title: "Edit…") { model.editReviewedDraft() }
                        .disabled(model.busy)
                        .help("Change what's blocked or the duration")
                }
                Button {
                    let confirmedLongBlock = confirmed(endDate)
                    guard !isLongBlock || confirmedLongBlock else { return }
                    Task { await model.commit(confirmedLongBlock: confirmedLongBlock) }
                } label: {
                    Text(model.busy ? "Starting…" : "Block for \(model.durationLabel)")
                        .frame(minWidth: 120)
                }
                .buttonStyle(PrimaryStyle()).keyboardShortcut(.return, modifiers: .command)
                .help("Start blocking   ⌘↩")
                .disabled(model.busy || !model.serviceReady || (isLongBlock && !confirmed(end)))
            }
        }
        .onChange(of: model.minutes) { confirmedEndDay = nil }
        .interactiveDismissDisabled(model.busy)
    }
}
