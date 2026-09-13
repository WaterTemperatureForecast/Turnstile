import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("The game", """
                    A machine accepts some sequences of three tiles and rejects others, following a secret rule. \
                    You see a few labelled examples, run up to four experiments of your own, then classify four hidden sequences. \
                    Four right is a perfect score. There is no penalty for experiments and no clock: thinking slowly is fine.
                    """)
                    section("Two machines a day", """
                    One is built by Claude, one by GPT. Before you see them, each AI has tried to crack the other's machine blind. \
                    After you finish, the reveal shows the rule, the setter's note about the trap it laid, the rival AI's experiments, \
                    and how many people solved it.
                    """)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tiles").font(.headline)
                        HStack(spacing: 8) { ForEach(0..<9, id: \.self) { TileView(tile: $0, size: 32) } }
                        Text("Three shapes (circle, square, triangle) in three colours (red, blue, yellow). A sequence is three tiles; repeats are allowed.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .card()
                    section("What a rule can say", """
                    • Position: the tile in position 1, 2 or 3 has a given shape or colour.
                    • Count: exactly N tiles (0 to 3) have a given shape or colour.
                    • Match: two given positions share their shape, or share their colour.
                    • All same / all different: the three shapes (or colours) are all the same, or all different.

                    Monday to Wednesday the rule is one of these, or NOT one of these. Thursday to Saturday two can be joined by AND or OR. \
                    Sunday adds XOR (exactly one of the two).
                    """)
                    section("Fair by construction", """
                    Every machine is checked by code before it is published: there is always a four-experiment strategy that decides the hidden tests. \
                    A good experiment is one whose answer separates the rules you still believe in. Write your current guess in the note box if it helps; nobody else sees it.
                    """)
                    section("Stars and boards", """
                    After answering you can build the rule you believe in. A star if it matches the machine on every possible sequence; \
                    if not, you see one sequence where they differ. The daily board ranks score out of 8, then stars, then fewer experiments. \
                    The Setters board scores Claude and GPT on how well calibrated their machines were for people.
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

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
