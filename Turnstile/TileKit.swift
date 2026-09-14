import SwiftUI

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// One tile: a bright shape on a dark tile.
struct TileGlyph: View {
    let tile: Int
    var size: CGFloat = 44

    var body: some View {
        let colour = Palette.tile(Tiles.colour(tile))
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Palette.slateHigh)
            shape(colour)
                .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(Tiles.spoken(tile)))
    }

    @ViewBuilder private func shape(_ colour: Color) -> some View {
        switch Tiles.shape(tile) {
        case "circle": Circle().fill(colour)
        case "square": RoundedRectangle(cornerRadius: size * 0.06, style: .continuous).fill(colour)
        default: TriangleShape().fill(colour)
        }
    }
}

/// Three tiles side by side.
struct TileStrip: View {
    let row: TileRow3
    var size: CGFloat = 40
    var body: some View {
        HStack(spacing: size * 0.14) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, t in TileGlyph(tile: t, size: size) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Tiles.spoken(row)))
    }
}

/// A tick for accepted, a cross for rejected.
struct VerdictMark: View {
    let accepted: Bool
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle().fill((accepted ? Palette.pass : Palette.stop).opacity(0.18))
            Image(systemName: accepted ? "checkmark" : "xmark")
                .font(.system(size: size * 0.5, weight: .black))
                .foregroundColor(accepted ? Palette.pass : Palette.stop)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(accepted ? "accepted" : "rejected"))
    }
}

/// An empty place in the row being built.
struct OpenSlot: View {
    var size: CGFloat = 60
    var armed = false
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .strokeBorder(armed ? Palette.brand : Palette.edge, style: StrokeStyle(lineWidth: armed ? 2.5 : 1.5, dash: armed ? [] : [6, 5]))
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Palette.slateHigh.opacity(0.4)))
            .frame(width: size, height: size)
    }
}

/// All nine tiles as a grid: shapes down, colours across. Easier to find a
/// tile than in a single strip, and it shows the game's two properties.
struct TilePicker: View {
    let pick: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { shape in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { colour in
                        let t = Tiles.make(shape: shape, colour: colour)
                        Button { pick(t) } label: {
                            TileGlyph(tile: t, size: 52)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Four segments, one per final row called correctly.
struct ScoreRing: View {
    let score: Int
    var outOf = 4
    var diameter: CGFloat = 132

    var body: some View {
        ZStack {
            ForEach(0..<outOf, id: \.self) { k in
                let start = Double(k) / Double(outOf) + 0.012
                let end = Double(k + 1) / Double(outOf) - 0.012
                Circle()
                    .trim(from: start, to: end)
                    .stroke(k < score ? Palette.brand : Palette.slateHigh, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(score)").font(Typeface.display(diameter * 0.36)).foregroundColor(Palette.text)
                Text("of \(outOf)").font(Typeface.tiny).foregroundColor(Palette.muted)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(score) of \(outOf)"))
    }
}

/// A small "AI" tag next to a machine builder's or player's name.
struct AITag: View {
    var body: some View {
        Text("AI")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(Palette.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Palette.brand, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel("AI player")
    }
}
