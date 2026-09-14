import SwiftUI

/// Your name on the standings, your record, and control over your data.
struct ProfileView: View {
    @EnvironmentObject var store: GameStore
    @State private var nameDraft = ""
    @State private var nameNote: String?
    @State private var agreed = UserDefaults.standard.bool(forKey: "name-terms-agreed")
    @State private var confirmForget = false
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let p = store.profile { record(p) }
                nameCard
                privacyCard
                contactCard
            }
            .padding(18)
        }
        .background(Palette.ink.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { typing = false }
            }
        }
        .task {
            await store.loadProfile()
            if nameDraft.isEmpty { nameDraft = store.profile?.nickname ?? "" }
        }
        .confirmationDialog("Delete everything about you?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Delete my data", role: .destructive) { Task { _ = await store.forget() } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your name, scores, history and private hunches are removed from the server, and this device starts over as a new player.")
        }
    }

    private func record(_ p: PlayerProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your record").eyebrow()
            HStack(spacing: 0) {
                figure("\(p.roundsPlayed)", "days played")
                figure("\(p.streak)", "day streak")
                figure(p.lifetimeScore.map { String(format: "%.1f", $0) } ?? "\u{2013}", "average of 8")
                figure("\(p.stars)", "stars")
            }
        }
        .slab()
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Typeface.display(22)).foregroundColor(Palette.text)
            Text(caption).font(Typeface.tiny).foregroundColor(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name on the standings").eyebrow()
            Text("Optional. Without one you appear as \u{201C}Player\u{201D} and four letters.")
                .font(Typeface.small).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if agreed {
                HStack(spacing: 10) {
                    TextField("Your name", text: $nameDraft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveName() } }
                        .padding(12)
                        .background(Palette.slateHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button("Save") { Task { await saveName() } }
                        .font(Typeface.label)
                        .foregroundColor(Palette.brand)
                }
                if let nameNote { Text(nameNote).font(Typeface.small).foregroundColor(Palette.muted) }
            } else {
                Text("Names are seen by other players, so there is one rule: nothing hateful, sexual, threatening or impersonating someone. Names are checked automatically, anyone can report one, reports are reviewed within a day, and a player who breaks the rule is removed.")
                    .font(Typeface.small).foregroundColor(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button("I agree, let me choose a name") {
                    agreed = true
                    UserDefaults.standard.set(true, forKey: "name-terms-agreed")
                }
                .buttonStyle(OutlineButton())
            }
        }
        .slab()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your data").eyebrow()
            Text("No account, no ads, no tracking. A random code kept on this device is the only thing that links your scores together. Your hunches are never shown to anyone.")
                .font(Typeface.small).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let url = URL(string: "https://turnstile.advancedfield.tech/privacy") {
                    Link("Privacy policy", destination: url).font(Typeface.label)
                }
                Spacer()
                Button("Delete my data", role: .destructive) { confirmForget = true }
                    .font(Typeface.label)
            }
        }
        .slab()
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get in touch").eyebrow()
            Text("A problem with a machine, a name that should not be there, or an idea for the game.")
                .font(Typeface.small).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            // The address advancedfield.tech itself publishes.
            if let mail = URL(string: "mailto:contact@advancedfield.tech?subject=Turnstile%20AI") {
                Link(destination: mail) {
                    Label("contact@advancedfield.tech", systemImage: "envelope").font(Typeface.label)
                }
            }
        }
        .slab()
    }

    private func saveName() async {
        typing = false
        nameNote = await store.rename(nameDraft)
    }
}
