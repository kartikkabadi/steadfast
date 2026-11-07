import SwiftUI
import SteadfastCore

extension Date {
    /// "18:41", "tomorrow at 09:00", "Mon at 09:00" within a week, "9 Nov at 09:00", or with the year when it differs.
    var blockTime: String {
        let calendar = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(self) { return time }
        if calendar.isDateInTomorrow(self) { return "tomorrow at \(time)" }
        let now = Date()
        if self > now, timeIntervalSince(now) < 6 * 86_400 {
            return "\(formatted(.dateTime.weekday(.abbreviated))) at \(time)"
        }
        let sameYear = calendar.component(.year, from: self) == calendar.component(.year, from: now)
        let day = sameYear ? formatted(.dateTime.day().month(.abbreviated)) : formatted(.dateTime.day().month(.abbreviated).year())
        return "\(day) at \(time)"
    }
    /// Reads after a verb: "unlocks at 18:41", "tomorrow at 09:00", "on 9 Nov 2026 at 09:00".
    var blockDeadline: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) || calendar.isDateInTomorrow(self) {
            return calendar.isDateInToday(self) ? "at \(blockTime)" : blockTime
        }
        return "on \(blockTime)"
    }
}

struct BlockingStatus: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(model.statusLabel, systemImage: model.connecting ? "clock" : model.serviceReady ? "checkmark.circle" : "exclamationmark.circle")
                .fontWeight(.semibold)
            if model.serviceReady, let next = (model.websiteUnlocks.map(\.end) + model.appUnlocks.map(\.end)).min() {
                Text("Next unlock \(next.blockDeadline)")
                    .foregroundStyle(Palette.muted)
            } else if !model.serviceReady, let lastChecked = model.snapshot?.now {
                Text("Last checked \(lastChecked.blockDeadline)")
                    .foregroundStyle(Palette.muted)
            }
        }.font(TypeScale.chrome)
    }
}

extension Model {
    var limitTrackingLabel: String {
        guard serviceReady else { return "Waiting for the background service" }
        guard websiteUsage.authorized else { return "Website access is needed to count time" }
        if let status = websiteUsage.status { return status.asSentence }
        switch websiteUsage.activity {
        case .waiting: return "Waiting for a limited website"
        case .unreadable: return "No readable browser page"
        case let .tracking(domain): return "Counting time on \(domain)"
        }
    }
}

extension DailyLimit {
    func remainingLabel(at date: Date) -> String {
        if blockedUntil(at: date) != nil { return "Limit reached · resets at midnight" }
        let remaining = Int(ceil(max(0, Double(minutes * 60) - usage(at: date)) / 60))
        return "\(remaining) min left"
    }
}

struct BlockDurationControls: View {
    @Bindable var model: Model
    @Binding var custom: Bool
    var onSubmit: () -> Void = {}
    @FocusState private var editing: Bool
    @Namespace private var track
    private let presets = [("30 min", 30.0), ("1 hour", 60.0), ("2 hours", 120.0), ("4 hours", 240.0)]
    private var showsFields: Bool { custom || !presets.contains { $0.1 == model.minutes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(presets, id: \.0) { title, minutes in
                    segment(title, selected: !showsFields && model.minutes == minutes) {
                        custom = false
                        model.setDuration(minutes)
                    }
                }
                segment("Custom", selected: showsFields) {
                    custom = true
                    editing = true
                }
            }
            .padding(3)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.row + 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.row + 3, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .accessibilityElement(children: .contain).accessibilityLabel("block duration")
            if showsFields {
                HStack(spacing: 8) {
                    TextField("Duration", text: $model.amountText).formField().frame(width: 80)
                        .accessibilityLabel("custom block duration").focused($editing).onSubmit(onSubmit)
                    Picker("Unit", selection: $model.multiplier) {
                        Text("Minutes").tag(1.0)
                        Text("Hours").tag(60.0)
                        Text("Days").tag(1440.0)
                    }.pickerStyle(.menu).labelsHidden().frame(width: 100)
                }
            }
        }
    }

    /// One stop on the duration track. The picked stop is a raised plate that
    /// slides between stops, the same gesture as the page switcher.
    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Motion.with(.settle, action)
        } label: {
            Text(title)
                .font(TypeScale.chrome.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if selected {
                        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        shape.fill(Palette.accent.opacity(0.16))
                            .overlay(shape.strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1))
                            .matched(id: "duration", in: track)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(.control))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// How long is left, in the fewest words that stay true for the next minute.
enum Remaining {
    static func text(until end: Date, from now: Date) -> String {
        let minutes = max(1, Int(ceil(end.timeIntervalSince(now) / 60)))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        if hours < 24 { return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min" }
        let days = hours / 24, hoursLeft = hours % 24
        let dayText = days == 1 ? "1 day" : "\(days) days"
        return hoursLeft == 0 ? dayText : "\(dayText) \(hoursLeft) h"
    }
}

/// Redraws a countdown the moment its minute changes. `Remaining` rounds up, so
/// the text turns over at whole minutes before `end`, not at clock minutes.
struct CountdownSchedule: TimelineSchedule {
    let end: Date

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let left = end.timeIntervalSince(start)
        var next = left > 0 ? end.addingTimeInterval(-60 * floor(left / 60)) : start.addingTimeInterval(60)
        if next <= start { next += 60 }
        var first = true
        return AnyIterator {
            if first { first = false; return start }
            defer { next += 60 }
            return next
        }
    }
}

extension TimelineSchedule where Self == CountdownSchedule {
    static func countdown(to end: Date) -> CountdownSchedule { CountdownSchedule(end: end) }
}
