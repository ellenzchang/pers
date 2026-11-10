// Renders the pixel-art penguin app icon to Assets/AppIcon.icns.
// Usage: swift scripts/make_icon.swift
import AppKit

let penguin = [
    "......KKKKKKKK......",
    "....KKPPPPPPPPKK....",
    "...KPPSSPPPPPPPPK...",
    "..KPPSPPPPPPPPPPPK..",
    "..KPPPWWWPPWWWPPPK..",
    ".KPPPWWWWWWWWWWPPPK.",
    ".KPPWHEEWWWWHEEWPPK.",
    ".KPPWEEEWWWWEEEWPPK.",
    ".KPPWEEEWOOWEEEWPPK.",
    ".KPPWRRWOOOOWRRWPPK.",
    "KPPPWWWWWooWWWWWPPPK",
    "KPPWWWWWWWWWWWWWWPPK",
    "KPPWWWWWWWWWWWWWWPPK",
    "KPPLWWWWWWWWWWWWLPPK",
    "KPPLWWWWWWWWWWWWLPPK",
    "KPPLWWWWWWWWWWWWLPPK",
    ".KKPWWWWWWWWWWWWPKK.",
    "..KPWWWWWWWWWWWWPK..",
    "..KPPWWWWWWWWWWPPK..",
    "...KPPWWWWWWWWPPK...",
    "....KOOOKKKKOOOK....",
    "....KKKKK..KKKKK....",
]

let colors: [Character: UInt32] = [
    "B": 0x000000, "w": 0x6C6C80,
    "K": 0xD7D7E0, "P": 0x2E2B3A, "S": 0x55506A, "L": 0x45405A,
    "W": 0xF6F2EA, "E": 0x121117, "H": 0xFFFFFF,
    "O": 0xF2A65A, "o": 0xC27A3E, "R": 0xF3A3B8,
]

// Full-bleed square: macOS applies its own rounded mask to the icon.
let grid = 26
var pixels = Array(repeating: Array(repeating: Character("B"), count: grid), count: grid)
for (x, y) in [(2, 4), (23, 6), (2, 17), (23, 15)] { pixels[y][x] = "w" }
for (row, line) in penguin.enumerated() {
    for (column, char) in line.enumerated() where char != "." { pixels[2 + row][3 + column] = char }
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / CGFloat(grid)
    for (y, row) in pixels.enumerated() {
        for (x, char) in row.enumerated() {
            guard let hex = colors[char] else { continue }
            color(hex).setFill()
            let left = (CGFloat(x) * scale).rounded(), right = (CGFloat(x + 1) * scale).rounded()
            let bottom = (CGFloat(grid - 1 - y) * scale).rounded(), top = (CGFloat(grid - y) * scale).rounded()
            NSRect(x: left, y: bottom, width: right - left, height: top - bottom).fill()
        }
    }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let assets = root.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try render(size: 512).write(to: assets.appendingPathComponent("AppIcon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote Assets/AppIcon.icns")
