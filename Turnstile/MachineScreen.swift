import SwiftUI

/// Playing one machine, from its judged rows to the verdict.
struct MachineScreen: View {
    @EnvironmentObject var store: GameStore
    let machineId: String

    @State private var slots: [Int?] = [nil, nil, nil]
    @State private var cursor = 0
    @State private var hunch = ""
    @State private var calls: [Bool?] = [nil, nil, nil, nil]
    @State private var working = false
    @State private var problem: String?
    @State private var lastAnswer: Bool?
    @State private var askLock = false
    @State private var building = false
    @State private var naming: NameReply?
    @State private var skippedNaming = false
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            if let m = store.machine(machineId) {
                VStack(alignment: .leading, spacing: 18) {
                    if let problem { NoticeBar(text: problem) }
                    lanes(m)
                    if !m.play.queries.isEmpty { triesSoFar(m) }
                    if m.play.isFinished {
                        finished(m)
                    } else if m.play.isCalling {
                        finalFour(m)
                    } else {
                        workbench(m)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            } else {
                ProgressView().tint(Palette.brand).frame(maxWidth: .infinity).padding(.top, 120)
            }
        }
        .background(Palette.ink.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(store.machine(machineId)?.title ?? "Machine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { typing = false }
            }
        }
        .sheet(isPresented: $building) {
            if let m = store.machine(machineId) {
                RuleBuilderView(tier: m.tier) { rule in
                    building = false
                    Task { await name(m, rule) }
                }
            }
        }
        .confirmationDialog("Ready for the final four?", isPresented: $askLock, titleVisibility: .visible) {
            Button("Show me the final four") { Task { await lock() } }
            Button("Keep trying rows", role: .cancel) {}
        } message: {
            Text("Tries cost you nothing. Once the final four appear you cannot try any more rows.")
        }
    }

    // MARK: What the machine has done

