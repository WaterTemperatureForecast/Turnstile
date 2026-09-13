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

// MARK: - Rule text (mirrors worker/src/rules.ts describe())

enum RuleText {
    static func describe(_ r: Rule) -> String {
        let pos = ["", "first", "second", "third"]
        switch r.op {
        case "pos":
            let i = pos[max(0, min(3, r.i ?? 1))]
            return r.attr == "colour" ? "the \(i) tile is \(r.value ?? "")" : "the \(i) tile is a \(r.value ?? "")"
        case "count":
            let n = r.n ?? 0
            if r.attr == "colour" { return "exactly \(n) tile\(n != 1 ? "s" : "") \(n != 1 ? "are" : "is") \(r.value ?? "")" }
            return "there \(n != 1 ? "are" : "is") exactly \(n) \(r.value ?? "")\(n != 1 ? "s" : "")"
        case "same":
            return "the \(pos[max(0, min(3, r.i ?? 1))]) and \(pos[max(0, min(3, r.j ?? 2))]) tiles have the same \(r.attr ?? "")"
        case "allsame": return "all three tiles have the same \(r.attr ?? "")"
        case "alldiff": return "all three \(r.attr ?? "")s are different"
        case "not": return "NOT (" + (r.a.map { describe($0.rule) } ?? "…") + ")"
        default:
            let a = r.a.map { describe($0.rule) } ?? "…"
            let b = r.b.map { describe($0.rule) } ?? "…"
            return "(\(a)) \(r.op.uppercased()) (\(b))"
        }
    }
}
