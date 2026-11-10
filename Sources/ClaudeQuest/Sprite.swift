import SwiftUI
import AppKit

enum Mood: String, CaseIterable {
    case idle, thinking, talking, worried
}

/// Original pixel-art party members drawn from character maps, so they scale crisply at any size.
/// Faces are drawn over the map, so every character keeps its face in the same place.
struct PixelSprite {
    var name: String
    var rows: [String]
    var colors: [Character: UInt32]
    /// Cloth and cloth-shadow colours; each session's outfit picks one pair.
    var outfits: [(UInt32, UInt32)]

    static func of(_ model: ClaudeModel) -> PixelSprite {
        switch model {
        case .opus: mage
        case .sonnet: bard
        case .haiku: ranger
        }
    }

    func draw(mood: Mood, blink: Bool, mouthOpen: Bool, outfit: Int, in context: GraphicsContext, size: CGSize) {
        let cloth = outfits[outfit % outfits.count]
        let palette = Self.skin.merging(colors) { $1 }.merging(["a": cloth.0, "A": cloth.1]) { $1 }
        let pixels = frame(mood: mood, blink: blink, mouthOpen: mouthOpen)
        let pixel = floor(min(size.width / CGFloat(pixels[0].count), size.height / CGFloat(pixels.count)))
        let origin = CGPoint(x: (size.width - pixel * CGFloat(pixels[0].count)) / 2, y: size.height - pixel * CGFloat(pixels.count))
        for (y, row) in pixels.enumerated() {
            for (x, char) in row.enumerated() {
                guard let color = palette[char] else { continue }
                let rect = CGRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel, width: pixel, height: pixel)
                context.fill(Path(rect), with: .color(Color(hex: color)))
            }
        }
    }

    private func frame(mood: Mood, blink: Bool, mouthOpen: Bool) -> [[Character]] {
        var pixels = rows.map(Array.init)
        for feature in Self.features(mood: mood, blink: blink, mouthOpen: mouthOpen) {
            for (row, column, text) in feature {
                for (offset, char) in text.enumerated() where char != "." {
                    pixels[row][column + offset] = char
                }
            }
        }
        return pixels
    }

    private typealias Feature = [(row: Int, column: Int, pixels: String)]

    private static func features(mood: Mood, blink: Bool, mouthOpen: Bool) -> [Feature] {
        let eyes = blink ? closedEyes : mood == .thinking ? focusedEyes : openEyes
        switch mood {
        case .idle: return [eyes, cheeks, smile]
        case .thinking: return [eyes, closedMouth]
        case .talking: return [eyes, cheeks, mouthOpen ? openMouth : closedMouth]
        case .worried: return [eyes, worriedBrows, frown, sweat]
        }
    }

    private static let openEyes: Feature = [(15, 10, "kk"), (16, 10, "we"), (17, 10, "ee"), (15, 20, "kk"), (16, 20, "we"), (17, 20, "ee")]
    private static let closedEyes: Feature = [(17, 10, "kk"), (17, 20, "kk")]
    private static let focusedEyes: Feature = [(16, 10, "kk"), (17, 10, "ee"), (16, 20, "kk"), (17, 20, "ee")]
    private static let worriedBrows: Feature = [(14, 11, "k"), (15, 9, "k"), (14, 20, "k"), (15, 22, "k")]
    private static let cheeks: Feature = [(18, 8, "cc"), (18, 22, "cc")]
    private static let smile: Feature = [(20, 14, "m..m"), (21, 15, "mm")]
    private static let closedMouth: Feature = [(20, 15, "mm")]
    private static let openMouth: Feature = [(20, 15, "mm"), (21, 15, "oo")]
    private static let frown: Feature = [(20, 15, "mm"), (21, 14, "m..m")]
    private static let sweat: Feature = [(12, 24, "d"), (13, 23, "ddd"), (14, 23, "ddd")]

    private static let skin: [Character: UInt32] = [
        "k": 0x050B24, "f": 0xF5C09A, "F": 0xD8946E, "w": 0xFFFFFF, "e": 0x1A2A5A,
        "c": 0xFF8FA8, "m": 0x7A2E3A, "o": 0xE0606E, "d": 0x9FE8FF,
    ]

    static let mage = PixelSprite(
        name: "Pixel mage",
        rows: [
            "....................kk..........",
            "...................kaak.........",
            "..................kaaAk.........",
            ".................kaaaAk.........",
            "................kaaaaAk.........",
            "...............kaaaaaAAk........",
            "..............kaaasaaaAk........",
            ".............kaaasssaaAAk.......",
            "............kaaaaasaaaaAk.......",
            "........kkkkttttttttttttkk......",
            "....kkkkaaaaTTTTTTTTTTTTaakk....",
            "...kAAAAAAAAAAAAAAAAAAAAAAAAk...",
            "....kkkkkkkkkkkkkkkkkkkkkkkk....",
            "....khhkhhffffffffffffhhkhhk....",
            "....khhkhffffffffffffffhkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khHkffffffffffffffffkHhk....",
            "....khHkkFffffffffffffFkkHhk....",
            "....khHk.kFFffffffffFFk.kHhk....",
            "....khHk..kkFFffffFFkk..kHhk....",
            "....kHHk....kkFFFFkk....kHHk....",
            "....kkkkkaaaakttttkaaaakkkkk....",
            "...kaaaaaaaaakttttkaaaaaaaaak...",
            "..kaaaaaaaAAAAkttkAAAAaaaaaaak..",
            ".kaaaaaaaAAAAAAkkAAAAAAaaaaaaak.",
            ".kaaaaaaAAAAAAAssAAAAAAAaaaaaak.",
            ".kaaaaaaAAAAAAAttAAAAAAAaaaaaak.",
            ".kaaaaaaAAAAAAAAAAAAAAAAaaaaaak.",
            ".kaaaaaaAAAAAAAAAAAAAAAAaaaaaak.",
        ],
        colors: ["h": 0xDCE6F5, "H": 0xA9B6CC, "t": 0xFFD866, "T": 0xC9961A, "s": 0xFFF3B0],
        outfits: [(0x2E64D8, 0x1B3F94), (0x7A4FD0, 0x4E2F94), (0xC8324A, 0x8A1F32)]
    )

    static let bard = PixelSprite(
        name: "Pixel bard",
        rows: [
            "................................",
            "........................k.......",
            ".......................ksk......",
            "......................ksk.......",
            "..........kkkkkkkkkkksk.........",
            "........kkaaaaaaaaaaskkk........",
            "......kkaaaaaaaaaaaaaaaakk......",
            ".....kaaaaaaaaaaaaaaaaaaaakk....",
            "....kaaaaaaaaaaaaaaaaaaaaaaak...",
            "....kAAaaaaaaaaaaaaaaaaaaaAAk...",
            "....kkAAAAAAAAAAAAAAAAAAAAAkk...",
            "....khhhhhhhhhhhhhhhhhhhhhhk....",
            "....khhhhhhhhhhhhhhhhhhhhhhk....",
            "....khhhhhhhhhhhhhhhhhhhhhhk....",
            "....khhkfhhffhffffhffhhfkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khhkffffffffffffffffkhhk....",
            "....khHkffffffffffffffffkHhk....",
            "....khHkkFffffffffffffFkkHhk....",
            "....kHHk.kFFffffffffFFk.kHHk....",
            ".....kk...kkFFffffFFkk...kk.....",
            "............kkFFFFkk............",
            "....kkbkkkkkttttttttkkkkkkkk....",
            "...kaabBaaaktTtTTtTtkaaaaaaak...",
            "..kaaaabBaaaktTttTtkaaaaaaaaak..",
            ".kaaaaaabBaaAkttttkAaaaaaaaaaak.",
            ".kaaaaaaabBAAAkkkkAAAaaaaaaaaak.",
            ".kaaaaaaaabBAAAssAAAAAaaaaaaaak.",
            ".kaaaaaaaaAbBAAAAAAAAAaaaaaaaak.",
            ".kaaaaaaaaAAbBAAAAAAAAaaaaaaaak.",
        ],
        colors: ["h": 0x8A5430, "H": 0x5A3218, "t": 0xF4F1E8, "T": 0xC8C4D0, "s": 0xFFD866, "b": 0x6A3E20, "B": 0xA8703E],
        outfits: [(0x2AA889, 0x1B7560), (0xD0507A, 0x963456), (0xE09A2A, 0xA86A14)]
    )

    static let ranger = PixelSprite(
        name: "Pixel ranger",
        rows: [
            "................................",
            "................................",
            "................................",
            "...........kkkkkkkkkk...........",
            ".........kkaaaaaaaaaakk.........",
            ".......kkaaaaaaaaaaaaaakk.......",
            "......kaaaaaaaaaaaaaaaaaak......",
            ".....kaaaaaaaaaaaaaaaaaaaak.....",
            "....kaaaaaaaaaaaaaaaaaaaaaak....",
            "...kaaaaaaaaaaaaaaaaaaaaaaaak...",
            "...kaaaaaaAAAAAAAAAAAAaaaaaak...",
            "..kaaaaaAAkkkkkkkkkkkkAAaaaaak..",
            "..kaaaaAkhhhhhhhhhhhhhhkAaaaak..",
            "..kaaaAkhhhhhhhhhhhhhhhhkAaaak..",
            "..kaaaAkfhhffhffffhffhhfkAaaak..",
            "..kaaaAkffffffffffffffffkAaaak..",
            "..kaaaAkffffffffffffffffkAaaak..",
            "..kaaaAkffffffffffffffffkAaaak..",
            "..kaaaAkffffffffffffffffkAaaak..",
            "..kaaaAkffffffffffffffffkAaaak..",
            "..kaaaAkkFffffffffffffFkkAaaak..",
            "..kaaaaAkkFFffffffffFFkkAaaaak..",
            "..kaaaaaAAkkFFffffFFkkAAaaaaak..",
            "..kaaaaaakkkkttttttkkkkaaaaaak..",
            ".kaaaaaaktttTttttttTtttkaaaaaak.",
            ".kaaaaaaakTTTTTTTTTTTTkaaaaaaak.",
            "kaaaaaaaaaakkkkkkkkkttaaaaaaaaak",
            "kaaaaaaaaaaAAAAkkAAAtTaaaaaaaaak",
            "kaaaaaaaaaaAAAAssAAAAtTaaaaaaaak",
            "kaaaaaaaaaaAAAAAAAAAATaaaaaaaaak",
            "kaaaaaaaaaaAAAAAAAAAAaaaaaaaaaak",
            "kaaaaaaaaaaAAAAAAAAAAaaaaaaaaaak",
        ],
        colors: ["h": 0xE8783A, "H": 0xB8522A, "t": 0xD8434A, "T": 0x9A2A34, "s": 0xFFD866],
        outfits: [(0x4E9A3E, 0x2F6A2A), (0x8A6440, 0x5E4228), (0x56708C, 0x384C64)]
    )
}

