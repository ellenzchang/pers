import AppKit

/// A layered character sprite (outfit base + eye and mouth overlays) as produced by `scripts/fetch_sprites.py`.
@MainActor
final class SpritePack {
    struct Outfit: Decodable {
        var file: String
        var set: String
    }

    struct Offset: Decodable {
        var x: CGFloat
        var y: CGFloat
    }

    struct Manifest: Decodable {
        var outfits: [Outfit]
        var eyes: [String: [String]]
        var mouths: [String: [String]]
        var eyesOffset: Offset
        var mouthsOffset: Offset
    }

    struct Layer {
        var image: NSImage
        var origin: CGPoint
        /// Size in the pack's original pixel space, which the offsets are expressed in.
        var size: CGSize
    }

    private struct Loaded {
        var image: NSImage
        var size: CGSize
    }

    /// Packs bundled into the app come first; Application Support holds extra packs added after building.
    static let installed: SpritePack? = {
        let roots = [
            Bundle.main.resourceURL?.appendingPathComponent("Sprites", isDirectory: true),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ClaudeQuest/Sprites", isDirectory: true),
        ].compactMap { $0 }
        let packs = roots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
        }
        return packs.lazy.compactMap(SpritePack.init(directory:)).first
    }()

    let manifest: Manifest
    private let directory: URL
    private var cache: [String: Loaded] = [:]

    init?(directory: URL) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              !manifest.outfits.isEmpty else { return nil }
        self.directory = directory
        self.manifest = manifest
    }

    /// Layers bottom to top. `face` is an expression code like "F01"; `eyes` and `mouth` are frame numbers 1–3.
    func layers(outfit: Int, face: String, eyes: Int, mouth: Int) -> [Layer] {
        let outfit = manifest.outfits[outfit % manifest.outfits.count]
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
        return file.flatMap(image)
    }

    /// Layers are downscaled once on load; redrawing full 2048px textures every animation frame is costly.
    private func image(_ relativePath: String) -> Loaded? {
        if let cached = cache[relativePath] { return cached }
        guard let source = NSImage(contentsOf: directory.appendingPathComponent(relativePath)),
              let rep = source.representations.first, rep.pixelsWide > 0 else { return nil }
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
        let loaded = Loaded(image: image, size: size)
        cache[relativePath] = loaded
        return loaded
    }
}
