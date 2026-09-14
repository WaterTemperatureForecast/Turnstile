import SwiftUI

/// Shown once a machine is answered: the rule, the builder's trap, the crowd, the rival.
struct VerdictView: View {
    let verdict: Verdict

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The secret rule").eyebrow()
            Text(verdict.ruleText.sentenceCased + ".")
                .font(Typeface.display(22))
                .foregroundColor(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let note = verdict.setterNote, !note.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(Palette.brand).frame(width: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(verdict.setter.name).font(Typeface.tiny).foregroundColor(Palette.muted)
                            if verdict.setter.isAI { AITag() }
                        }
                        Text(note).font(Typeface.body).italic().foregroundColor(Palette.text.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .slab()

        crowd

        ForEach(verdict.agents) { run in rival(run) }
    }

    @ViewBuilder private var crowd: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How everyone did").eyebrow()
            if verdict.stats.finished == 0 {
                Text("You are the first to finish this machine.").font(Typeface.body).foregroundColor(Palette.text)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                    figure("\(verdict.stats.finished)", "played it")
                    figure("\(Int((verdict.stats.solvedPct ?? 0).rounded()))%", "got all four")
                    figure(String(format: "%.1f", verdict.stats.meanScore ?? 0), "average out of 4")
                    figure("\(Int((verdict.stats.starPct ?? 0).rounded()))%", "named the rule")
                }
            }
        }
        .slab()
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Typeface.display(24)).foregroundColor(Palette.text)
            Text(caption).font(Typeface.small).foregroundColor(Palette.muted)
        }
    }

    private func rival(_ run: RivalRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(run.name).font(Typeface.heading).foregroundColor(Palette.text)
                AITag()
                Spacer()
                Text("\(run.score)/4").font(Typeface.heading).foregroundColor(Palette.text)
            }
            Text(run.queries.isEmpty ? "It went straight to the final four." : "What it tried, before anyone else saw this machine:")
                .font(Typeface.small).foregroundColor(Palette.muted)
            ForEach(Array(run.queries.enumerated()), id: \.offset) { i, q in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(Typeface.tiny).foregroundColor(Palette.muted).frame(width: 14)
                    VStack(alignment: .leading, spacing: 4) {
                        TileStrip(row: q.seq, size: 26)
                        if let note = q.note, !note.isEmpty {
                            Text(note).font(Typeface.small).foregroundColor(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    VerdictMark(accepted: q.accepted, size: 24)
                }
            }
            HStack(spacing: 6) {
                Text("Its calls").font(Typeface.small).foregroundColor(Palette.muted)
                ForEach(Array(run.answers.enumerated()), id: \.offset) { i, said in
                    let right = i < verdict.truth.count && verdict.truth[i] == said
                    Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(right ? Palette.pass : Palette.stop)
                        .accessibilityLabel(Text(right ? "row \(i + 1) right" : "row \(i + 1) wrong"))
                }
            }
            if let star = run.star {
                Text((star.hit ? "It named the rule: " : "It guessed: ") + star.ruleText)
                    .font(Typeface.small).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .slab()
    }
}
