import SwiftUI
import SteadfastCore

struct BlockHold: View {
    let block: Commitment
    let end: Date
    let now: Date
    let aim: Aim?
    let unlocks: String
    var verified = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(block.name ?? aim?.title ?? "Room for what matters.")
                .font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Remaining.text(until: end, from: now)) left")
                    .font(.system(size: 25, weight: .medium)).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(unlocks).font(TypeScale.body).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if verified {
                Text("You can close Steadfast. Your blocks keep running.")
                    .font(TypeScale.chrome).foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 12)
    }
}

/// How much of the block has passed, drawn as a closing ring around the mark.
struct BlockRing: View {
    let fraction: Double
    /// Stroke width; the mark inside scales with the ring.
    var weight: CGFloat = 8
    @Environment(\.restrainedMotion) private var still

    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.wash, lineWidth: weight)
            Circle()
                .inset(by: weight / 2)
                .trim(from: 0, to: max(0.012, fraction))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: weight, lineCap: .round))
                .rotationEffect(.degrees(-90))

            GeometryReader { proxy in
                PauseMark()
                    .frame(width: proxy.size.width * 0.22, height: proxy.size.width * 0.28)
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(still ? nil : .smooth(duration: 0.6), value: fraction)
        .accessibilityHidden(true)
    }
}

extension Aim {
    /// The title without closing punctuation, to sit inside a sentence.
    var phrase: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
    }
}

extension Model {
    /// The Block page's line under its heading: what the time is for and what the past week kept.
    var aimSummary: String? {
        guard let aim = outcomes.aim else { return nil }
        return aim.title
    }
}
