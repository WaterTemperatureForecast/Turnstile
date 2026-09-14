import SwiftUI

/// The play screen for one machine: examples, experiments, tests, answer, reveal.
struct MachineView: View {
    @EnvironmentObject var model: AppModel
    let machineId: String

    @State private var slots: [Int?] = [nil, nil, nil]
    @State private var activeSlot = 0
    @State private var note = ""
    @State private var picks: [Bool?] = [nil, nil, nil, nil]
    @State private var busy = false
    @State private var message: String?
    @State private var lastVerdict: Bool?
    @State private var showPicker = false
    @State private var starResult: StarResponse?
    @State private var confirmTests = false
    @State private var skipped = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollView {
            if let m = model.machine(machineId) {
                VStack(spacing: 16) {
                    if let message { ErrorBanner(message: message) }
                    examples(m)
                    experiments(m)
                    switch m.play.phase {
                    case "experiments": builder(m)
                    case "tests": classify(m)
                    default: answered(m)
                    }
                }
                .padding()
            } else {
                ProgressView().padding(40)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(model.machine(machineId).map { $0.setter.kind == "agent" ? "\($0.setter.name)'s machine" : "House machine" } ?? "Machine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { noteFocused = false }
            }
        }
        .sheet(isPresented: $showPicker) {
            if let m = model.machine(machineId) {
                RulePickerView(tier: m.tier) { rule in
                    showPicker = false
                    Task { await submitStar(m, rule) }
                }
            }
        }
        .confirmationDialog("Ready for the final four?", isPresented: $confirmTests, titleVisibility: .visible) {
            Button("Show me the final four") { Task { await showTests() } }
            Button("Keep trying rows", role: .cancel) {}
        } message: {
            Text("You still have tries left, and they cost you nothing. Once the final four are shown you cannot try any more rows.")
        }
    }

    // MARK: Sections

