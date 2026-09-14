import SwiftUI
import UIKit

/// Turnstile's look: a dark, high-contrast board with bright tiles, so the
/// pieces of the puzzle are always the brightest thing on the screen.
enum Palette {
    static let ink = Color(red: 0.043, green: 0.071, blue: 0.082)        // background
    static let slate = Color(red: 0.078, green: 0.114, blue: 0.129)      // raised surfaces
    static let slateHigh = Color(red: 0.118, green: 0.161, blue: 0.180)  // inputs, empty slots
    static let edge = Color.white.opacity(0.08)
    static let text = Color(red: 0.918, green: 0.949, blue: 0.945)
    static let muted = Color(red: 0.561, green: 0.639, blue: 0.651)
    static let brand = Color(red: 0.176, green: 0.831, blue: 0.749)
    static let pass = Color(red: 0.204, green: 0.827, blue: 0.600)
    static let stop = Color(red: 0.973, green: 0.443, blue: 0.443)
    static let gold = Color(red: 0.980, green: 0.800, blue: 0.082)

    static func tile(_ colourName: String) -> Color {
        switch colourName {
        case "red": return Color(red: 0.937, green: 0.267, blue: 0.267)
        case "blue": return Color(red: 0.231, green: 0.510, blue: 0.965)
        default: return Color(red: 0.980, green: 0.800, blue: 0.082)
        }
    }
}

enum Typeface {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static let heading = Font.system(.title3, design: .rounded).weight(.bold)
    static let label = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .default)
    static let small = Font.system(.footnote, design: .default)
    static let tiny = Font.system(.caption, design: .rounded).weight(.semibold)
}

/// A raised surface on the dark board.
struct Slab: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.slate, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.edge, lineWidth: 1))
    }
}

extension View {
    func slab(padding: CGFloat = 18) -> some View { modifier(Slab(padding: padding)) }

    /// Small uppercase tracking label used above sections.
    func eyebrow() -> some View {
        self.font(Typeface.tiny).textCase(.uppercase).tracking(1.2).foregroundColor(Palette.muted)
    }
}

/// The main call to action: a wide bright capsule.
struct BrightButton: ButtonStyle {
    var tint: Color = Palette.brand
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.label)
            .foregroundColor(Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(tint.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

/// A secondary action: an outlined capsule.
struct OutlineButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.label)
            .foregroundColor(Palette.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Capsule().fill(Palette.slateHigh.opacity(configuration.isPressed ? 1 : 0.6)))
            .overlay(Capsule().stroke(Palette.edge, lineWidth: 1))
    }
}

/// A one-line message that sits at the top of a screen.
struct NoticeBar: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(Palette.stop)
            Text(text).font(Typeface.small).foregroundColor(Palette.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.stop.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// "New machines in 5h 12m", ticking once a minute.
struct ResetClock: View {
    let endsAt: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(label(at: context.date))
        }
    }

    private func label(at now: Date) -> String {
        guard let end = GameCalendar.instant(endsAt) else { return "" }
        let seconds = Int(end.timeIntervalSince(now))
        if seconds <= 0 { return "New machines any moment" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "New machines in \(hours)h \(minutes)m" : "New machines in \(minutes)m"
    }
}

enum Feedback {
    static func good() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func bad() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}
