import SwiftUI
import AppKit

/// An original pixel mage drawn from a character map, so it scales crisply at any size.
enum MageSprite {
    private static let base = [
        "........kk......",
        ".......khsk.....",
        "......khhhhk....",
        ".....khhhhhhk...",
        "....khhhhhhhhk..",
        "..kkkkkkkkkkkkk.",
        "..kHHHHHHHHHHHk.",
        "...kffffffffk...",
        "..kffffffffffk..",
        "..kffweffweffk..",
        "..kffeeffeeffk..",
        "..kfccffffccfk..",
        "..kffffmmffffk..",
        "...kffffffffk...",
        "....kkbbbbkk....",
        "...kbbbbsbbbk...",
        "..kbbbbbbbbbbk..",
        "..kkkkkkkkkkkk..",
    ]

    private static let palette: [Character: Color] = [
        "k": Color(hex: 0x050B24),
        "h": Color(hex: 0x2E64D8),
        "H": Color(hex: 0x8FE9FF),
        "s": Theme.ice,
        "f": Color(hex: 0xF5A27A),
        "w": .white,
        "e": Color(hex: 0x1A3A7A),
        "c": Color(hex: 0xFF7EB6),
        "m": Color(hex: 0x7A2E3A),
        "o": Color(hex: 0xFF9AA8),
        "b": Color(hex: 0x123070),
    ]

    static func frame(blink: Bool, talking: Bool) -> [String] {
        var rows = base
        if blink {
            rows[9] = "..kffffffffffk.."
            rows[10] = "..kffkkffkkffk.."
        }
        if talking {
            rows[12] = "..kfffkmmkfffk.."
            rows[13] = "...kfffoofffk..."
        }
        return rows
    }

    static func draw(_ rows: [String], in context: GraphicsContext, size: CGSize) {
        let columns = rows.map(\.count).max() ?? 1
        let pixel = floor(min(size.width / CGFloat(columns), size.height / CGFloat(rows.count)))
        let origin = CGPoint(x: (size.width - pixel * CGFloat(columns)) / 2, y: (size.height - pixel * CGFloat(rows.count)) / 2)
        for (y, row) in rows.enumerated() {
            for (x, char) in row.enumerated() {
                guard let color = palette[char] else { continue }
                let rect = CGRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel, width: pixel, height: pixel)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

enum Mood {
    case idle, thinking, talking, worried

    /// Expression codes in the sprite pack: F01 soft smile, F02 focused, F00 neutral, F06 sad.
    var face: String {
        switch self {
        case .idle: "F01"
        case .thinking: "F02"
        case .talking: "F00"
        case .worried: "F06"
        }
    }
}

struct Portrait: View {
    var mood: Mood
    var outfit: Int

    /// Head-and-shoulders region of the 2048×2048 sprite canvas.
    private static let bust = CGRect(x: 420, y: 680, width: 1160, height: 1368)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let blinkPhase = t.truncatingRemainder(dividingBy: 4.2)
            let eyes = blinkPhase < 0.06 ? 2 : blinkPhase < 0.14 ? 3 : blinkPhase < 0.2 ? 2 : 1
            let mouth = mood == .talking ? [1, 2, 3, 2][Int(t * 10) % 4] : 1
            let bob = mood == .thinking ? CGFloat(Int(t * 4) % 2) * -3 : 0

            ZStack(alignment: .topTrailing) {
                ZStack {
                    Slant(amount: 36)
                        .fill(LinearGradient(colors: [Theme.cyan.opacity(0.45), Theme.ice.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        .padding(.vertical, 10)
                    Theme.cyan.opacity(0.55)
                        .mask(sprite(eyes: eyes, mouth: mouth))
                        .offset(x: 8, y: 6)
                    sprite(eyes: eyes, mouth: mouth)
                }
                .offset(y: bob)
                if mood == .thinking {
                    Text(String(repeating: ".", count: Int(t * 3) % 3 + 1))
                        .font(Theme.ui(18, weight: .black))
                        .foregroundStyle(Theme.navy)
                        .frame(width: 40, height: 22, alignment: .leading)
                        .padding(.leading, 10)
                        .background(Slant(amount: 8).fill(Theme.ice))
                }
            }
        }
    }

    @ViewBuilder
    private func sprite(eyes: Int, mouth: Int) -> some View {
        if let pack = SpritePack.installed {
            let layers = pack.layers(outfit: outfit, face: mood.face, eyes: eyes, mouth: mouth)
            Canvas { context, size in
                let scale = min(size.width / Self.bust.width, size.height / Self.bust.height)
                for layer in layers {
                    let rect = CGRect(x: (layer.origin.x - Self.bust.minX) * scale, y: (layer.origin.y - Self.bust.minY) * scale,
                                      width: layer.size.width * scale, height: layer.size.height * scale)
                    context.draw(Image(nsImage: layer.image), in: rect)
                }
            }
        } else {
            Canvas { context, size in
                MageSprite.draw(MageSprite.frame(blink: eyes == 3, talking: mouth > 1), in: context, size: size)
            }
        }
    }
}
