import SwiftUI

/// The last two weeks, newest first. Tapping a day shows both machines' rules.
struct HistoryView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(1...14, id: \.self) { back in
                    let key = GameCalendar.key(daysAgo: back)
                    let mine: PastDay? = store.profile?.rounds.first(where: { $0.date == key })
                    let line: String = mine.map { d -> String in "You scored \(d.score)/8, placed \(d.rank) of \(d.playerCount)" } ?? "You did not play"
                    NavigationLink(value: key) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(GameCalendar.pretty(key)).font(Typeface.label).foregroundColor(Palette.text)
                                Text(verbatim: line)
                                    .font(Typeface.small).foregroundColor(Palette.muted)
                            }
                            Spacer()
                            if let mine, mine.stars > 0 {
                                Text(String(repeating: "\u{2605}", count: mine.stars)).foregroundColor(Palette.gold)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundColor(Palette.muted)
                        }
                        .slab(padding: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle("Past days")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { key in DayDetailView(key: key) }
    }
}

struct DayDetailView: View {
    @EnvironmentObject var store: GameStore
    let key: String
    @State private var summary: DaySummary?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let problem { NoticeBar(text: problem) }
                if let s = summary {
                    if let you = s.you {
                        HStack(spacing: 16) {
                            ScoreRing(score: you.score, outOf: 8, diameter: 88)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Placed \(you.rank) of \(s.playerCount)").font(Typeface.heading).foregroundColor(Palette.text)
                                Text("\(you.experiments) rows tried").font(Typeface.small).foregroundColor(Palette.muted)
                            }
                        }
                        .slab()
                    }
                    ForEach(s.machines) { m in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(m.setter.isAI ? "\(m.setter.name)\u{2019}s machine" : "Bonus machine")
                                    .font(Typeface.label).foregroundColor(Palette.text)
                                if m.setter.isAI { AITag() }
                                Spacer()
                                if let score = m.you?.score { Text("\(score)/4").font(Typeface.label).foregroundColor(Palette.text) }
                            }
                            Text((m.ruleText ?? "The rule appears once the day is over").sentenceCased + ".")
                                .font(Typeface.body).foregroundColor(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if m.stats.finished > 0 {
                                Text("\(m.stats.finished) played \u{00b7} \(Int((m.stats.solvedPct ?? 0).rounded()))% got all four")
                                    .font(Typeface.small).foregroundColor(Palette.muted)
                            }
                        }
                        .slab()
                    }
                } else if problem == nil {
                    ProgressView().tint(Palette.brand).frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(18)
        }
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle(GameCalendar.short(key))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { summary = try await store.day(key) } catch {
                problem = (error as? GateError)?.errorDescription ?? "That day could not be loaded."
            }
        }
    }
}
