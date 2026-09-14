import SwiftUI

/// Everything that is not today's machines lives behind this one menu.
struct MenuSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss

    enum Place: Hashable { case history, standings, profile, guide }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let p = store.profile { summary(p) }
                    entry(.history, icon: "calendar", title: "Past days", detail: "Every machine you played and its rule")
                    entry(.standings, icon: "trophy", title: "Standings", detail: "Today, the last 30 days, and the AI builders")
                    entry(.profile, icon: "person.crop.circle", title: "You", detail: "Your name, your record, your data")
                    entry(.guide, icon: "questionmark.circle", title: "How to play", detail: "The rules of the game in two minutes")
                    if !store.links.isEmpty { moreFromUs }
                }
                .padding(18)
            }
            .background(Palette.ink.ignoresSafeArea())
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.ink, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(for: Place.self) { place in
                switch place {
                case .history: HistoryView()
                case .standings: StandingsView()
                case .profile: ProfileView()
                case .guide: GuideView(embedded: true)
                }
            }
        }
        .preferredColorScheme(.dark)
        .environmentObject(store)
        .task { await store.loadProfile() }
    }

    private func summary(_ p: PlayerProfile) -> some View {
        HStack(spacing: 0) {
            stat("\(p.streak)", p.streak == 1 ? "day streak" : "days streak")
            stat("\(p.roundsPlayed)", "days played")
            stat("\(p.stars)", p.stars == 1 ? "star" : "stars")
        }
        .slab(padding: 14)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Typeface.display(26)).foregroundColor(Palette.text)
            Text(caption).font(Typeface.tiny).foregroundColor(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func entry(_ place: Place, icon: String, title: String, detail: String) -> some View {
        NavigationLink(value: place) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(Palette.brand)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typeface.label).foregroundColor(Palette.text)
                    Text(detail).font(Typeface.small).foregroundColor(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundColor(Palette.muted)
            }
            .slab(padding: 16)
        }
        .buttonStyle(.plain)
    }

    private var moreFromUs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Also from Advanced Field Technologies").eyebrow()
            ForEach(store.links) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title).font(Typeface.label).foregroundColor(Palette.text)
                            if let sub = link.subtitle { Text(sub).font(Typeface.small).foregroundColor(Palette.muted) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .slab()
        .padding(.top, 6)
    }
}
