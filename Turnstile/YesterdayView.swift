import SwiftUI

struct YesterdayView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let r = model.yesterday {
                        ResultsSummary(results: r)
                    } else if let e = model.yesterdayError {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundColor(.secondary)
                            Text(e).foregroundColor(.secondary).multilineTextAlignment(.center)
                            Button("Try again") { Task { await model.loadYesterday() } }.buttonStyle(.bordered)
                        }
                        .padding(40)
                    } else {
                        ProgressView().padding(40)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Yesterday")
            .task { await model.loadYesterday() }
            .refreshable { await model.loadYesterday() }
        }
    }
}

/// A closed (or finished) round: both machines with their rules and stats, your line, top ten.
struct ResultsSummary: View {
    let results: Results

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(UTCDay.label(results.date)).font(.headline)
                Spacer()
                Text(results.final ? "Closed · \(results.player_count) played" : "\(results.player_count) played so far")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let you = results.you {
                HStack(spacing: 12) {
                    Text("You: \(you.score)/\(results.machines.count * 4)").font(.subheadline.weight(.semibold))
                    if you.stars > 0 { Text(String(repeating: "★", count: you.stars)).foregroundColor(.yellow) }
                    Text("#\(you.rank)").font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                Text("You did not play this round.").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .card()

        ForEach(results.machines) { m in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(m.setter.kind == "agent" ? "\(m.setter.name)'s machine" : "House machine", systemImage: m.setter.kind == "agent" ? "cpu" : "building.columns")
                        .font(.headline)
                    Spacer()
                    if let you = m.you, let s = you.score {
                        Text("\(s)/4").font(.headline.monospacedDigit())
                        if you.star { Text("★").foregroundColor(.yellow) }
                    }
                }
                if let rule = m.rule_text {
                    Text(rule.capitalizedFirst).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("The rule is shown once the day ends.").font(.subheadline).foregroundColor(.secondary)
                }
                if m.stats.finished > 0 {
                    Text("\(m.stats.finished) played · \(Int((m.stats.solved_pct ?? 0).rounded()))% got all four · \(Int((m.stats.star_pct ?? 0).rounded()))% named the rule")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }

        if !results.leaderboard.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top ten").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                ForEach(results.leaderboard) { e in
                    BoardRow(entry: e)
                }
            }
            .card()
        }
    }
}

struct BoardRow: View {
    let entry: BoardEntry
    var body: some View {
        HStack(spacing: 8) {
            Text("#\(entry.rank)").font(.subheadline.monospacedDigit()).foregroundColor(.secondary).frame(width: 40, alignment: .leading)
            Text(entry.name).font(.subheadline).lineLimit(1)
            KindBadge(isAgent: entry.isAgent)
            Spacer()
            if let stars = entry.stars, stars > 0 {
                Text(String(repeating: "★", count: min(stars, 5))).font(.caption).foregroundColor(.yellow)
            }
            if let rounds = entry.rounds {
                Text("\(rounds) rounds").font(.caption).foregroundColor(.secondary)
            }
            Text(entry.score.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(entry.score))" : String(format: "%.1f", entry.score))
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
    }
}
