import SwiftUI

/// Illustrations only: these views never read or write activity or commitments.
struct ExampleBlock: View {
    var body: some View {
        Card {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Example block").font(TypeScale.caption).foregroundStyle(Palette.muted)
                    Text("Time to think").font(TypeScale.title)
                    Text("45 minutes left").font(TypeScale.body).monospacedDigit()
                    Label("X and YouTube blocked", systemImage: "lock")
                        .font(TypeScale.chrome).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 16)
                BlockRing(fraction: 0.25, weight: 4).frame(width: 80, height: 80)
            }
            .padding(Inset.row)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example block: Time to think. 45 minutes left. X and YouTube blocked. This example does not start a block.")
    }
}

struct ExampleActivity: View {
    @State private var websitesExpanded = true
    @Environment(\.restrainedMotion) private var still
    private let total: Double = (35 + 20) * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ActivityTime.short(total))
                    .font(TypeScale.hero.weight(.semibold)).tracking(-0.8).monospacedDigit()
                Text("Example day · not your data").font(TypeScale.chrome).foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .combine)
            Card {
                Button {
                    withAnimation(still ? nil : Motion.interaction(.settle)) { websitesExpanded.toggle() }
                } label: {
                    row("Safari", bundleID: "com.apple.Safari", minutes: 35, expanded: websitesExpanded)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Safari, 35 minutes, example websites")
                .accessibilityValue(websitesExpanded ? "Expanded" : "Collapsed")
                if websitesExpanded {
                    VStack(spacing: 0) {
                        row("wikipedia.org", minutes: 20)
                        row("youtube.com", minutes: 15)
                    }
                    .padding(.leading, 28)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Website time within Safari")
                }
                Rule()
                row("Mail", bundleID: "com.apple.mail", minutes: 20)
            }
            Text("Website time is part of browser time.")
                .font(TypeScale.caption).foregroundStyle(Palette.muted)
        }
    }

    private func row(_ name: String, bundleID: String? = nil, minutes: Double, expanded: Bool? = nil) -> some View {
        HStack(spacing: 12) {
            Group {
                if let bundleID { AppIcon(bundleID: bundleID, size: 24) }
                else { Image(systemName: "globe").font(Symbols.header).foregroundStyle(Palette.muted) }
            }
            .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(name).font(TypeScale.body.weight(.medium)).lineLimit(1)
                    if let expanded {
                        Image(systemName: "chevron.right").font(Symbols.small).foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(expanded ? 90 : 0)).accessibilityHidden(true)
                    }
                    Spacer(minLength: 8)
                    Text(ActivityTime.short(minutes * 60)).font(TypeScale.chrome)
                        .monospacedDigit().foregroundStyle(Palette.muted).fixedSize()
                }
                GeometryReader { proxy in
                    Capsule().fill(Palette.wash)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Palette.accent).frame(width: proxy.size.width * minutes * 60 / total)
                        }
                }
                .frame(height: 3).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Inset.row).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

}
