import SwiftUI
import AppKit
import SteadfastCore

struct StatusMenu: View {
    @Bindable var model: Model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var checked = false

    static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            for x in [3.5, 9.5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 2, width: 3.5, height: 12),
                             xRadius: 1.75, yRadius: 1.75).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "steadfast"
        return image
    }()

    /// The UI check renders the menu without a live service.
    static var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                PauseMark().frame(width: 12, height: 14)
                    .foregroundStyle(Palette.accent).accessibilityHidden(true)
                Text("Steadfast").font(TypeScale.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                if checked, model.serviceReady, model.hasActiveBlocks {
                    Text("Blocking")
                        .font(TypeScale.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Palette.accent.opacity(0.14), in: Capsule())
                }
            }

            status

            if checked, !model.serviceReady, !model.connecting {
                HStack(spacing: 8) {
                    Button("Retry") { Task { await model.refresh(showProgress: true) } }
                        .buttonStyle(PrimaryStyle())
                    SecondaryButton(title: "Settings") { showWindow { model.panel = .settings } }
                        .disabled(model.panel != nil)
                }.disabled(model.busy)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let version = model.availableUpdate {
                    actionRow("Update \(version) Available", icon: "arrow.down.circle", enabled: !model.busy && model.panel == nil) {
                        showWindow { model.panel = .settings }
                    }
                    divider
                }
                if let last = model.lastBlock, !model.hasActiveBlocks {
                    actionRow("Repeat Last Block", icon: "arrow.clockwise", detail: DurationLabel.text(last.durationMinutes)) {
                        showWindow { model.reuseBlock(last) }
                    }
                }
                ForEach(model.favorites.prefix(3)) { routine in
                    actionRow(routine.name, icon: "star", detail: DurationLabel.text(routine.minutes)) {
                        showWindow { model.prepareRoutine(routine) }
                    }
                }
                actionRow(model.hasActiveBlocks ? "Add Another Block" : "New Block", icon: "plus") {
                    showWindow { model.startDraft() }
                }
                let shown = Set(model.favorites.prefix(3).map(\.id))
                let others = model.routines.filter { !shown.contains($0.id) }
                if !others.isEmpty {
                    Menu {
                        ForEach(others) { routine in
                            Button(routine.name) { showWindow { model.prepareRoutine(routine) } }
                        }
                    } label: {
                        rowLabel("Start a Routine", icon: "calendar", trailing: "chevron.right")
                    }
                    .menuStyle(.button)
                    .buttonStyle(PressStyle(.control))
                    .menuIndicator(.hidden)
                    .disabled(!readyForAction)
                }
                divider
                actionRow("Open Steadfast", icon: "macwindow", enabled: true) { showWindow {} }
                actionRow("Daily Limits", icon: "hourglass",
                          enabled: !model.busy && model.panel == nil && model.snapshot != nil) {
                    showWindow { model.panel = .dailyLimits }
                }
                divider
                actionRow("Quit Steadfast", icon: "power", detail: "⌘Q", enabled: true) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            // Row plates reach past the column; their icons stay on its edge.
            .padding(.horizontal, -8)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .font(TypeScale.chrome)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent.color)
        .task { if !Self.preview { await model.checkForUpdate() } }
        .task {
            if Self.preview { checked = true; return }
            checked = false
            do {
                let updates = try ServiceEvents.updates(for: model.service)
                await model.refresh()
                checked = !Task.isCancelled
                for await _ in updates { await model.refresh() }
            } catch {
                await model.refresh()
                checked = !Task.isCancelled
            }
        }
        .onDisappear { checked = false }
    }

    /// While blocking: the same countdown the window leads with, small.
    /// Otherwise the service's state and what's next.
    @ViewBuilder private var status: some View {
        if !checked {
            Label("Checking blocking…", systemImage: "clock").foregroundStyle(Palette.muted)
        } else if model.serviceReady, let block = model.holdingBlock,
                  let end = model.active.map(\.endsAt).max() {
            TimelineView(.countdown(to: end)) { context in
                let now = max(context.date, model.currentTime)
                let total = max(1, end.timeIntervalSince(block.createdAt))
                HStack(spacing: 12) {
                    BlockRing(fraction: min(1, max(0, now.timeIntervalSince(block.createdAt) / total)), weight: 4)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Remaining.text(until: end, from: now)) left")
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.4)
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text("Unlocks \(end.blockDeadline)").foregroundStyle(Palette.muted).monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let aim = model.outcomes.aim {
                VStack(alignment: .leading, spacing: 2) {
                    Text(aim.title).lineLimit(1)
                    if model.weekCoverageHours >= 1 / 60 {
                        Text("\(ProtectedTime.short(hours: model.weekCoverageHours)) with blocks active in the past 7 days")
                            .foregroundStyle(Palette.muted).monospacedDigit()
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                BlockingStatus(model: model)
                if model.snapshot != nil, let summary = model.aimSummary {
                    Text(summary).foregroundStyle(Palette.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if model.serviceReady, let next = model.nextRun {
                    Text("Next routine: \(next.name) · \(next.start.blockTime)")
                        .foregroundStyle(Palette.muted).monospacedDigit()
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func rowLabel(_ title: String, icon: String, detail: String? = nil, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(Symbols.row).foregroundStyle(Palette.muted)
                .frame(width: 16).accessibilityHidden(true)
            Text(title).lineLimit(1).help(title)
            Spacer(minLength: 8)
            if let detail { Text(detail).foregroundStyle(Palette.faint).monospacedDigit() }
            if let trailing { Image(systemName: trailing).font(Symbols.small).foregroundStyle(Palette.faint) }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    private func actionRow(_ title: String, icon: String, detail: String? = nil, enabled: Bool? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, icon: icon, detail: detail) }
            .buttonStyle(PressStyle(.control))
            .disabled(!(enabled ?? readyForAction))
    }

    private var readyForAction: Bool {
        checked && model.serviceReady && !model.busy && model.panel == nil
    }

    private func showWindow(_ action: () -> Void) {
        dismiss()
        openWindow(id: "main")
        NSApp.activate()
        action()
    }
}
