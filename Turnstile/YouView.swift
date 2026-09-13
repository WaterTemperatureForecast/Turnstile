import SwiftUI

struct YouView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete = false
    @State private var reportName = ""
    @State private var reportStatus: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let me = model.me {
                        summary(me)
                        history(me)
                    } else {
                        ProgressView().padding(20)
                    }
                    nickname
                    if !model.promos.isEmpty { promos }
                    report
                    privacy
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("You")
            .task { await model.loadMe() }
            .refreshable { await model.loadMe() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
            .confirmationDialog("Delete my data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await model.deleteMyData() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes your player record, nickname, scores, notes and history from the server. Past plays remain only as anonymous counts. You start over as a new player.")
            }
        }
    }

    private func summary(_ me: Me) -> some View {
        HStack {
            stat("\(me.rounds_played)", "rounds")
            Divider().frame(height: 36)
            stat("\(me.streak)", "streak")
            Divider().frame(height: 36)
            stat(me.lifetime_score.map { String(format: "%.1f", $0) } ?? "–", "mean /8")
            Divider().frame(height: 36)
            stat("\(me.stars)", "stars")
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func history(_ me: Me) -> some View {
        if !me.rounds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent rounds").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                ForEach(me.rounds.prefix(14)) { r in
                    HStack {
                        Text(UTCDay.label(r.date)).font(.subheadline).frame(width: 64, alignment: .leading)
                        Text("\(r.score)/8").font(.subheadline.monospacedDigit().weight(.medium))
                        if r.stars > 0 { Text(String(repeating: "★", count: r.stars)).font(.caption).foregroundColor(.yellow) }
                        Spacer()
                        Text("#\(r.rank) of \(r.player_count)" + (r.final ? "" : " · live")).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .card()
        }
    }

    private var nickname: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nickname").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            HStack {
                TextField("Shown on the board (optional)", text: $model.nicknameDraft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { Task { await model.saveNickname() } }
                Button("Save") { focused = false; Task { await model.saveNickname() } }
                    .buttonStyle(.bordered)
            }
            if let s = model.nicknameStatus { Text(s).font(.caption).foregroundColor(.secondary) }
        }
        .card()
    }

    private var promos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More from us").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            ForEach(model.promos) { p in
                if let url = URL(string: p.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(.subheadline.weight(.medium))
                            if let s = p.subtitle { Text(s).font(.caption).foregroundColor(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .card()
    }

    private var report: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report a nickname").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            HStack {
                TextField("Nickname from the board", text: $reportName)
                    .autocorrectionDisabled()
                    .focused($focused)
                Button("Report") {
                    focused = false
                    let name = reportName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    Task {
                        reportStatus = await model.report(nickname: name) ? "Thanks. A human will look at it." : (model.errorMessage ?? "Could not send.")
                        reportName = ""
                    }
                }
                .buttonStyle(.bordered)
            }
            if let s = reportStatus { Text(s).font(.caption).foregroundColor(.secondary) }
        }
        .card()
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Text("No account, no ads, no tracking. A random player ID in your keychain is the only thing that ties your scores together. Your hypothesis notes are never shown to anyone.")
                .font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("Privacy policy", destination: URL(string: "https://turnstile.advancedfield.tech/privacy")!)
                    .font(.footnote)
                Spacer()
                Button("Delete my data", role: .destructive) { confirmDelete = true }.font(.footnote)
            }
        }
        .card()
    }
}
