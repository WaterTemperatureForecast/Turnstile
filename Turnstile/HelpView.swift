import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The idea").font(.headline)
                        Text("A machine is following a secret rule. You feed it rows of three tiles: it accepts some and rejects the rest. Work out the rule.")
                            .font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        exampleStrip
                        Text("Here, every accepted row starts and ends with the same colour. That is the sort of thing a rule can be.")
                            .font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .card()

                    section("How a turn goes", """
                    You start with a few rows the machine has already judged. Then you build up to four rows of your own and watch what it does with each one. \
                    Finally you are shown four rows you have never seen, and you say which ones it accepts. Exactly two of them.

                    Trying rows costs you nothing, and there is no clock. Taking your time is free.
                    """)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("The tiles").font(.headline)
                        HStack(spacing: 8) { ForEach(0..<9, id: \.self) { TileView(tile: $0, size: 32) } }
                        Text("Three shapes in three colours. A row is any three of them, and the same tile may appear more than once.")
                            .font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .card()

                    section("What a rule can be about", """
                    • Where a tile sits, like “the middle tile is blue”.
                    • How many, like “exactly two tiles are red”, or “there are no triangles”.
                    • A pair matching, like “the first and last tiles are the same colour”.
                    • All three, like “all three shapes are the same”, or “all three colours are different”.

                    That is the whole list. Early in the week the rule is one of these, or the opposite of one. Later in the week it can join two of them together, and Sunday is the hardest.
                    """)

                    section("Picking a good row to try", """
                    Suppose every accepted row so far starts with red. The rule might be “the first tile is red”, or it might be “exactly one tile is red”. \
                    A row with two red tiles tells you which: one of those rules accepts it, the other rejects it.

                    That is the whole skill. Try the row whose answer you cannot predict.
                    """)

                    section("Always solvable", """
                    Before a machine is published, a program checks that four well-chosen rows are always enough to settle the final four. \
                    There is no trivia, no trick wording, and nothing you could not have worked out.
                    """)

                    section("Stars and scores", """
                    Each machine is worth up to four points, one for each of the final four you call correctly. \
                    Two machines a day makes eight.

                    After you answer you can name the rule for a star. If your rule behaves exactly like the machine on every possible row you get it, \
                    and if not you are shown one row where the two of you disagree.
                    """)

                    section("The two machines", """
                    One is built each day by Claude and one by GPT. Before you see them, each has tried to crack the other’s machine without any help. \
                    When you finish you see the rule, a note from whoever built it about the trap they set, how everyone else did, and what the rival made of it.

                    The Board tab also scores the two of them on how well they set: a machine that almost everyone solves is too easy, and one that almost nobody solves is too hard.
                    """)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// Two rows through, two turned away, under the rule "first and last tiles are the same colour".
    private var exampleStrip: some View {
        VStack(spacing: 8) {
            ExampleRow(seq: [0, 3, 6], accepted: true)
            ExampleRow(seq: [1, 4, 7], accepted: true)
            ExampleRow(seq: [0, 4, 8], accepted: false)
            ExampleRow(seq: [2, 4, 3], accepted: false)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
