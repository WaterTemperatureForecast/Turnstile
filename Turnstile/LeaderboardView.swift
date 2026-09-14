import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $model.boardPeriod) {
                        Text("Today").tag("today")
                        Text("30 days").tag("30d")
                        Text("Setters").tag("setters")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.boardPeriod) { _ in Task { await model.loadBoard() } }

                    if let board = model.board, board.period == model.boardPeriod {
                        if board.period == "setters" {
                            setters(board.setters ?? [])
                        } else {
                            players(board)
                        }
                    } else {
                        ProgressView().padding(40)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Board")
            .task { await model.loadBoard() }
            .refreshable { await model.loadBoard() }
        }
    }

    @ViewBuilder private func players(_ board: Leaderboard) -> some View {
        let list = board.players ?? []
        if list.isEmpty {
            Text(board.period == "today" ? "Nobody has finished yet today." : "The 30-day board needs at least 5 rounds played.")
                .font(.subheadline).foregroundColor(.secondary).padding(40)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(board.period == "today"
                     ? "Out of 8 for the day. Level scores are split by stars, then by who used fewer tries."
                     : "Average score per day, for anyone who has played at least 5 days.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(list) { e in BoardRow(entry: e) }
            }
            .card()
        }
    }

    @ViewBuilder private func setters(_ list: [SetterEntry]) -> some View {
        if list.isEmpty {
            Text("No setter results yet.").font(.subheadline).foregroundColor(.secondary).padding(40)
        } else {
            Text("Claude and GPT build the machines, so they are scored on how well they pitch them. A machine is best when 40 to 70 percent of people get all four, and there is a bonus point for one the other AI could not crack.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(list) { s in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(s.name, systemImage: "cpu").font(.headline)
                        Spacer()
                        Text("\(s.points) points · \(s.machines) machines").font(.subheadline.monospacedDigit())
                    }
                    ForEach(s.recent.prefix(7)) { m in
                        HStack {
                            Text(UTCDay.label(m.date)).font(.caption).foregroundColor(.secondary).frame(width: 52, alignment: .leading)
                            Text("L\(m.tier)").font(.caption2.weight(.bold)).foregroundColor(.accentColor)
                            Text(m.finished > 0 ? "\(Int((m.solved_pct ?? 0).rounded()))% got all four" : "no results yet")
                                .font(.caption)
                            Spacer()
                            if let r = m.rival_score { Text("other AI \(r)/4").font(.caption).foregroundColor(.secondary) }
                            Text("+\(m.points)").font(.caption.monospacedDigit().weight(.semibold))
                        }
                    }
                }
                .card()
            }
        }
    }
}
