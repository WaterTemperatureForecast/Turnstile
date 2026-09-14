import SwiftUI
import UIKit

// Small shared pieces. Everything here is iOS 16-safe on purpose.

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.subheadline)
        .foregroundColor(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Tiles

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

enum TileColours {
    static func colour(_ name: String) -> Color {
        switch name {
        case "red": return Color(red: 0.86, green: 0.15, blue: 0.15)
        case "blue": return Color(red: 0.15, green: 0.39, blue: 0.93)
        default: return Color(red: 0.95, green: 0.72, blue: 0.05)
        }
    }
}

/// One tile: a coloured shape on a subtle tile background.
struct TileView: View {
    let tile: Int
    var size: CGFloat = 44
    var dimmed = false

    var body: some View {
        let colour = TileColours.colour(Tile.colour(tile)).opacity(dimmed ? 0.35 : 1)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
            Group {
                switch Tile.shape(tile) {
                case "circle": Circle().fill(colour)
                case "square": RoundedRectangle(cornerRadius: size * 0.08, style: .continuous).fill(colour)
                default: Triangle().fill(colour)
                }
            }
            .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(Tile.label(tile)))
    }
}

/// An empty slot in the experiment builder.
struct EmptyTile: View {
    var size: CGFloat = 44
    var selected = false
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, dash: selected ? [] : [5, 4]))
            .frame(width: size, height: size)
    }
}

struct SequenceView: View {
    let seq: Seq
    var size: CGFloat = 40
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(seq.enumerated()), id: \.offset) { _, t in
                TileView(tile: t, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Tile.label(seq)))
    }
}