struct Portrait: View {
    var mood: Mood
    var outfit: Int
    var model: ClaudeModel
    var pack: SpritePack?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let blinkPhase = t.truncatingRemainder(dividingBy: 4.2)
            let eyes = blinkPhase < 0.06 ? 2 : blinkPhase < 0.14 ? 3 : blinkPhase < 0.2 ? 2 : 1
            let mouth = mood == .talking ? [1, 2, 3, 2][Int(t * 10) % 4] : 1

            ZStack(alignment: .topTrailing) {
                ZStack {
                    MorphingPanel(time: t, phase: 2.1, wobble: 14)
                        .fill(LinearGradient(colors: [Theme.navy.opacity(0.9), Theme.deep.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                        .padding(.vertical, 2)
                        .padding(.horizontal, -10)
                    MorphingPanel(time: t, wobble: 14)
                        .fill(LinearGradient(colors: [Theme.cyan.opacity(0.45), Theme.ice.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        .padding(.vertical, 10)
                    Theme.cyan.opacity(0.55)
                        .mask(sprite(eyes: eyes, mouth: mouth))
                        .offset(x: 8, y: 6)
                    sprite(eyes: eyes, mouth: mouth)
                }
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

    /// Head-and-shoulders region of a layered set's 2048×2048 canvas.
    private static let bust = CGRect(x: 420, y: 680, width: 1160, height: 1368)

    @ViewBuilder
    private func sprite(eyes: Int, mouth: Int) -> some View {
        switch pack?.picture(mood: mood, outfit: outfit, eyes: eyes, mouth: mouth) {
        case .image(let image):
            // Small images are pixel art being scaled up, which smoothing would blur.
            Image(nsImage: image)
                .resizable()
                .interpolation(image.size.width < 210 ? .none : .high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .layers(let layers):
            Canvas { context, size in
                let scale = min(size.width / Self.bust.width, size.height / Self.bust.height)
                for layer in layers {
                    let rect = CGRect(x: (layer.origin.x - Self.bust.minX) * scale, y: (layer.origin.y - Self.bust.minY) * scale,
                                      width: layer.size.width * scale, height: layer.size.height * scale)
                    context.draw(Image(nsImage: layer.image), in: rect)
                }
            }
        case nil:
            let character = PixelSprite.of(model)
            Canvas { context, size in
                character.draw(mood: mood, blink: eyes > 1, mouthOpen: mouth > 1, outfit: outfit, in: context, size: size)
            }
        }
    }
}
