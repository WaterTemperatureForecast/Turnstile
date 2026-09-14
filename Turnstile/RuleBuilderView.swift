import SwiftUI

/// Put together the rule you believe in. The server compares what it MEANS
/// with the machine's rule on every possible row, so wording does not matter.
struct RuleBuilderView: View {
    let tier: Int
    let submit: (RuleNode) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var shape = Joiner.one
    @State private var first = Clause()
    @State private var second = Clause()

    enum Joiner: String, CaseIterable, Identifiable {
        case one, opposite, both, either, onlyOne
        var id: String { rawValue }
        var title: String {
            switch self {
            case .one: return "One thing is true"
            case .opposite: return "One thing is NOT true"
            case .both: return "Two things are both true"
            case .either: return "At least one of two things"
            case .onlyOne: return "One of two things, not both"
            }
        }
        var needsTwo: Bool { self == .both || self == .either || self == .onlyOne }
        var minimumLevel: Int {
            switch self {
            case .one, .opposite: return 1
            case .both, .either: return 2
            case .onlyOne: return 3
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What kind of rule?").eyebrow()
                        ForEach(Joiner.allCases.filter { $0.minimumLevel <= tier }) { j in
                            Button {
                                shape = j
                                Feedback.tick()
                            } label: {
                                HStack {
                                    Text(j.title).font(Typeface.body).foregroundColor(Palette.text)
                                    Spacer()
                                    Image(systemName: shape == j ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(shape == j ? Palette.brand : Palette.muted)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .slab()

                    ClauseEditor(heading: shape.needsTwo ? "The first thing" : "The thing it checks", clause: $first)
                    if shape.needsTwo {
                        ClauseEditor(heading: "The second thing", clause: $second)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your rule reads").eyebrow()
                        Text(RulePhrasing.say(built).sentenceCased + ".")
                            .font(Typeface.heading)
                            .foregroundColor(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .slab()

                    Button("Check my rule") { submit(built) }
                        .buttonStyle(BrightButton())
                }
                .padding(18)
            }
            .background(Palette.ink.ignoresSafeArea())
            .navigationTitle("Name the rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.ink, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var built: RuleNode {
        switch shape {
        case .one: return first.node
        case .opposite: return RuleNode(op: "not", a: first.node)
        case .both: return RuleNode(op: "and", a: first.node, b: second.node)
        case .either: return RuleNode(op: "or", a: first.node, b: second.node)
        case .onlyOne: return RuleNode(op: "xor", a: first.node, b: second.node)
        }
    }
}

/// One property of a row, as the player assembles it.
struct Clause {
    enum Kind: String, CaseIterable, Identifiable {
        case spot, howMany, pair, allSame, allDifferent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .spot: return "A tile in one spot"
            case .howMany: return "How many tiles"
            case .pair: return "Two tiles matching"
            case .allSame: return "All three the same"
            case .allDifferent: return "All three different"
            }
        }
    }

    var kind = Kind.spot
    var aboutShape = false
    var valueIndex = 0
    var spot = 1
    var count = 1
    var pair = 13

    var trait: String { aboutShape ? "shape" : "colour" }
    var value: String { aboutShape ? Tiles.shapes[valueIndex] : Tiles.colours[valueIndex] }

    var node: RuleNode {
        switch kind {
        case .spot: return RuleNode(op: "pos", attr: trait, value: value, i: spot)
        case .howMany: return RuleNode(op: "count", attr: trait, value: value, n: count)
        case .pair: return RuleNode(op: "same", attr: trait, i: pair / 10, j: pair % 10)
        case .allSame: return RuleNode(op: "allsame", attr: trait)
        case .allDifferent: return RuleNode(op: "alldiff", attr: trait)
        }
    }
}

struct ClauseEditor: View {
    let heading: String
    @Binding var clause: Clause

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading).eyebrow()

            Picker("About", selection: $clause.kind) {
                ForEach(Clause.Kind.allCases) { k in Text(k.title).tag(k) }
            }
            .pickerStyle(.menu)

            Picker("Colour or shape", selection: $clause.aboutShape) {
                Text("Colour").tag(false)
                Text("Shape").tag(true)
            }
            .pickerStyle(.segmented)

            if clause.kind == .spot || clause.kind == .howMany {
                Picker("Which", selection: $clause.valueIndex) {
                    ForEach(0..<3, id: \.self) { k in
                        Text((clause.aboutShape ? Tiles.shapes[k] : Tiles.colours[k]).sentenceCased).tag(k)
                    }
                }
                .pickerStyle(.segmented)
            }
            if clause.kind == .spot {
                Picker("Which tile", selection: $clause.spot) {
                    Text("1st").tag(1)
                    Text("2nd").tag(2)
                    Text("3rd").tag(3)
                }
                .pickerStyle(.segmented)
            }
            if clause.kind == .howMany {
                Picker("How many", selection: $clause.count) {
                    Text("none").tag(0)
                    Text("one").tag(1)
                    Text("two").tag(2)
                    Text("all three").tag(3)
                }
                .pickerStyle(.segmented)
            }
            if clause.kind == .pair {
                Picker("Which two", selection: $clause.pair) {
                    Text("1st & 2nd").tag(12)
                    Text("1st & 3rd").tag(13)
                    Text("2nd & 3rd").tag(23)
                }
                .pickerStyle(.segmented)
            }
        }
        .slab()
    }
}
