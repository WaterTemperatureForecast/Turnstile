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
                Text(board.period == "today" ? "Score out of 8, then stars, then fewer experiments." : "Mean daily score, minimum 5 rounds.")
                    .font(.caption).foregroundColor(.secondary)
                ForEach(list) { e in BoardRow(entry: e) }
            }
            .card()
        }
    }

    @ViewBuilder private func setters(_ list: [SetterEntry]) -> some View {
        if list.isEmpty {
            Text("No setter results yet.").font(.subheadline).foregroundColor(.secondary).padding(40)
        } else {
            Text("Calibration points: 2 when 40–70% of people scored 4/4, 1 when close, +1 when the rival AI did not.")
                .font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(list) { s in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(s.name, systemImage: "cpu").font(.headline)
                        Spacer()
                        Text("\(s.points) pts · \(s.machines) machines").font(.subheadline.monospacedDigit())
                    }
                    ForEach(s.recent.prefix(7)) { m in
                        HStack {
                            Text(UTCDay.label(m.date)).font(.caption).foregroundColor(.secondary).frame(width: 52, alignment: .leading)
                            Text("T\(m.tier)").font(.caption2.weight(.bold)).foregroundColor(.accentColor)
                            Text(m.finished > 0 ? "\(Int((m.solved_pct ?? 0).rounded()))% solved · \(m.finished) played" : "no results yet")
                                .font(.caption)
                            Spacer()
                            if let r = m.rival_score { Text("rival \(r)/4").font(.caption).foregroundColor(.secondary) }
                            Text("+\(m.points)").font(.caption.monospacedDigit().weight(.semibold))
                        }
                    }
                }
                .card()
            }
        }
    }
}
