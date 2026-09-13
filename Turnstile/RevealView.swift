import SwiftUI

/// After answering: the rule, the setter's note, how everyone did, and the AI transcripts.
struct RevealView: View {
    let reveal: Reveal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The rule").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Text(reveal.rule_text.capitalizedFirst)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let note = reveal.setter_note, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: reveal.setter.kind == "agent" ? "cpu" : "building.columns").foregroundColor(.secondary)
                    Text("\(reveal.setter.name): \u{201C}\(note)\u{201D}")
                        .font(.subheadline).italic().foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .card()

        stats

        ForEach(reveal.agents) { agent in
            transcript(agent)
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Everyone").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            if reveal.stats.finished == 0 {
                Text("You are the first person to finish this machine.").font(.subheadline)
            } else {
                HStack {
                    stat("\(reveal.stats.finished)", "finished")
                    Divider().frame(height: 30)
                    stat("\(Int((reveal.stats.solved_pct ?? 0).rounded()))%", "scored 4/4")
                    Divider().frame(height: 30)
                    stat(String(format: "%.1f", reveal.stats.mean_score ?? 0), "mean score")
                    Divider().frame(height: 30)
                    stat("\(Int((reveal.stats.star_pct ?? 0).rounded()))%", "named it")
                }
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func transcript(_ agent: AgentTranscript) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(agent.name, systemImage: "cpu").font(.headline)
                Spacer()
                Text("\(agent.score)/4").font(.headline.monospacedDigit())
                if agent.star?.hit == true { Text("★").foregroundColor(.yellow) }
            }
            Text(agent.queries.isEmpty ? "Went straight to the tests." : "How it investigated, blind, before you saw this machine:")
                .font(.caption).foregroundColor(.secondary)
            ForEach(Array(agent.queries.enumerated()), id: \.offset) { i, q in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 18, height: 18)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    ExampleRow(seq: q.seq, accepted: q.accepted, note: q.note)
                }
            }
            HStack(spacing: 6) {
                Text("Tests:").font(.caption).foregroundColor(.secondary)
                ForEach(Array(agent.answers.enumerated()), id: \.offset) { i, a in
                    let right = i < reveal.truth.count && reveal.truth[i] == a
                    Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(right ? .green : .red)
                        .accessibilityLabel(Text(right ? "test \(i + 1) right" : "test \(i + 1) wrong"))
                }
            }
            if let star = agent.star {
                Text((star.hit ? "Named it: " : "Guessed: ") + star.rule_text)
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
