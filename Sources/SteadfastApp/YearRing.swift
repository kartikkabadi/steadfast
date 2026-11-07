import SwiftUI
import SteadfastCore

/// The year as a ring of days, January at twelve o'clock, running clockwise.
/// Each past day is a tick whose length and colour show the hours with blocks that
/// day; the days still ahead are an open dashed track. Today is a dark mark, the
/// aim's deadline a small dot outside the ring. Hover or click a day, or move with
/// the arrow keys, and the centre shows that day instead of the year.
struct YearRing: View {
    let facts: ProgressFacts
    var aim: Aim?
    var diameter: CGFloat = 380

    @State private var hovered: Int?
    @State private var selection: Int?
    @State private var shown = false
    @FocusState private var focused: Bool
    @Environment(\.restrainedMotion) private var still

    init(facts: ProgressFacts, aim: Aim? = nil, diameter: CGFloat = 380, selection: Int? = nil) {
        self.facts = facts; self.aim = aim; self.diameter = diameter
        _selection = State(initialValue: selection)
    }

    private var count: Int { facts.year.count }
    private var inner: CGFloat { diameter * 0.335 }
    private var outer: CGFloat { diameter * 0.43 }
    /// The day the centre describes, if any.
    private var detail: Int? { hovered ?? selection }
    /// Where the accent marker sits: the inspected day, or today once the ring has focus.
    private var marker: Int? { detail ?? (focused ? facts.today : nil) }

