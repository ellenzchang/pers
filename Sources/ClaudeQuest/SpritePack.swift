import AppKit

/// A portrait set from a folder, in one of two layouts:
/// - frames: `idle.png`, optionally `thinking.png`, `talking.png` and `worried.png`, plus `<mood>-blink.png` and `talking-open.png`;
/// - layered: a `manifest.json` listing outfit images with eye and mouth overlays, for sets with several outfits.
@MainActor
final class SpritePack {
    enum Picture {
        case image(NSImage)
        case layers([Layer])
    }

    struct Layer {
        var image: NSImage
        var origin: CGPoint
        /// Size in the set's original pixel space, which the manifest's offsets are expressed in.
        var size: CGSize
    }

    struct Manifest: Decodable {
        var outfits: [Outfit]
        var eyes: [String: [String]]
        var mouths: [String: [String]]
        var eyesOffset: Offset
        var mouthsOffset: Offset

        struct Outfit: Decodable {
            var file: String
            var set: String
        }

        struct Offset: Decodable {
            var x: CGFloat
            var y: CGFloat
        }
    }

    private struct Loaded {
        var image: NSImage
        var size: CGSize
    }

    let name: String
    private let directory: URL
    private let manifest: Manifest?
    private var cache: [String: Loaded?] = [:]

    init?(directory: URL) {
        let manifest = (try? Data(contentsOf: directory.appendingPathComponent("manifest.json")))
            .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
            .flatMap { $0.outfits.isEmpty ? nil : $0 }
        guard manifest != nil || FileManager.default.fileExists(atPath: directory.appendingPathComponent("idle.png").path) else { return nil }
        name = directory.lastPathComponent
        self.directory = directory
        self.manifest = manifest
    }

    /// `eyes` and `mouth` are frames 1–3: open, half and closed eyes; closed, half and open mouth.
    func picture(mood: Mood, outfit: Int, eyes: Int, mouth: Int) -> Picture? {
        if let manifest { return .layers(layers(manifest, mood: mood, outfit: outfit, eyes: eyes, mouth: mouth)) }
        let frame = mouth > 1 ? "-open" : eyes > 1 ? "-blink" : ""
        // A missing frame falls back to its mood's still image, and a missing mood to idle.
        return [mood.rawValue + frame, mood.rawValue, "idle" + frame, "idle"].lazy
            .compactMap { self.image($0 + ".png", downscaled: false) }.first
            .map { .image($0.image) }
    }

    private func layers(_ manifest: Manifest, mood: Mood, outfit: Int, eyes: Int, mouth: Int) -> [Layer] {
        let outfit = manifest.outfits[outfit % manifest.outfits.count]
        let face = mood.face
        return [
            image(outfit.file).map { Layer(image: $0.image, origin: .zero, size: $0.size) },
            overlay(manifest.eyes, set: outfit.set, face: face, suffix: "_E\(eyes).png")
                .map { Layer(image: $0.image, origin: CGPoint(x: manifest.eyesOffset.x, y: manifest.eyesOffset.y), size: $0.size) },
            overlay(manifest.mouths, set: outfit.set, face: face, suffix: "_M\(mouth).png")
                .map { Layer(image: $0.image, origin: CGPoint(x: manifest.mouthsOffset.x, y: manifest.mouthsOffset.y), size: $0.size) },
        ].compactMap { $0 }
    }

    /// Outfits with their own face set use it; others share "general". Faces missing a frame fall back to
    /// that face's first frame (e.g. a wink has no blink), and missing faces fall back to the neutral F00.
    private func overlay(_ sets: [String: [String]], set: String, face: String, suffix: String) -> Loaded? {
        let files = sets[set] ?? sets["general"] ?? []
        let file = files.first { $0.contains("_\(face)_") && $0.hasSuffix(suffix) }
            ?? files.first { $0.contains("_\(face)_") }
            ?? files.first { $0.contains("_F00_") && $0.hasSuffix(suffix) }
        return file.flatMap { image($0) }
    }

    /// Layers are downscaled once on load; redrawing full 2048px textures every animation frame is costly.
    private func image(_ relativePath: String, downscaled: Bool = true) -> Loaded? {
        if let cached = cache[relativePath] { return cached }
        let loaded = NSImage(contentsOf: directory.appendingPathComponent(relativePath)).flatMap { downscaled ? halved($0) : Loaded(image: $0, size: $0.size) }
        cache[relativePath] = .some(loaded)
        return loaded
    }

    private func halved(_ source: NSImage) -> Loaded? {
        guard let rep = source.representations.first, rep.pixelsWide > 0 else { return nil }
        let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide / 2, pixelsHigh: rep.pixelsHigh / 2,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return Loaded(image: image, size: size)
    }
}

private extension Mood {
    /// Expression codes in layered sets: F01 soft smile, F02 focused, F00 neutral, F06 sad.
    var face: String {
        switch self {
        case .idle: "F01"
        case .thinking: "F02"
        case .talking: "F00"
        case .worried: "F06"
        }
    }
}

/// The sprite folders in Application Support and which one each model uses, kept in UserDefaults.
@MainActor
final class SpriteSettings: ObservableObject {
    static let shared = SpriteSettings()
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeQuest/Sprites", isDirectory: true)
    private static let choicesKey = "spritePacks"

    @Published private(set) var packs: [SpritePack] = []
    @Published private var choices: [String: String] {
        didSet { UserDefaults.standard.set(choices, forKey: Self.choicesKey) }
    }

    private init() {
        choices = UserDefaults.standard.dictionary(forKey: Self.choicesKey) as? [String: String] ?? [:]
        reload()
    }

    /// Rescans the folder, so sets added while the app runs show up.
    func reload() {
        let directories = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        packs = directories.compactMap(SpritePack.init(directory:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Nil means the built-in pixel sprite, which is also used when the chosen folder is gone.
    func pack(for model: ClaudeModel) -> SpritePack? {
        packs.first { $0.name == choices[model.rawValue] }
    }

    func choose(_ pack: SpritePack?, for model: ClaudeModel) {
        choices[model.rawValue] = pack?.name
    }
}