    private func lanes(_ m: Machine) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This machine follows a secret rule. Here is what it did with \(m.examples.count) rows.")
                .font(Typeface.small).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                lane("Accepted", rows: m.examples.filter { $0.accepted }, tint: Palette.pass)
                lane("Rejected", rows: m.examples.filter { !$0.accepted }, tint: Palette.stop)
            }
        }
        .slab()
    }

    private func lane(_ title: String, rows: [JudgedRow], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title).eyebrow()
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in TileStrip(row: r.seq, size: 34) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func triesSoFar(_ m: Machine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rows you tried").eyebrow()
            ForEach(Array(m.play.queries.enumerated()), id: \.offset) { i, q in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)").font(Typeface.tiny).foregroundColor(Palette.muted).frame(width: 14)
                    VStack(alignment: .leading, spacing: 4) {
                        TileStrip(row: q.seq, size: 30)
                        if let note = q.note, !note.isEmpty {
                            Text(note).font(Typeface.small).foregroundColor(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    VerdictMark(accepted: q.accepted, size: 28)
                }
            }
        }
        .slab()
    }

    // MARK: Trying rows

    private func workbench(_ m: Machine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Try a row").font(Typeface.heading).foregroundColor(Palette.text)
                Spacer()
                Text("\(m.triesLeft) of \(m.maxExperiments) left").font(Typeface.tiny).foregroundColor(Palette.muted)
            }
            Text("Pick three tiles and the machine will accept or reject the row. Choose one that could prove a hunch wrong.")
                .font(Typeface.small).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    Button {
                        cursor = i
                        Feedback.tick()
                    } label: {
                        if let t = slots[i] {
                            TileGlyph(tile: t, size: 60)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(cursor == i ? Palette.brand : Color.clear, lineWidth: 2.5))
                        } else {
                            OpenSlot(size: 60, armed: cursor == i)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Place \(i + 1): " + (slots[i].map { Tiles.spoken($0) } ?? "empty")))
                }
                Spacer()
                if let answer = lastAnswer {
                    VStack(spacing: 2) {
                        VerdictMark(accepted: answer, size: 34)
                        Text(answer ? "Accepted" : "Rejected").font(Typeface.tiny)
                            .foregroundColor(answer ? Palette.pass : Palette.stop)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }

            TilePicker { t in
                slots[cursor] = t
                if let next = (0..<3).first(where: { slots[$0] == nil }) { cursor = next }
                Feedback.tick()
            }

            HStack(spacing: 10) {
                Image(systemName: "lightbulb").foregroundColor(Palette.muted)
                TextField("Your hunch, only you see it", text: $hunch, axis: .vertical)
                    .font(Typeface.body)
                    .foregroundColor(Palette.text)
                    .lineLimit(1...3)
                    .focused($typing)
            }
            .padding(12)
            .background(Palette.slateHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task { await ask(m) }
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(Palette.ink) }
                    Text(working ? "Asking\u{2026}" : "Ask the machine")
                }
            }
            .buttonStyle(BrightButton())
            .disabled(working || slots.contains(where: { $0 == nil }) || m.triesLeft == 0)
            .opacity(slots.contains(where: { $0 == nil }) || m.triesLeft == 0 ? 0.5 : 1)

            HStack(spacing: 10) {
                Button("Clear row") {
                    slots = [nil, nil, nil]
                    cursor = 0
                }
                .buttonStyle(OutlineButton())
                .disabled(slots.allSatisfy { $0 == nil })
                Button {
                    if m.triesLeft > 0 { askLock = true } else { Task { await lock() } }
                } label: {
                    Text(m.triesLeft > 0 ? "I think I\u{2019}ve got it" : "Final four")
                }
                .buttonStyle(OutlineButton())
                .disabled(working)
            }
        }
        .slab()
    }

    // MARK: The final four

    private func finalFour(_ m: Machine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The final four").font(Typeface.heading).foregroundColor(Palette.text)
            Text("Which of these rows does the machine accept? Exactly two of them.")
                .font(Typeface.small).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array((m.play.tests ?? []).enumerated()), id: \.offset) { i, row in
                VStack(alignment: .leading, spacing: 10) {
                    TileStrip(row: row, size: 44)
                    HStack(spacing: 10) {
                        choice("Accept", chosen: calls[i] == true, tint: Palette.pass) { calls[i] = true }
                        choice("Reject", chosen: calls[i] == false, tint: Palette.stop) { calls[i] = false }
                    }
                }
                .padding(.vertical, 4)
            }
            Button {
                Task { await callIn(m) }
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(Palette.ink) }
                    Text(working ? "Checking\u{2026}" : "Lock in my answers")
                }
            }
            .buttonStyle(BrightButton())
            .disabled(working || calls.contains(where: { $0 == nil }))
            .opacity(calls.contains(where: { $0 == nil }) ? 0.5 : 1)
        }
        .slab()
    }

    private func choice(_ title: String, chosen: Bool, tint: Color, pick: @escaping () -> Void) -> some View {
        Button {
            pick()
            Feedback.tick()
        } label: {
            Text(title)
                .font(Typeface.label)
                .foregroundColor(chosen ? Palette.ink : Palette.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(chosen ? tint : Palette.slateHigh))
        }
        .buttonStyle(.plain)
    }

    // MARK: After answering

    @ViewBuilder private func finished(_ m: Machine) -> some View {
        VStack(spacing: 16) {
            ScoreRing(score: m.play.score ?? 0)
            if let tests = m.play.tests, let answers = m.play.answers, let v = store.verdicts[m.id] {
                VStack(spacing: 10) {
                    ForEach(Array(tests.enumerated()), id: \.offset) { i, row in
                        let known = i < v.truth.count && i < answers.count
                        let right = known && answers[i] == v.truth[i]
                        let actual: String = !known ? "" : (v.truth[i] ? "accepted" : "rejected")
                        HStack(spacing: 10) {
                            Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(right ? Palette.pass : Palette.stop)
                            TileStrip(row: row, size: 28)
                            Spacer()
                            Text(verbatim: actual)
                                .font(Typeface.tiny).foregroundColor(Palette.muted)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .slab()

        if let v = store.verdicts[m.id] {
            namingCard(m)
            VerdictView(verdict: v)
        } else {
            ProgressView().tint(Palette.brand).frame(maxWidth: .infinity)
                .task { await store.loadVerdict(m.id) }
        }
    }

    @ViewBuilder private func namingCard(_ m: Machine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let star = m.play.star {
                Text(star.hit ? "\u{2605} You named the rule" : "Not quite")
                    .font(Typeface.heading)
                    .foregroundColor(star.hit ? Palette.gold : Palette.text)
                if let rule = star.rule {
                    Text("You said: " + RulePhrasing.say(rule))
                        .font(Typeface.small).foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let miss = naming?.counterexample {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A row where your rule and the machine disagree:").font(Typeface.small).foregroundColor(Palette.muted)
                        HStack(spacing: 10) {
                            TileStrip(row: miss.seq, size: 28)
                            Text("machine \(miss.machine ? "accepts" : "rejects"), yours \(miss.yours ? "accepts" : "rejects")")
                                .font(Typeface.small).foregroundColor(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if skippedNaming {
                Text("You skipped naming the rule.").font(Typeface.small).foregroundColor(Palette.muted)
            } else {
                Text("Name the rule for a star").font(Typeface.heading).foregroundColor(Palette.text)
                Text("Build the rule you think it is. If it matches the machine on every possible row, you earn a star.")
                    .font(Typeface.small).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Build my rule") { building = true }.buttonStyle(BrightButton())
                    Button("No thanks") { skippedNaming = true }.buttonStyle(OutlineButton())
                }
            }
        }
        .slab()
    }

    // MARK: Moves

    private func ask(_ m: Machine) async {
        let row = slots.compactMap { $0 }
        guard row.count == 3 else { return }
        working = true; problem = nil
        defer { working = false }
        do {
            let accepted = try await store.tryRow(m.id, row: row, hunch: hunch)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lastAnswer = accepted }
            hunch = ""
            slots = [nil, nil, nil]
            cursor = 0
        } catch {
            problem = (error as? GateError)?.errorDescription
            if (error as? GateError)?.status == 409 { await store.loadDay() }
        }
    }

    private func lock() async {
        working = true; problem = nil
        defer { working = false }
        do { try await store.lock(machineId) } catch { problem = (error as? GateError)?.errorDescription }
    }

    private func callIn(_ m: Machine) async {
        let answers = calls.compactMap { $0 }
        guard answers.count == 4 else { return }
        working = true; problem = nil
        defer { working = false }
        do {
            _ = try await store.call(m.id, answers: answers)
        } catch {
            problem = (error as? GateError)?.errorDescription
            if (error as? GateError)?.status == 409 { await store.loadDay() }
        }
    }

    private func name(_ m: Machine, _ rule: RuleNode) async {
        working = true; problem = nil
        defer { working = false }
        do { naming = try await store.name(m.id, rule: rule) } catch { problem = (error as? GateError)?.errorDescription }
    }
}