struct VerdictBadge: View {
    let accepted: Bool
    var compact = false
    var body: some View {
        // Two label styles are different types, so branch instead of a ternary.
        Group {
            if compact {
                label.labelStyle(.iconOnly)
            } else {
                label.labelStyle(.titleAndIcon)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(accepted ? .green : .red)
        .accessibilityLabel(Text(accepted ? "accepted" : "rejected"))
    }

    private var label: some View {
        Label(accepted ? "Accept" : "Reject", systemImage: accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
    }
}

struct ExampleRow: View {
    let seq: Seq
    let accepted: Bool
    var note: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SequenceView(seq: seq)
                Spacer()
                VerdictBadge(accepted: accepted)
            }
            if let note, !note.isEmpty {
                Text(note).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct KindBadge: View {
    let isAgent: Bool
    var body: some View {
        if isAgent {
            Label("AI", systemImage: "cpu")
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityLabel("AI agent")
        }
    }
}

struct BigNumber: View {
    let value: Int
    let of: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("/\(of)")
                .font(.title2.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// "Closes in 5h 12m" from an ISO close time; re-renders every minute.
struct Countdown: View {
    let closesAt: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(text(at: context.date))
        }
    }

    private func text(at now: Date) -> String {
        guard let end = UTCDay.iso(closesAt) else { return "" }
        let secs = Int(end.timeIntervalSince(now))
        if secs <= 0 { return "Round closing now" }
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "Closes in \(h)h \(m)m" }
        return "Closes in \(m)m"
    }
}

// MARK: - Rule text and meaning (mirrors worker/src/rules.ts)

/// Evaluates a rule on one row of three tiles. Only used so the rule builder
/// can preview wording exactly as the server would word it.
enum RuleEval {
    static func matches(_ r: Rule, _ seq: Seq) -> Bool {
        switch r.op {
        case "not": return !(r.a.map { matches($0.rule, seq) } ?? false)
        case "and": return (r.a.map { matches($0.rule, seq) } ?? false) && (r.b.map { matches($0.rule, seq) } ?? false)
        case "or": return (r.a.map { matches($0.rule, seq) } ?? false) || (r.b.map { matches($0.rule, seq) } ?? false)
        case "xor": return (r.a.map { matches($0.rule, seq) } ?? false) != (r.b.map { matches($0.rule, seq) } ?? false)
        default: break
        }
        let values = seq.map { r.attr == "shape" ? Tile.shape($0) : Tile.colour($0) }
        guard values.count == 3 else { return false }
        switch r.op {
        case "pos": return values[max(0, min(2, (r.i ?? 1) - 1))] == (r.value ?? "")
        case "count": return values.filter { $0 == (r.value ?? "") }.count == (r.n ?? 0)
        case "same": return values[max(0, min(2, (r.i ?? 1) - 1))] == values[max(0, min(2, (r.j ?? 2) - 1))]
        case "allsame": return Set(values).count == 1
        case "alldiff": return Set(values).count == 3
        default: return false
        }
    }

    /// Every possible row, for comparing two rules.
    static let allRows: [Seq] = (0..<9).flatMap { a in (0..<9).flatMap { b in (0..<9).map { c in [a, b, c] } } }
}

enum RuleText {
    private static let pos = ["", "first", "second", "third"]
    private static let num = ["no", "one", "two", "three"]

    /// "red tile"/"red tiles" for a colour, "triangle"/"triangles" for a shape.
    private static func things(_ attr: String, _ value: String, plural: Bool) -> String {
        let one = attr == "colour" ? "\(value) tile" : value
        return plural ? one + "s" : one
    }

    /// One property in plain English, negated if asked.
    private static func property(_ r: Rule, not: Bool) -> String {
        let attr = r.attr ?? "colour"
        let value = r.value ?? ""
        switch r.op {
        case "pos":
            let where_ = "the \(pos[max(1, min(3, r.i ?? 1))]) tile is\(not ? " not" : "")"
            return attr == "colour" ? "\(where_) \(value)" : "\(where_) a \(value)"
        case "count":
            let n = max(0, min(3, r.n ?? 0))
            if !not {
                if n == 0 { return "there are no \(things(attr, value, plural: true))" }
                if n == 3 { return attr == "colour" ? "all three tiles are \(value)" : "all three tiles are \(value)s" }
                return "there \(n == 1 ? "is" : "are") exactly \(num[n]) \(things(attr, value, plural: n != 1))"
            }
            if n == 0 { return "there is at least one \(things(attr, value, plural: false))" }
            if n == 3 { return "the three tiles are not all \(things(attr, value, plural: true))" }
            return "there \(n == 1 ? "is" : "are") not exactly \(num[n]) \(things(attr, value, plural: n != 1))"
        case "same":
            let pair = "the \(pos[max(1, min(3, r.i ?? 1))]) and \(pos[max(1, min(3, r.j ?? 2))]) tiles are"
            return not ? "\(pair) different \(attr)s" : "\(pair) the same \(attr)"
        case "allsame":
            return not ? "the three tiles are not all the same \(attr)" : "all three tiles are the same \(attr)"
        case "alldiff":
            return not ? "at least two tiles share a \(attr)" : "all three \(attr)s are different"
        default:
            return describe(r)
        }
    }

    static func describe(_ r: Rule) -> String {
        switch r.op {
        case "not":
            return r.a.map { property($0.rule, not: true) } ?? "…"
        case "and":
            return (r.a.map { property($0.rule, not: false) } ?? "…") + " and " + (r.b.map { property($0.rule, not: false) } ?? "…")
        case "or":
            let a = r.a.map { property($0.rule, not: false) } ?? "…"
            let b = r.b.map { property($0.rule, not: false) } ?? "…"
            // "or both" only helps when both halves can actually hold at once.
            let overlap: Bool = {
                guard let x = r.a?.rule, let y = r.b?.rule else { return true }
                return RuleEval.allRows.contains { RuleEval.matches(x, $0) && RuleEval.matches(y, $0) }
            }()
            return a + ", or " + b + (overlap ? ", or both" : "")
        case "xor":
            return (r.a.map { property($0.rule, not: false) } ?? "…") + ", or "
                + (r.b.map { property($0.rule, not: false) } ?? "…") + ", but not both"
        default:
            return property(r, not: false)
        }
    }
}