    private func examples(_ m: Machine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This machine follows a secret rule. It accepted these rows and rejected these.")
                .font(.subheadline).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(m.examples.enumerated()), id: \.offset) { _, ex in
                ExampleRow(seq: ex.seq, accepted: ex.accepted)
            }
        }
        .card()
    }

    @ViewBuilder private func experiments(_ m: Machine) -> some View {
        if !m.play.queries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rows you tried").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                ForEach(Array(m.play.queries.enumerated()), id: \.offset) { i, q in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 18, height: 18)
                            .background(Circle().fill(Color.accentColor.opacity(0.15)))
                        ExampleRow(seq: q.seq, accepted: q.accepted, note: q.note)
                    }
                }
            }
            .card()
        }
    }

    private func builder(_ m: Machine) -> some View {
        let used = m.play.queries.count
        let left = m.max_experiments - used
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your turn (\(used + 1) of \(m.max_experiments))").font(.headline)
                Spacer()
                if let v = lastVerdict {
                    VerdictBadge(accepted: v).transition(.opacity)
                }
            }
            Text("Build a row of three tiles and the machine will accept it or reject it. Try a row that would prove one of your hunches wrong.")
                .font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Button {
                        activeSlot = i
                        Haptics.tap()
                    } label: {
                        if let t = slots[i] {
                            TileView(tile: t, size: 56)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(activeSlot == i ? Color.accentColor : .clear, lineWidth: 2.5))
                        } else {
                            EmptyTile(size: 56, selected: activeSlot == i)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Position \(i + 1)" + (slots[i].map { ": " + Tile.label($0) } ?? ", empty")))
                }
                Spacer()
                Button {
                    slots = [nil, nil, nil]; activeSlot = 0
                } label: { Image(systemName: "arrow.counterclockwise") }
                .disabled(slots.allSatisfy { $0 == nil })
                .accessibilityLabel("Clear")
            }
            palette
            HStack {
                Image(systemName: "lightbulb").foregroundColor(.secondary)
                TextField("Your hunch, just for you (optional)", text: $note, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
                    .focused($noteFocused)
            }
            .padding(10)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                Task { await runExperiment(m) }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? "Asking…" : "Ask the machine").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || slots.contains(nil) || left == 0)
            Button {
                if left > 0 { confirmTests = true } else { Task { await showTests() } }
            } label: {
                Text(left > 0 ? "I think I've got it" : "Show me the final four")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(busy)
        }
        .card()
    }

    private var palette: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 9), spacing: 8) {
            ForEach(0..<9, id: \.self) { t in
                Button {
                    slots[activeSlot] = t
                    if activeSlot < 2 { activeSlot += 1 }
                    Haptics.tap()
                } label: {
                    TileView(tile: t, size: 34)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func classify(_ m: Machine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The final four").font(.headline)
            Text("Which of these rows does the machine accept? Exactly two of them. Call all four, then lock in.")
                .font(.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array((m.play.tests ?? []).enumerated()), id: \.offset) { i, seq in
                HStack {
                    Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 18)
                    SequenceView(seq: seq)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { picks[i].map { $0 ? 1 : 0 } ?? -1 },
                        set: { picks[i] = $0 == -1 ? nil : $0 == 1 }
                    )) {
                        Text("Accept").tag(1)
                        Text("Reject").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }
            Button {
                Task { await submitAnswers(m) }
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? "Checking…" : "Lock in my answers").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || picks.contains(nil))
        }
        .card()
    }

    @ViewBuilder private func answered(_ m: Machine) -> some View {
        VStack(spacing: 8) {
            Text("Your score").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            BigNumber(value: m.play.score ?? 0, of: 4)
            if let tests = m.play.tests, let answers = m.play.answers, let rv = model.reveals[m.id] {
                VStack(spacing: 6) {
                    ForEach(Array(tests.enumerated()), id: \.offset) { i, seq in
                        HStack {
                            Image(systemName: answers[i] == rv.truth[i] ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(answers[i] == rv.truth[i] ? .green : .red)
                            SequenceView(seq: seq, size: 28)
                            Spacer()
                            Text("you said \(answers[i] ? "accept" : "reject")").font(.caption).foregroundColor(.secondary)
                            VerdictBadge(accepted: rv.truth[i], compact: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .card()

        if let rv = model.reveals[m.id] {
            starCard(m, rv)
            RevealView(reveal: rv)
        } else {
            ProgressView().task { await model.loadReveal(m.id) }
        }
    }

    @ViewBuilder private func starCard(_ m: Machine, _ rv: Reveal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let star = m.play.star {
                HStack {
                    Text(star.hit ? "★ You named the rule" : "No star this time").font(.headline)
                    Spacer()
                }
                if let r = star.rule {
                    Text("You said: \(RuleText.describe(r))").font(.subheadline).foregroundColor(.secondary)
                }
                if let sr = starResult, let ce = sr.counterexample {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Here is a row where your rule and the machine disagree:")
                            .font(.caption).foregroundColor(.secondary)
                        HStack {
                            SequenceView(seq: ce.seq, size: 24)
                            Text("the machine \(ce.machine ? "accepts" : "rejects") it, yours \(ce.yours ? "accepts" : "rejects") it")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if skipped {
                Text("You skipped naming the rule.").font(.subheadline).foregroundColor(.secondary)
            } else {
                Text("Name the rule for a star").font(.headline)
                Text("Optional. Build the rule you think it is. If it behaves exactly like the machine on every possible row, you get a star.")
                    .font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Build my rule") { showPicker = true }.buttonStyle(.borderedProminent)
                    Button("No thanks") { Task { await skipStar(m) } }.buttonStyle(.bordered)
                }
            }
        }
        .card()
    }

    // MARK: Actions

    private func runExperiment(_ m: Machine) async {
        guard !slots.contains(nil) else { return }
        busy = true; message = nil
        defer { busy = false }
        let seq = slots.compactMap { $0 }
        do {
            let accepted = try await model.experiment(m.id, seq: seq, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            withAnimation { lastVerdict = accepted }
            note = ""
            slots = [nil, nil, nil]; activeSlot = 0
        } catch {
            message = model.describe(error)
            if (error as? APIFailure)?.status == 409 { await model.refresh() }
        }
    }

    private func showTests() async {
        busy = true; message = nil
        defer { busy = false }
        do { try await model.showTests(machineId) } catch { message = model.describe(error) }
    }

    private func submitAnswers(_ m: Machine) async {
        guard !picks.contains(nil) else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            _ = try await model.answer(m.id, answers: picks.compactMap { $0 })
        } catch {
            message = model.describe(error)
            if (error as? APIFailure)?.status == 409 { await model.refresh() }
        }
    }

    private func submitStar(_ m: Machine, _ rule: Rule) async {
        busy = true; message = nil
        defer { busy = false }
        do { starResult = try await model.star(m.id, rule: rule) } catch { message = model.describe(error) }
    }

    /// Skipping only hides the offer; the rule is already shown in the reveal below.
    private func skipStar(_ m: Machine) async {
        showPicker = false
        withAnimation { skipped = true }
    }
}
