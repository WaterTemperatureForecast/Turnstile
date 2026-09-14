import SwiftUI

/// How to play, in plain words with one worked example.
struct GuideView: View {
    /// True when pushed inside the menu; false when shown on its own as a sheet.
    var embedded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if embedded {
            content.navigationTitle("How to play").navigationBarTitleDisplayMode(.inline)
        } else {
            NavigationStack {
                content
                    .navigationTitle("How to play")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Palette.ink, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { dismiss() } } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Work out the secret rule").font(Typeface.display(24)).foregroundColor(Palette.text)
                    Text("A machine follows a rule you cannot see. Feed it a row of three tiles and it accepts the row or rejects it. Your job is to work out why.")
                        .font(Typeface.body).foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 14) {
                        example("Accepted", rows: [[0, 3, 6], [1, 4, 7]], tint: Palette.pass)
                        example("Rejected", rows: [[0, 4, 8], [2, 4, 3]], tint: Palette.stop)
                    }
                    Text("Here every accepted row starts and ends with the same colour. That is the kind of thing a rule can be.")
                        .font(Typeface.small).foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .slab()

                step("1", "Look", "Each machine shows you rows it has already accepted and rejected.")
                step("2", "Try", "Build up to four rows of your own and see what the machine does with each. Trying costs nothing and there is no clock.")
                step("3", "Call it", "You are shown four rows you have never seen. Say which ones the machine accepts. Exactly two of them.")
                step("\u{2605}", "Name it", "Afterwards, build the rule you think it is. If it matches the machine on every possible row, you earn a star.")

                VStack(alignment: .leading, spacing: 10) {
                    Text("What a rule can be about").eyebrow()
                    bullet("Where a tile sits, like \u{201C}the middle tile is blue\u{201D}.")
                    bullet("How many, like \u{201C}exactly two tiles are red\u{201D} or \u{201C}there are no triangles\u{201D}.")
                    bullet("A pair matching, like \u{201C}the first and last tiles are the same colour\u{201D}.")
                    bullet("All three, like \u{201C}all three shapes are the same\u{201D} or \u{201C}all three colours are different\u{201D}.")
                    Text("Early in the week a rule is one of these, or its opposite. Later in the week two can be joined together, and Sunday is the hardest.")
                        .font(Typeface.small).foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .slab()

                VStack(alignment: .leading, spacing: 10) {
                    Text("A good row to try").eyebrow()
                    Text("Suppose every accepted row so far starts with red. The rule might be \u{201C}the first tile is red\u{201D} or \u{201C}exactly one tile is red\u{201D}. A row with two red tiles settles it: one of those rules accepts it and the other does not. Try the row whose answer you cannot predict.")
                        .font(Typeface.body).foregroundColor(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .slab()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Who builds the machines").eyebrow()
                    Text("Each day Claude builds one machine and GPT builds the other, and each tries to crack the other\u{2019}s before you see them. When you finish, you see the rule, the builder\u{2019}s note about the trap, and what the rival tried. A program checks every machine first, so four good rows are always enough.")
                        .font(Typeface.body).foregroundColor(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .slab()
            }
            .padding(18)
        }
        .background(Palette.ink.ignoresSafeArea())
    }

    private func example(_ title: String, rows: [TileRow3], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title).eyebrow()
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in TileStrip(row: r, size: 30) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ mark: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(mark)
                .font(Typeface.heading)
                .foregroundColor(Palette.ink)
                .frame(width: 34, height: 34)
                .background(Palette.brand, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typeface.label).foregroundColor(Palette.text)
                Text(detail).font(Typeface.small).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .slab(padding: 16)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Palette.brand).frame(width: 5, height: 5).padding(.top, 7)
            Text(text).font(Typeface.body).foregroundColor(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
