import SwiftUI

/// The whole day on one screen: the date, the two machines, and your result.
struct GateHomeView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showMenu = false
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let notice = store.notice { NoticeBar(text: notice) }
                    if let gate = store.gate {
                        masthead(gate)
                        levelLine(gate)
                        ForEach(gate.machines) { machine in
                            NavigationLink(value: machine.id) { MachineTile(machine: machine) }
                                .buttonStyle(.plain)
                        }
                        if gate.finished { dayResult(gate) }
                        if let sponsor = gate.sponsor { SponsorNote(sponsor: sponsor) }
                    } else if store.loading {
                        ProgressView().tint(Palette.brand).frame(maxWidth: .infinity).padding(.top, 120)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(Palette.ink.ignoresSafeArea())
            .refreshable { await store.loadDay() }
            .navigationDestination(for: String.self) { id in MachineScreen(machineId: id) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Turnstile").font(Typeface.heading).foregroundColor(Palette.text)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showGuide = true } label: { Image(systemName: "questionmark") }
                        .accessibilityLabel("How to play")
                    Button { showMenu = true } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Menu")
                }
            }
            .toolbarBackground(Palette.ink, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showMenu) { MenuSheet().environmentObject(store) }
            .sheet(isPresented: $showGuide) { GuideView() }
        }
        .task {
            await store.loadDay()
            await store.loadProfile()
            await store.loadLinks()
            if store.profile?.roundsPlayed == 0 && !UserDefaults.standard.bool(forKey: "guide-seen") {
                UserDefaults.standard.set(true, forKey: "guide-seen")
                showGuide = true
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await store.loadDay() } }
        }
    }

    private func masthead(_ gate: DailyGate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(GameCalendar.pretty(gate.date))
                .font(Typeface.display(30))
                .foregroundColor(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ResetClock(endsAt: gate.closesAt)
                Text("\u{00b7}")
                Text(gate.playerCount == 1 ? "1 person has played" : "\(gate.playerCount) people have played")
            }
            .font(Typeface.small)
            .foregroundColor(Palette.muted)
        }
        .padding(.top, 4)
    }

    private func levelLine(_ gate: DailyGate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { level in
                    Capsule()
                        .fill(level <= gate.tier ? Palette.brand : Palette.slateHigh)
                        .frame(width: 18, height: 6)
                }
            }
            .padding(.top, 6)
            .accessibilityLabel(Text("Level \(gate.tier) of 3"))
            Text(gate.tierText)
                .font(Typeface.small)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dayResult(_ gate: DailyGate) -> some View {
        HStack(spacing: 18) {
            ScoreRing(score: store.dayTotal, outOf: gate.machines.count * 4, diameter: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text("Done for today").font(Typeface.heading).foregroundColor(Palette.text)
                if store.dayStars > 0 {
                    Text(String(repeating: "\u{2605} ", count: store.dayStars) + (store.dayStars == 1 ? "rule named" : "rules named"))
                        .font(Typeface.label).foregroundColor(Palette.gold)
                }
                ShareLink(item: store.brag) {
                    Label("Share", systemImage: "square.and.arrow.up").font(Typeface.label)
                }
            }
            Spacer(minLength: 0)
        }
        .slab()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash").font(.system(size: 34)).foregroundColor(Palette.muted)
            Text("Today\u{2019}s machines did not load.").font(Typeface.body).foregroundColor(Palette.muted)
            Button("Try again") { Task { await store.loadDay() } }
                .buttonStyle(BrightButton())
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

/// One machine on the home screen, showing a taste of what it did.
struct MachineTile: View {
    let machine: Machine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(machine.title).font(Typeface.heading).foregroundColor(Palette.text)
                if machine.setter.isAI { AITag() }
                Spacer()
                status
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundColor(Palette.muted)
            }
            HStack(alignment: .top, spacing: 16) {
                lane(title: "Accepted", rows: machine.examples.filter { $0.accepted }, tint: Palette.pass)
                lane(title: "Rejected", rows: machine.examples.filter { !$0.accepted }, tint: Palette.stop)
            }
            .opacity(machine.play.isFinished ? 0.55 : 1)
        }
        .slab()
    }

    private func lane(title: String, rows: [JudgedRow], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow().foregroundColor(tint)
            ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { _, r in TileStrip(row: r.seq, size: 24) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var status: some View {
        if machine.play.isFinished {
            HStack(spacing: 3) {
                Text("\(machine.play.score ?? 0)/4").font(Typeface.label).foregroundColor(Palette.text)
                if machine.play.star?.hit == true { Text("\u{2605}").foregroundColor(Palette.gold) }
            }
        } else if machine.play.isCalling {
            Text("Final four").font(Typeface.tiny).foregroundColor(Palette.brand)
        } else if machine.play.queries.isEmpty {
            Text("Play").font(Typeface.tiny).foregroundColor(Palette.brand)
        } else {
            Text("\(machine.triesLeft) tries left").font(Typeface.tiny).foregroundColor(Palette.brand)
        }
    }
}

struct SponsorNote: View {
    let sponsor: Sponsor
    var body: some View {
        if let url = URL(string: sponsor.url) {
            Link(destination: url) {
                VStack(spacing: 3) {
                    Text("Supported by \(sponsor.name)").font(Typeface.tiny).foregroundColor(Palette.muted)
                    if !sponsor.tagline.isEmpty {
                        Text(sponsor.tagline).font(Typeface.small).foregroundColor(Palette.muted.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 6)
        }
    }
}
