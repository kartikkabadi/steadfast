import Foundation

/// A short line shown while a block runs, for the moment someone reaches for what
/// they blocked. Plain and calm; most are Steadfast's own. A quotation carries its
/// source, and only quotations whose wording and attribution are certain belong here.
public struct SteadyLine: Equatable, Sendable {
    public let text: String
    /// "Seneca, On the Shortness of Life". Nil for Steadfast's own lines.
    public let source: String?

    public init(_ text: String, source: String? = nil) {
        self.text = text; self.source = source
    }
}

public enum SteadyLines {
    /// Lines for anyone, whatever they are protecting time for.
    public static let general: [SteadyLine] = [
        SteadyLine("The urge rises, peaks and passes, usually within a few minutes. You don't have to act on it."),
        SteadyLine("This hour won't come back. You're deciding what it was for."),
        SteadyLine("Wanting to check is not the same as needing to."),
        SteadyLine("You set this block when you were thinking clearly. Trust that version of you."),
        SteadyLine("The feed will be just as full when the block ends. It always is."),
        SteadyLine("Nothing you'd find there now will matter next week. What you do with this hour might."),
        SteadyLine("Every hour you keep is an hour spent on purpose."),
        SteadyLine("The pull fades faster than it promises. Give it a little longer."),
        SteadyLine("This is what changing a habit feels like from the inside. It gets quieter."),
        SteadyLine("Who you become is mostly decided in ordinary hours, like this one."),
        SteadyLine("It is not that we have a short time to live, but that we waste a lot of it.",
                   source: "Seneca, On the Shortness of Life"),
        SteadyLine("How we spend our days is, of course, how we spend our lives.",
                   source: "Annie Dillard, The Writing Life"),
    ]

    /// Lines that speak to one kind of aim, mixed in with the general ones.
    public static func specific(to kind: AimKind) -> [SteadyLine] {
        switch kind {
        case .build: return [
            SteadyLine("What you're building only grows in hours like this one."),
            SteadyLine("Shipping is mostly showing up for unglamorous hours. This is one of them."),
        ]
        case .learn: return [
            SteadyLine("Skill is attention, repeated. You're giving it some now."),
            SteadyLine("The hard part of learning is staying with it past the itch to look away."),
        ]
        case .health: return [
            SteadyLine("Your body keeps the hours you give it."),
            SteadyLine("Stand up and move for ten minutes. See if you still want it after."),
        ]
        case .create: return [
            SteadyLine("The draft doesn't need you to feel ready. It needs this hour."),
            SteadyLine("Make something small and bad now. You can make it good later."),
        ]
        case .people: return [
            SteadyLine("The people you love only exist in the present tense."),
            SteadyLine("Put the screen down and go find someone."),
        ]
        case .calm: return [
            SteadyLine("Notice the pull, name it, let it go by. That's the whole practice."),
            SteadyLine("Quiet feels uncomfortable at first. Then it's just quiet."),
        ]
        case .other: return []
        }
    }

    /// Every line that may be shown for `kind`, specific ones first.
    public static func pool(for kind: AimKind?) -> [SteadyLine] {
        (kind.map(specific) ?? []) + general
    }

    /// The line for one block: the same for as long as it runs, usually different
    /// for the next. Uses a fixed hash of the block's ID, so it survives relaunches.
    public static func line(for block: UUID, kind: AimKind?) -> SteadyLine {
        let lines = pool(for: kind)
        return lines[Int(stableHash(block) % UInt64(lines.count))]
    }

    /// FNV-1a over the UUID's bytes. Swift's `Hasher` is seeded per process.
    static func stableHash(_ id: UUID) -> UInt64 {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return bytes.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}