    var body: some View {
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(in: &context, size: size)
            }
            centre
                .frame(width: inner * 1.7)
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || still ? 1 : 0.985)
        .onAppear {
            if still { shown = true } else { withAnimation(.easeOut(duration: 0.45)) { shown = true } }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(point): hovered = day(at: point)
            case .ended: hovered = nil
            }
        }
        .onTapGesture(coordinateSpace: .local) { point in
            let day = day(at: point)
            selection = day == selection ? nil : day
            focused = true
        }
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end, .escape]) { press in
            switch press.key {
            case .escape:
                guard selection != nil else { return .ignored }
                selection = nil
            case .home: selection = 0
            case .end: selection = count - 1
            default: move(press.key == .rightArrow ? 1 : -1)
            }
            hovered = nil
            return .handled
        }
        .onChange(of: focused) { _, now in if !now { selection = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Year of block coverage")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Adjust to move between days.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(1)
            case .decrement: move(-1)
            @unknown default: break
            }
        }
        .help("Arrow keys move between days")
    }

    private func move(_ step: Int) {
        selection = min(count - 1, max(0, (selection ?? facts.today) + step))
    }

    private func day(at point: CGPoint) -> Int? {
        RingGeometry.day(dx: point.x - diameter / 2, dy: point.y - diameter / 2, count: count,
                         band: Double(inner - 10)...Double(outer + 14))
    }

    // MARK: - Centre

    @ViewBuilder private var centre: some View {
        if let day = detail {
            dayDetail(day)
        } else {
            let empty = !facts.hasAny

            VStack(spacing: 2) {
                Text(facts.coveredDays.formatted())
                    .font(.system(size: diameter * 0.118, weight: .semibold))
                    .tracking(-1.4)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text(empty ? "days with blocks" : facts.coveredDays == 1 ? "day with blocks this year" : "days with blocks this year")
                    .font(TypeScale.chrome)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private func dayDetail(_ day: Int) -> some View {
        let date = facts.date(ofDay: day)
        let ahead = day > facts.today
        let hours = facts.year[safe: day] ?? nil
        let blocks = facts.blocks[safe: day] ?? 0
        return VStack(spacing: 4) {
            Text(day == facts.today ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(TypeScale.chrome.weight(.medium))
                .foregroundStyle(Palette.muted)
            if ahead {
                Text(day - facts.today == 1 ? "Tomorrow" : "In \(day - facts.today) days")
                    .font(.system(size: diameter * 0.075, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(Palette.ink)
            } else {
                Text(ProtectedTime.short(hours: hours ?? 0))
                    .font(.system(size: diameter * 0.075, weight: .semibold))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .foregroundStyle((hours ?? 0) > 0 ? Palette.ink : Palette.muted)
            }
            Group {
                if day == facts.deadline, let aim {
                    Text("Deadline for \(aim.title)")
                } else if ahead {
                    Text("Still open")
                } else {
                    Text(blocks == 0 ? "Nothing blocked" : blocks == 1 ? "1 block" : "\(blocks) blocks")
                }
            }
            .font(TypeScale.chrome)
            .foregroundStyle(Palette.muted)
            .lineLimit(2)
            .multilineTextAlignment(.center)
        }
    }

    private var spokenValue: String {
        if let day = detail {
            let date = facts.date(ofDay: day).formatted(.dateTime.weekday(.wide).day().month(.wide))
            if day > facts.today {
                return day == facts.deadline ? "\(date), deadline for \(aim?.title ?? "your aim")" : "\(date), ahead"
            }
            let blocks = facts.blocks[safe: day] ?? 0
            return "\(date), \(ProtectedTime.phrase(hours: facts.year[safe: day].flatMap { $0 } ?? 0)) with blocks active, \(blocks == 1 ? "1 block" : "\(blocks) blocks")"
        }
        var parts = ["\(ProtectedTime.phrase(hours: facts.yearHours)) with blocks active this year"]
        parts.append("today \(ProtectedTime.phrase(hours: facts.year[safe: facts.today].flatMap { $0 } ?? 0))")
        parts.append("\(facts.daysLeft) days left")
        if let deadline = facts.deadline, let aim {
            parts.append("deadline for \(aim.title) on \(facts.date(ofDay: deadline).formatted(.dateTime.day().month(.wide)))")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let environment = context.environment
        func point(_ radius: CGFloat, _ index: Double) -> CGPoint {
            let angle = RingGeometry.angle(index, of: count)
            return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }
        let mid = (inner + outer) / 2
        let slot = 2 * .pi * mid / CGFloat(max(1, count)) * 0.5
        let today = facts.today

        // A faint guide through the middle of the band shows between the days.
        var guide = Path()
        guide.addEllipse(in: CGRect(x: centre.x - mid, y: centre.y - mid, width: mid * 2, height: mid * 2))
        context.stroke(guide, with: .style(Palette.hairline), style: StrokeStyle(lineWidth: 0.6, dash: [1, 4]))

        // Day cells: the past barely there, the days ahead an open dashed track.
        var past = Path(), ahead = Path()
        for index in 0..<count {
            let from = point(inner, Double(index)), to = point(outer, Double(index))
            if index > today { ahead.move(to: from); ahead.addLine(to: to) }
            else { past.move(to: from); past.addLine(to: to) }
        }
        context.stroke(past, with: .style(Palette.wash.opacity(0.35)), lineWidth: slot)
        context.stroke(ahead, with: .style(Palette.faint.opacity(0.32)), lineWidth: slot)

        // Protected hours, bucketed so a year is a handful of strokes, not hundreds.
        let neutral = Palette.faint.resolve(in: environment), accent = Palette.accent.resolve(in: environment)
        let levels = 12
        var buckets = Array(repeating: Path(), count: levels + 1)
        var unprotected = Path()
        let tick = max(1.4, slot * 0.95)
        for (index, value) in facts.year.enumerated() where index <= today {
            let hours = value ?? 0
            let from = point(inner + 1, Double(index))
            if hours <= 0 {
                unprotected.move(to: from); unprotected.addLine(to: point(inner + 3, Double(index)))
                continue
            }
            let length = inner + 4 + CGFloat(RingScale.length(hours: hours)) * (outer - inner - 5)
            let level = Int((RingScale.tint(hours: hours) * Double(levels)).rounded())
            buckets[level].move(to: from); buckets[level].addLine(to: point(length, Double(index)))
        }
        context.stroke(unprotected, with: .style(Palette.faint.opacity(0.5)), style: StrokeStyle(lineWidth: tick, lineCap: .round))
        for (level, path) in buckets.enumerated() where !path.isEmpty {
            let t = Float(max(0.18, Double(level) / Double(levels)))
            let colour = Color.Resolved(red: neutral.red + (accent.red - neutral.red) * t,
                                        green: neutral.green + (accent.green - neutral.green) * t,
                                        blue: neutral.blue + (accent.blue - neutral.blue) * t)
            context.stroke(path, with: .color(Color(colour)), style: StrokeStyle(lineWidth: tick, lineCap: .round))
        }

        // Month initials just outside the ring.
        let calendar = facts.calendar
        for month in 0..<12 {
            guard let first = calendar.date(byAdding: .month, value: month, to: facts.yearStart),
                  let days = calendar.range(of: .day, in: .month, for: first)?.count else { continue }
            let index = Double(Ledger.dayIndex(first, calendar: calendar)) + Double(days) / 2
            let symbol = calendar.veryShortStandaloneMonthSymbols[month]
            context.draw(Text(symbol).font(.system(size: max(9, diameter * 0.025), weight: .medium)).foregroundStyle(Palette.faint),
                         at: point(diameter * 0.476, index))
        }

        // The aim's deadline: a small dot just outside the band.
        if let deadline = facts.deadline {
            let at = point(outer + 7, Double(deadline))
            let dot = Path(ellipseIn: CGRect(x: at.x - 3.5, y: at.y - 3.5, width: 7, height: 7))
            context.fill(dot, with: .style(Palette.accent))
            context.stroke(dot, with: .style(Palette.ground), lineWidth: 1.5)
        }

        // Today.
        var now = Path()
        now.move(to: point(inner - 5, Double(today))); now.addLine(to: point(outer + 4, Double(today)))
        context.stroke(now, with: .style(Palette.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // The inspected day.
        if let marker {
            var line = Path()
            line.move(to: point(inner - 6, Double(marker))); line.addLine(to: point(outer + 6, Double(marker)))
            context.stroke(line, with: .style(Palette.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
