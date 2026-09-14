import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let message = model.errorMessage {
                        if model.round != nil {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi.slash")
                                Text(message)
                            }
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        } else {
                            ErrorBanner(message: message)
                        }
                    }
                    if let round = model.round {
                        header(round)
                        tierCard(round)
                        ForEach(round.machines) { m in
                            NavigationLink(value: m.id) {
                                MachineCard(machine: m)
                            }
                            .buttonStyle(.plain)
                        }
                        if round.finished {
                            finishedCard(round)
                        }
                        if let s = round.sponsor {
                            SponsorRow(sponsor: s)
                        }
                    } else if model.isLoading {
                        ProgressView().padding(40)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.slash").font(.largeTitle).foregroundColor(.secondary)
                            Text("Couldn't load today's machines.").foregroundColor(.secondary)
                            Button("Try again") { Task { await model.refresh() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(40)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Turnstile")
            .navigationDestination(for: String.self) { id in
                MachineView(machineId: id)
            }
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if model.hasFinishedToday {
                        ShareLink(item: model.shareText) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .sheet(isPresented: $showHelp) { HelpView() }
        }
    }

    private func header(_ round: TodayRound) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(UTCDay.label(round.date)).font(.headline)
                Countdown(closesAt: round.closes_at).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(round.player_count)").font(.headline.monospacedDigit())
                Text("played so far").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func tierCard(_ round: TodayRound) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LEVEL \(round.tier) OF 3").font(.caption.weight(.bold)).foregroundColor(.accentColor)
                Spacer()
                Text("Two machines, four tries each").font(.caption).foregroundColor(.secondary)
            }
            Text(round.tier_text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func finishedCard(_ round: TodayRound) -> some View {
        let total = round.machines.compactMap { $0.play.score }.reduce(0, +)
        let stars = round.machines.filter { $0.play.star?.hit == true }.count
        return VStack(spacing: 6) {
            Text("Today").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            BigNumber(value: total, of: round.machines.count * 4)
            if stars > 0 {
                Text(String(repeating: "★", count: stars)).font(.title3).foregroundColor(.yellow)
            }
            Text("Come back tomorrow for two new machines.").font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

struct MachineCard: View {
    let machine: Machine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(setterLine, systemImage: machine.setter.kind == "agent" ? "cpu" : "building.columns")
                    .font(.headline)
                Spacer()
                status
            }
            HStack(spacing: 10) {
                ForEach(Array(machine.examples.prefix(3).enumerated()), id: \.offset) { _, ex in
                    HStack(spacing: 3) {
                        SequenceView(seq: ex.seq, size: 22)
                        VerdictBadge(accepted: ex.accepted, compact: true)
                    }
                }
            }
            .opacity(machine.play.phase == "answered" ? 0.6 : 1)
        }
        .card()
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right").foregroundColor(.secondary).padding(.trailing, 12)
        }
    }

    private var setterLine: String {
        machine.setter.kind == "agent" ? "\(machine.setter.name)'s machine" : "House machine"
    }

    @ViewBuilder private var status: some View {
        switch machine.play.phase {
        case "answered":
            HStack(spacing: 4) {
                Text("\(machine.play.score ?? 0)/4").font(.subheadline.weight(.bold).monospacedDigit())
                if machine.play.star?.hit == true { Text("★").foregroundColor(.yellow) }
            }
        case "tests":
            Text("Finish it").font(.caption.weight(.semibold)).foregroundColor(.accentColor)
        default:
            Text(machine.play.queries.isEmpty ? "Play" : "\(machine.max_experiments - machine.play.queries.count) tries left")
                .font(.caption.weight(.semibold)).foregroundColor(.accentColor)
        }
    }
}

struct SponsorRow: View {
    let sponsor: SponsorLine
    var body: some View {
        if let url = URL(string: sponsor.url) {
            Link(destination: url) {
                VStack(spacing: 2) {
                    Text("Today's machines are brought to you by \(sponsor.name)").font(.footnote.weight(.semibold))
                    if !sponsor.tagline.isEmpty { Text(sponsor.tagline).font(.caption).foregroundColor(.secondary) }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
        }
    }
}
