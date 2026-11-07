import SwiftUI
import SteadfastCore

struct BlockReflectionView: View {
    let store: OutcomeStore
    let block: Commitment
    @State private var note = ""
    @State private var addingNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rule(inset: 0)
            Text("Did your last block help?").font(TypeScale.title.weight(.medium))
            Text("\(block.displayName) · \(DurationLabel.text(block.durationMinutes))")
                .font(TypeScale.chrome).foregroundStyle(Palette.muted).lineLimit(2)
            if addingNote {
                FormField("A thought to keep · optional", text: $note)
                    .accessibilityLabel("A note about your last block, optional")
                    .onChange(of: note) { _, value in note = String(value.prefix(200)) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { answers }
                VStack(alignment: .leading, spacing: 8) { answers }
            }
        }
    }

    @ViewBuilder private var answers: some View {
        Button("Yes") { answer(.helped) }.buttonStyle(RowActionStyle())
        Button("Not Really") { answer(.notHelpful) }.buttonStyle(RowActionStyle())
        if !addingNote {
            QuietLink(title: "Add a Note") { addingNote = true }
        }
        QuietLink(title: "Skip") { answer(.skipped) }
    }

    private func answer(_ answer: BlockReflection.Answer) {
        Motion.with(.settle) { store.reflect(on: block.id, answer: answer, note: answer == .skipped ? "" : note) }
    }
}

extension Model {
    var latestUnreviewedBlock: Commitment? {
        guard let block = lastBlock,
              currentTime.timeIntervalSince(block.endsAt) < 7 * 86_400,
              !outcomes.reflections.contains(where: { $0.id == block.id }) else { return nil }
        return block
    }
}
