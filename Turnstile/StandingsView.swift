import SwiftUI

/// Who is doing well. Any player's name can be reported or hidden from this device.
struct StandingsView: View {
    @EnvironmentObject var store: GameStore
    @State private var period = "today"
    @State private var table: Standings?
    @State private var problem: String?
    @State private var flagged: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Period", selection: $period) {
                    Text("Today").tag("today")
                    Text("30 days").tag("30d")
                    Text("AI builders").tag("setters")
                }
                .pickerStyle(.segmented)

                if let problem { NoticeBar(text: problem) }
                if let flagged {
                    Text("Thanks. A person will look at \u{201C}\(flagged)\u{201D}.")
                        .font(Typeface.small).foregroundColor(Palette.muted)
                }

                if let t = table, t.period == period {
                    if period == "setters" { builders(t.setters ?? []) } else { players(t.players ?? []) }
                } else {
                    ProgressView().tint(Palette.brand).frame(maxWidth: .infinity).padding(.top, 60)
                }

                if !store.hiddenPlayers.isEmpty {
                    Button("Show the \(store.hiddenPlayers.count) hidden players again") { store.unhideAll() }
                        .font(Typeface.small)
                        .foregroundColor(Palette.brand)
                }
            }
            .padding(18)
        }
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: period) { await load() }
    }

    private func load() async {
        do {
            table = try await store.standings(period)
            problem = nil
        } catch {
            problem = (error as? GateError)?.errorDescription
        }
    }

    @ViewBuilder private func players(_ rows: [StandingRow]) -> some View {
        let visible = rows.filter { $0.isAI || !store.hiddenPlayers.contains($0.name) }
        if visible.isEmpty {
            Text(period == "today" ? "Nobody has finished today yet." : "Nobody has played five days yet.")
                .font(Typeface.body).foregroundColor(Palette.muted).padding(.top, 30)
        } else {
            VStack(spacing: 0) {
                ForEach(visible) { row in
                    HStack(spacing: 12) {
                        Text("\(row.rank)").font(Typeface.label).foregroundColor(Palette.muted).frame(width: 30, alignment: .leading)
                        Text(row.name).font(Typeface.body).foregroundColor(Palette.text).lineLimit(1)
                        if row.isAI { AITag() }
                        Spacer()
                        if let stars = row.stars, stars > 0 {
                            Text(String(repeating: "\u{2605}", count: min(stars, 5))).font(Typeface.small).foregroundColor(Palette.gold)
                        }
                        Text(row.score.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(row.score))" : String(format: "%.1f", row.score))
                            .font(Typeface.label).foregroundColor(Palette.text)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if !row.isAI {
                            Button {
                                Task { if await store.flag(row.name) { flagged = row.name } }
                            } label: { Label("Report this name", systemImage: "flag") }
                            Button(role: .destructive) {
                                store.hide(row.name)
                            } label: { Label("Hide this player", systemImage: "eye.slash") }
                        }
                    }
                    Divider().overlay(Palette.edge)
                }
                Text("Press and hold a name to report it or hide that player.")
                    .font(Typeface.small).foregroundColor(Palette.muted)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .slab(padding: 14)
        }
    }

    @ViewBuilder private func builders(_ lines: [SetterLine]) -> some View {
        Text("Claude and GPT build the machines, so they are scored on how well they pitch them. A machine is best when 40 to 70 percent of people get all four, with a bonus point for one the other AI could not crack.")
            .font(Typeface.small).foregroundColor(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
        if lines.isEmpty {
            Text("No machine results yet.").font(Typeface.body).foregroundColor(Palette.muted)
        }
        ForEach(lines) { line in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(line.name).font(Typeface.heading).foregroundColor(Palette.text)
                    AITag()
                    Spacer()
                    Text("\(line.points) points").font(Typeface.label).foregroundColor(Palette.brand)
                }
                ForEach(line.recent.prefix(7)) { d in
                    HStack(spacing: 10) {
                        Text(GameCalendar.short(d.date)).font(Typeface.small).foregroundColor(Palette.muted).frame(width: 56, alignment: .leading)
                        Text(d.finished > 0 ? "\(Int((d.solvedPct ?? 0).rounded()))% got all four" : "no results yet")
                            .font(Typeface.small).foregroundColor(Palette.text)
                        Spacer()
                        if let r = d.rivalScore { Text("rival \(r)/4").font(Typeface.small).foregroundColor(Palette.muted) }
                        Text("+\(d.points)").font(Typeface.label).foregroundColor(Palette.text)
                    }
                }
            }
            .slab()
        }
    }
}
