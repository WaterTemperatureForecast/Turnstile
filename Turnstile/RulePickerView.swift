import SwiftUI

/// Builds a rule AST from the published vocabulary. The server compares it to
/// the machine's rule on all 729 inputs; syntax does not matter, meaning does.
struct RulePickerView: View {
    let tier: Int
    let onSubmit: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = "single"          // single | not | and | or | xor
    @State private var a = AtomDraft()
    @State private var b = AtomDraft()

    private var forms: [(String, String)] {
        var f = [("single", "One property"), ("not", "NOT a property")]
        if tier >= 2 { f += [("and", "A AND B"), ("or", "A OR B")] }
        if tier >= 3 { f.append(("xor", "A XOR B")) }
        return f
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Form") {
                    Picker("Form", selection: $form) {
                        ForEach(forms, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.menu)
                }
                Section(form == "single" || form == "not" ? "Property" : "Property A") {
                    AtomEditor(draft: $a)
                }
                if form == "and" || form == "or" || form == "xor" {
                    Section("Property B") {
                        AtomEditor(draft: $b)
                    }
                }
                Section("Your rule") {
                    Text(RuleText.describe(rule).capitalizedFirst)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Name the rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Check") { onSubmit(rule) }.fontWeight(.semibold) }
            }
        }
    }

    private var rule: Rule {
        switch form {
        case "not": return Rule(op: "not", a: a.rule)
        case "and", "or", "xor": return Rule(op: form, a: a.rule, b: b.rule)
        default: return a.rule
        }
    }
}

struct AtomDraft {
    var kind = "pos"          // pos | count | same | allsame | alldiff
    var attr = "colour"
    var value = "red"
    var i = 1
    var j = 3
    var n = 1

    var rule: Rule {
        switch kind {
        case "count": return Rule(op: "count", attr: attr, value: value, n: n)
        case "same": return Rule(op: "same", attr: attr, i: i, j: j)   // the picker only offers 1&2, 1&3, 2&3
        case "allsame": return Rule(op: "allsame", attr: attr)
        case "alldiff": return Rule(op: "alldiff", attr: attr)
        default: return Rule(op: "pos", attr: attr, value: value, i: i)
        }
    }
}

struct AtomEditor: View {
    @Binding var draft: AtomDraft

    var body: some View {
        Picker("Kind", selection: $draft.kind) {
            Text("Position has…").tag("pos")
            Text("Exactly N tiles are…").tag("count")
            Text("Two positions match").tag("same")
            Text("All three the same").tag("allsame")
            Text("All three different").tag("alldiff")
        }
        .pickerStyle(.menu)
        Picker("Attribute", selection: $draft.attr) {
            Text("Colour").tag("colour")
            Text("Shape").tag("shape")
        }
        .pickerStyle(.segmented)
        .onChange(of: draft.attr) { attr in
            let values = attr == "shape" ? Tile.shapes : Tile.colours
            if !values.contains(draft.value) { draft.value = values[0] }
        }
        if draft.kind == "pos" || draft.kind == "count" {
            Picker("Value", selection: $draft.value) {
                ForEach(draft.attr == "shape" ? Tile.shapes : Tile.colours, id: \.self) { Text($0.capitalizedFirst).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        if draft.kind == "pos" {
            Picker("Position", selection: $draft.i) {
                Text("1st").tag(1); Text("2nd").tag(2); Text("3rd").tag(3)
            }
            .pickerStyle(.segmented)
        }
        if draft.kind == "count" {
            Picker("How many", selection: $draft.n) {
                Text("0").tag(0); Text("1").tag(1); Text("2").tag(2); Text("3").tag(3)
            }
            .pickerStyle(.segmented)
        }
        if draft.kind == "same" {
            Picker("Positions", selection: Binding(
                get: { draft.i * 10 + draft.j },
                set: { draft.i = $0 / 10; draft.j = $0 % 10 }
            )) {
                Text("1 & 2").tag(12); Text("1 & 3").tag(13); Text("2 & 3").tag(23)
            }
            .pickerStyle(.segmented)
        }
    }
}
