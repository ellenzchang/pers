import SwiftUI

enum ThemeStyle: String, CaseIterable {
    case neutral, quest
}

enum Theme {
    static let styleKey = "theme"

    static var isQuest: Bool { UserDefaults.standard.string(forKey: styleKey) == ThemeStyle.quest.rawValue }

    private static func pick(_ neutral: UInt32, _ quest: UInt32) -> Color {
        Color(hex: isQuest ? quest : neutral)
    }

    static var deep: Color { pick(0x0D1117, 0x020718) }
    static var ocean: Color { pick(0x0D1117, 0x0A2A6B) }
    static var panelTop: Color { pick(0x161B22, 0x0D307A) }
    static var panelBottom: Color { pick(0x161B22, 0x04103A) }
    static var terminalTop: Color { pick(0x010409, 0x1A1A1A) }
    static var terminalBottom: Color { pick(0x010409, 0x000000) }
    static var ice: Color { pick(0xE6EDF3, 0xEAF8FF) }
    static var navy: Color { pick(0x0D1117, 0x061A4A) }
    static var codeBackground: Color { pick(0x010409, 0x020A1E) }
    static var text: Color { pick(0xE6EDF3, 0xEAF8FF) }
    static var dim: Color { pick(0x8B949E, 0x6E8FC4) }
    static var cyan: Color { pick(0x58A6FF, 0x37D7FF) }
    static var aqua: Color { pick(0x39C5CF, 0x7DF5C8) }
    static var gold: Color { pick(0xD29922, 0xFFD866) }
    static var green: Color { pick(0x3FB950, 0x4BE37A) }
    static var amber: Color { pick(0x9E6A03, 0xC9961A) }
    static var amberTop: Color { pick(0x272115, 0x6B5200) }
    static var amberBottom: Color { pick(0x272115, 0x2E2200) }
    static var pink: Color { pick(0xF778BA, 0xFF7AB8) }
    static var red: Color { pick(0xF85149, 0xFF4D6D) }

    static func ui(_ size: CGFloat = 12, weight: Font.Weight = .heavy) -> Font {
        isQuest ? .system(size: size, weight: weight).width(.condensed).italic() : .system(size: size, weight: .medium)
    }
    static func display(_ size: CGFloat) -> Font {
        isQuest ? .system(size: size, weight: .black).width(.compressed).italic() : .system(size: size * 0.6, weight: .semibold)
    }
    static let body = Font.system(size: 14.5, weight: .medium)
    static let code = Font.system(size: 12.5, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Slant: Shape {
    var amount: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        guard Theme.isQuest else { return Path(roundedRect: rect, cornerRadius: 6) }
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + amount, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - amount, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Rectangle with the top-left and bottom-right corners sliced off.
struct CutPanel: Shape {
    var cut: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        guard Theme.isQuest else { return Path(roundedRect: rect, cornerRadius: 8) }
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

/// Quadrilateral whose corners drift on out-of-phase sine waves, so the outline keeps changing shape.
struct MorphingPanel: Shape {
    var time: Double
    var phase: Double = 0
    var wobble: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        return Path { path in
            for (index, corner) in corners.enumerated() {
                let t = time + phase + Double(index) * 1.9
                let point = CGPoint(x: corner.x + wobble * sin(t * 0.8), y: corner.y + wobble * cos(t * 1.1))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

struct Panel: ViewModifier {
    var light = false
    var accent: Color = Theme.cyan
    var dark = false
    var padding: CGFloat = 14
    var morphing = false
    var selected = false
    var colors: [Color]?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if morphing && Theme.isQuest {
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        layers(MorphingPanel(time: time), shadow: MorphingPanel(time: time, phase: 2.5))
                    }
                } else {
                    layers(CutPanel(), shadow: CutPanel())
                }
            }
    }

    private var borderOpacity: Double {
        if light { return 0 }
        return Theme.isQuest ? 0.7 : selected ? 1 : 0.35
    }

    private func layers(_ shape: some Shape, shadow: some Shape) -> some View {
        ZStack {
            if Theme.isQuest { shadow.fill(accent.opacity(0.35)).offset(x: 6, y: 6) }
            if light {
                shape.fill(Theme.ice)
            } else {
                let colors = colors ?? (dark ? [Theme.terminalTop, Theme.terminalBottom] : [Theme.panelTop, Theme.panelBottom])
                shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .opacity(0.94)
            }
            shape.stroke(accent.opacity(borderOpacity), lineWidth: Theme.isQuest || selected ? 1.5 : 1)
        }
    }
}

extension View {
    func panel(light: Bool = false, accent: Color = Theme.cyan, dark: Bool = false, padding: CGFloat = 14,
               morphing: Bool = false, selected: Bool = false, colors: [Color]? = nil) -> some View {
        modifier(Panel(light: light, accent: accent, dark: dark, padding: padding, morphing: morphing, selected: selected, colors: colors))
    }
}

struct NamePlate: View {
    var name: String
    var color: Color = Theme.ice
    var shadowColor: Color = Theme.cyan
    var textColor: Color = Theme.navy
    var morphing = false

    var body: some View {
        Text(name)
            .font(Theme.ui(14, weight: .black))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
            .background {
                if morphing && Theme.isQuest {
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        layers(MorphingPanel(time: time, wobble: 4), shadow: MorphingPanel(time: time, phase: 2.5, wobble: 4))
                    }
                } else {
                    layers(Slant(amount: 10), shadow: Slant(amount: 10))
                }
            }
    }

    private func layers(_ shape: some Shape, shadow: some Shape) -> some View {
        ZStack {
            if Theme.isQuest { shadow.fill(shadowColor).offset(x: 4, y: 3) }
            shape.fill(color)
        }
    }
}

struct Chip<Label: View>: View {
    var active = false
    var color: Color = Theme.cyan
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(Theme.ui(13))
            .foregroundStyle(active ? Theme.navy : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Slant().fill(active ? Theme.ice : Theme.navy.opacity(0.7)))
            .overlay(Slant().stroke(color.opacity(active ? 0 : 0.55), lineWidth: 1.5))
            .contentShape(Slant())
    }
}

struct MoonlitBackground: View {
    var body: some View {
        Canvas { context, size in
            let moon = CGPoint(x: size.width * 0.82, y: size.height * 0.28)
            for (radius, alpha) in [(260.0, 0.04), (170.0, 0.05), (110.0, 0.07)] {
                context.fill(Path(ellipseIn: CGRect(x: moon.x - radius, y: moon.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(Theme.cyan.opacity(alpha)))
            }
            for i in 0..<6 {
                let x = size.width * (0.1 + Double(i) * 0.17)
                var shaft = Path()
                shaft.move(to: CGPoint(x: x, y: 0))
                shaft.addLine(to: CGPoint(x: x + 60 + Double(i % 3) * 30, y: 0))
                shaft.addLine(to: CGPoint(x: x - 220 + Double(i % 3) * 30, y: size.height))
                shaft.addLine(to: CGPoint(x: x - 280, y: size.height))
                shaft.closeSubpath()
                context.fill(shaft, with: .color(Theme.ice.opacity(0.018)))
            }
            for y in stride(from: size.height * 0.55, to: size.height, by: 7) {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Theme.cyan.opacity(0.025)))
            }
        }
        .background(LinearGradient(colors: [Theme.ocean, Theme.deep], startPoint: .top, endPoint: .bottom))
    }
}

/// `@State` is a macro in recent SDKs; Command Line Tools ship without the SwiftUI macro plugin,
/// so naming the property-wrapper type through an alias keeps the app buildable without Xcode.
typealias ViewState = SwiftUI.State
