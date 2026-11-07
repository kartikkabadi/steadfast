import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SteadfastCore

struct AppPicker: View {
    @Bindable var model: Model
    var body: some View {
        Plate("Choose Apps", subtitle: "Blocked apps close and can't be opened until the block ends", width: Sheet.width,
              close: { model.dismissPanel() }) {
            AppEditor(model: model)
        } foot: {
            AppEditorFoot(model: model)
        }
    }
}

struct AppEditorFoot: View {
    @Bindable var model: Model

    var body: some View {
        HStack(spacing: 8) {
            Text(model.chosenApps.isEmpty ? "Nothing selected" : "\(model.chosenApps.count) selected")
                .font(TypeScale.body).monospacedDigit().foregroundStyle(Palette.muted)
            Spacer()
            SecondaryButton(title: "Clear") { model.chosenApps = []; model.error = nil }
                .disabled(model.chosenApps.isEmpty)
            Button("Done") { model.dismissPanel() }
                .buttonStyle(PrimaryStyle()).keyboardShortcut(.cancelAction)
        }
    }
}

struct AppEditor: View {
    @Bindable var model: Model
    @State private var query = ""
    @State private var expanded: Set<AppCategory> = Set(AppCategory.allCases).subtracting([.other])
    @FocusState private var searching: Bool
    private let catalog = AppCatalog.shared
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain).focused($searching).accessibilityLabel("search apps")
                if !query.isEmpty {
                    QuietToolButton(icon: "xmark.circle.fill", help: "Clear search") { query = "" }
                }
            }.padding(.horizontal, Inset.row).frame(height: 36)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !catalog.loaded {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Finding apps on this Mac…").font(TypeScale.chrome).foregroundStyle(Palette.muted)
                        }.padding(.vertical, 16)
                    } else if trimmed.isEmpty {
                        let elsewhere = model.chosenApps.filter { catalog.app(for: $0.bundleID) == nil }
                            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                        if !elsewhere.isEmpty {
                            Titled("Added by you") {
                                Card {
                                    ForEach(Array(elsewhere.enumerated()), id: \.element.id) { index, app in
                                        if index > 0 { Rule() }
                                        AppRow(model: model, app: app, path: nil)
                                    }
                                }
                            }
                        }
                        ForEach(AppCategory.allCases, id: \.self) { category in
                            let apps = catalog.apps.filter { $0.category == category }
                            if !apps.isEmpty { section(category, apps) }
                        }
                        Button { chooseApp() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(Symbols.header).frame(width: 20).foregroundStyle(Palette.muted)
                                Text("Choose Another App…").font(TypeScale.body.weight(.medium))
                                Spacer()
                            }
                            .padding(.horizontal, Inset.row)
                            .frame(height: 40)
                            .choice(false, radius: Radius.card)
                        }
                        .buttonStyle(PressStyle(.card))
                    } else {
                        let matches = catalog.apps.filter {
                            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.bundleID.localizedCaseInsensitiveContains(trimmed)
                        }
                        if matches.isEmpty {
                            Text("No matching apps. Clear the search and use Choose Another App to pick one from a folder.")
                                .foregroundStyle(Palette.muted).padding(.vertical, 16)
                        } else {
                            Card {
                                ForEach(Array(matches.enumerated()), id: \.element.id) { index, app in
                                    if index > 0 { Rule() }
                                    AppRow(model: model, app: app.blocked, path: app.path)
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 200, maxHeight: 360)


            if let error = model.error {
                ErrorNote(error)
            }
        }
        .onAppear {
            catalog.load(); searching = true
            revealChosen()
        }
        .onChange(of: catalog.loaded) { revealChosen() }
        .onChange(of: query) { model.error = nil }
    }

    private func section(_ category: AppCategory, _ apps: [InstalledApp]) -> some View {
        let open = expanded.contains(category)
        let picked = apps.filter { model.chosenApps.contains($0.blocked) }.count
        let available = apps.filter { !model.blockedAppKeys.contains($0.id) }.map(\.blocked)
        let all = !available.isEmpty && available.allSatisfy(model.chosenApps.contains)
        return Card {
            HStack(spacing: 8) {
                Button {
                    Motion.with(.settle) {
                        if open { expanded.remove(category) } else { expanded.insert(category) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(Symbols.small).foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(category.rawValue).font(TypeScale.body.weight(.medium))
                        Text(picked == 0 ? "\(apps.count)" : "\(picked) of \(apps.count)")
                            .font(TypeScale.caption).monospacedDigit()
                            .foregroundStyle(picked == 0 ? Palette.muted : Palette.accent)
                        Spacer()
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "expanded" : "collapsed")
                if category != .other {
                    Button(all ? "Remove All" : "Add All") {
                        if all { model.chosenApps.subtract(available) } else { model.chosenApps.formUnion(available) }
                        model.error = nil
                    }
                    .buttonStyle(RowActionStyle())
                    .disabled(available.isEmpty)
                    .accessibilityLabel("\(all ? "Remove" : "Add") all \(category.rawValue)")
                }
            }
            .padding(.horizontal, Inset.row)
            if open {
                Rule(inset: 0)
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Rule() }
                    AppRow(model: model, app: app.blocked, path: app.path)
                }
            }
        }
    }

    /// Sections holding a picked app start open, and can still be closed.
    private func revealChosen() {
        for app in catalog.apps where model.chosenApps.contains(app.blocked) { expanded.insert(app.category) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose apps to block"
        guard panel.runModal() == .OK else { return }
        var rejected: [String] = []
        for url in panel.urls {
            let real = url.resolvingSymlinksInPath().path
            if AppBundles.isSystemLocation(real) || AppBundles.isSystemLocation("/private" + real) {
                rejected.append("\(url.deletingPathExtension().lastPathComponent) is part of macOS and can't be blocked")
            } else if let app = AppCatalog.describe(url) {
                if model.blockedAppKeys.contains(app.id) { rejected.append("\(app.name) is already blocked") }
                else { model.chosenApps.insert(app.blocked) }
            } else {
                let name = url.deletingPathExtension().lastPathComponent
                rejected.append("\(name) is part of macOS or Steadfast, or has no bundle identifier, so it can't be blocked")
            }
        }
        model.error = rejected.isEmpty ? nil : rejected.joined(separator: ". ")
    }
}

/// One selectable app with its real icon.
struct AppRow: View {
    @Bindable var model: Model
    let app: BlockedApp
    let path: String?

    var body: some View {
        let blocked = model.active.first { $0.apps.contains(app) }
        let selected = model.chosenApps.contains(app)
        return Button {
            if blocked != nil && !selected { return }
            if selected { model.chosenApps.remove(app) } else { model.chosenApps.insert(app) }
            model.error = nil
        } label: {
            HStack(spacing: 10) {
                AppIcon(bundleID: app.bundleID, path: path, size: 20)
                Text(app.name).font(TypeScale.body).foregroundStyle(Palette.ink).lineLimit(1)
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
        .help(app.bundleID)
        .accessibilityLabel(app.name)
        .accessibilityValue(blocked != nil && !selected ? "already blocked" : selected ? "selected" : "not selected")
        .disabled(blocked != nil && !selected)
    }
}

/// Popular installed apps as one-click tiles on the Block page.
struct QuickApps: View {
    @Bindable var model: Model
    var columns = 2
    private let catalog = AppCatalog.shared

    static func shown(in catalog: AppCatalog) -> [InstalledApp] {
        Array(AppPresets.popular.compactMap { catalog.app(for: $0) }.prefix(6))
    }

    var body: some View {
        let apps = Self.shown(in: catalog)
        if !apps.isEmpty {
            TileGrid(columns: columns) {
                ForEach(apps) { app in
                    AppTile(model: model, app: app)
                }
            }
        }
    }
}

/// One installed app as a pickable tile.
struct AppTile: View {
    @Bindable var model: Model
    let app: InstalledApp

    var body: some View {
        let selected = model.chosenApps.contains(app.blocked)
        let blocked = !selected && model.blockedAppKeys.contains(app.id)
        ChoiceTile(app.name, glyph: .app(bundleID: app.bundleID, path: app.path),
                   mark: selected ? .on : blocked ? .locked : .off) {
            if selected { model.chosenApps.remove(app.blocked) } else { model.chosenApps.insert(app.blocked) }
            model.error = nil
        }
    }
}

/// A compact list of apps with icons, for review and summaries.
struct AppList: View {
    let apps: [BlockedApp]

    var body: some View {
        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
            if index > 0 { Rule() }
            HStack(spacing: 10) {
                AppIcon(bundleID: app.bundleID, size: 20)
                Text(app.name).font(TypeScale.body).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, Inset.row)
            .frame(minHeight: Inset.rowHeight)
            .accessibilityElement(children: .combine)
        }
    }
}
