import SwiftUI

enum ThemeStyle: String, CaseIterable {
    case neutral, quest, terminal, phantom
}

enum Theme {
    static let styleKey = "theme"

    private static var style: String? { UserDefaults.standard.string(forKey: styleKey) }
    static var isQuest: Bool { style == ThemeStyle.quest.rawValue }
    static var isTerminal: Bool { style == ThemeStyle.terminal.rawValue }
    static var isPhantom: Bool { style == ThemeStyle.phantom.rawValue }
    /// Themes drawn with slanted, cut and morphing shapes rather than rounded rectangles.
    static var isStylized: Bool { isQuest || isPhantom }

    private static func pick(_ neutral: UInt32, _ quest: UInt32, _ terminal: UInt32, _ phantom: UInt32) -> Color {
        Color(hex: isQuest ? quest : isTerminal ? terminal : isPhantom ? phantom : neutral)
    }

    /// Phantom time counts poses (several per second) rather than radians, see `MorphingPanel`.
    static func morphTime(_ date: Date) -> Double {
        let time = date.timeIntervalSinceReferenceDate
        return isPhantom ? time * 7 : time
    }

    static func radius(_ value: CGFloat) -> CGFloat { isTerminal ? 0 : value }

    static var deep: Color { pick(0x0D1117, 0x020718, 0x0C0C0F, 0x050505) }
    static var ocean: Color { pick(0x0D1117, 0x0A2A6B, 0x0C0C0F, 0x2A0308) }
    static var panelTop: Color { pick(0x161B22, 0x0D307A, 0x131318, 0x161616) }
    static var panelBottom: Color { pick(0x161B22, 0x04103A, 0x131318, 0x050505) }
    static var terminalTop: Color { pick(0x010409, 0x1A1A1A, 0x08080A, 0x111111) }
    static var terminalBottom: Color { pick(0x010409, 0x000000, 0x08080A, 0x000000) }
    static var ice: Color { pick(0xE6EDF3, 0xEAF8FF, 0xD7D7E0, 0xFFFFFF) }
    static var navy: Color { pick(0x0D1117, 0x061A4A, 0x0C0C0F, 0x000000) }
    static var codeBackground: Color { pick(0x010409, 0x020A1E, 0x08080A, 0x0A0A0A) }
    static var text: Color { pick(0xE6EDF3, 0xEAF8FF, 0xD7D7E0, 0xF5F5F5) }
    static var dim: Color { pick(0x8B949E, 0x6E8FC4, 0x6C6C80, 0x8C8C8C) }
    static var cyan: Color { pick(0x58A6FF, 0x37D7FF, 0x7DCFFF, 0xE60012) }
    static var aqua: Color { pick(0x39C5CF, 0x7DF5C8, 0x73DACA, 0xFF7A7A) }
    static var gold: Color { pick(0xD29922, 0xFFD866, 0xE0AF68, 0xFFE100) }
    static var green: Color { pick(0x3FB950, 0x4BE37A, 0x9ECE6A, 0x4BE37A) }
    static var amber: Color { pick(0x9E6A03, 0xC9961A, 0xB38A4D, 0xC9961A) }
    static var amberTop: Color { pick(0x272115, 0x6B5200, 0x1F1A12, 0x3A2A00) }
    static var amberBottom: Color { pick(0x272115, 0x2E2200, 0x1F1A12, 0x140E00) }
    static var pink: Color { pick(0xF778BA, 0xFF7AB8, 0xBB9AF7, 0xFF4FA3) }
    static var red: Color { pick(0xF85149, 0xFF4D6D, 0xF7768E, 0xFF2E2E) }

    static func ui(_ size: CGFloat = 12, weight: Font.Weight = .heavy) -> Font {
        if isTerminal { return .system(size: size, weight: .regular, design: .monospaced) }
        if isPhantom { return .system(size: size, weight: .black).width(.condensed) }
        return isQuest ? .system(size: size, weight: weight).width(.condensed).italic() : .system(size: size, weight: .medium)
    }
    static func display(_ size: CGFloat) -> Font {
        if isTerminal { return .system(size: size * 0.6, weight: .semibold, design: .monospaced) }
        if isPhantom { return .system(size: size, weight: .black, design: .serif).italic() }
        return isQuest ? .system(size: size, weight: .black).width(.compressed).italic() : .system(size: size * 0.6, weight: .semibold)
    }
    static var body: Font { isTerminal ? .system(size: 13.5, design: .monospaced) : .system(size: 14.5, weight: .medium) }
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
        guard Theme.isStylized else { return Path(roundedRect: rect, cornerRadius: Theme.radius(6)) }
        if Theme.isPhantom {
            return Path { path in
                path.move(to: CGPoint(x: rect.minX + amount * 1.5, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
                path.addLine(to: CGPoint(x: rect.maxX - amount * 0.5, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.1))
                path.closeSubpath()
            }
        }
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
        guard Theme.isStylized else { return Path(roundedRect: rect, cornerRadius: Theme.radius(8)) }
        if Theme.isPhantom {
            return Path { path in
                path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - cut * 3, y: rect.minY + 4))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.maxY - cut))
                path.addLine(to: CGPoint(x: rect.maxX - cut * 1.5, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 3))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut * 1.5))
                path.closeSubpath()
            }
        }
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

/// Quadrilateral whose outline keeps changing shape. Quest corners drift on out-of-phase sine waves;
/// phantom corners hold a fixed pose per whole unit of time and ease quickly into the next one.
struct MorphingPanel: Shape {
    var time: Double
    var phase: Double = 0
    var wobble: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        return Path { path in
            for (index, corner) in corners.enumerated() {
                let offset = Theme.isPhantom ? phantomOffset(corner: index, time: time + phase) : questOffset(corner: index, time: time + phase)
                let point = CGPoint(x: corner.x + wobble * offset.x, y: corner.y + wobble * offset.y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

extension MorphingPanel {
    func questOffset(corner: Int, time: Double) -> CGPoint {
        let t = time + Double(corner) * 1.9
        return CGPoint(x: sin(t * 0.8), y: cos(t * 1.1))
    }

    func phantomOffset(corner: Int, time: Double) -> CGPoint {
        let pose = time.rounded(.down)
        let progress = min(max((time - pose - 0.3) / 0.7, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        let from = Self.pose(Int(pose), corner: corner)
        let to = Self.pose(Int(pose) + 1, corner: corner)
        return CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
    }

    private static func pose(_ pose: Int, corner: Int) -> CGPoint {
        func unit(_ seed: Double) -> CGFloat {
            let noise = sin(seed) * 43758.5453
            return CGFloat(noise - noise.rounded(.down)) * 2 - 1
        }
        return CGPoint(x: unit(Double(pose) * 12.9898 + Double(corner) * 78.233),
                       y: unit(Double(pose) * 39.346 + Double(corner) * 11.135))
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
    var opacity = 0.94

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if animated {
                    TimelineView(.animation) { timeline in
                        let time = Theme.morphTime(timeline.date)
                        layers(MorphingPanel(time: time), shadow: MorphingPanel(time: time, phase: 2.5))
                    }
                } else {
                    layers(CutPanel(), shadow: CutPanel())
                }
            }
    }

    private var animated: Bool { Theme.isPhantom ? morphing || selected : morphing && Theme.isQuest }

    private var borderOpacity: Double {
        if light { return 0 }
        return Theme.isQuest ? 0.7 : selected ? 1 : 0.35
    }

    private var shadowOpacity: Double { Theme.isPhantom ? (animated ? 0.9 : 0.45) : 0.35 }

    private func layers(_ shape: some Shape, shadow: some Shape) -> some View {
        ZStack {
            if Theme.isStylized { shadow.fill(accent.opacity(shadowOpacity)).offset(x: 6, y: 6) }
            if light {
                shape.fill(Theme.ice)
            } else {
                let colors = colors ?? (dark ? [Theme.terminalTop, Theme.terminalBottom] : [Theme.panelTop, Theme.panelBottom])
                shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .opacity(opacity)
            }
            shape.stroke(accent.opacity(borderOpacity), lineWidth: Theme.isStylized || selected ? 1.5 : 1)
        }
    }
}

extension View {
    func panel(light: Bool = false, accent: Color = Theme.cyan, dark: Bool = false, padding: CGFloat = 14,
               morphing: Bool = false, selected: Bool = false, colors: [Color]? = nil, opacity: Double = 0.94) -> some View {
        modifier(Panel(light: light, accent: accent, dark: dark, padding: padding, morphing: morphing, selected: selected, colors: colors, opacity: opacity))
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
                if morphing && Theme.isStylized {
                    TimelineView(.animation) { timeline in
                        let time = Theme.morphTime(timeline.date)
                        layers(MorphingPanel(time: time, wobble: 4), shadow: MorphingPanel(time: time, phase: 2.5, wobble: 4))
                    }
                } else {
                    layers(Slant(amount: 10), shadow: Slant(amount: 10))
                }
            }
    }

    private func layers(_ shape: some Shape, shadow: some Shape) -> some View {
        ZStack {
            if Theme.isStylized { shadow.fill(shadowColor).offset(x: 4, y: 3) }
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
            .background(Slant().fill(Theme.navy.opacity(active ? 0 : 0.7)))
            .background(ActiveBackdrop(active: active, amount: 8))
            .overlay(Slant().stroke(color.opacity(active ? 0 : 0.55), lineWidth: 1.5))
            .contentShape(Slant())
            .activeShift(active, offset: 0)
    }
}

/// The white plate behind an active row or option; in the phantom theme it is a shifting shard with a red one kicked out behind it.
struct ActiveBackdrop: View {
    var active: Bool
    var amount: CGFloat = 8

    var body: some View {
        if Theme.isPhantom && active {
            TimelineView(.animation) { timeline in
                let time = Theme.morphTime(timeline.date)
                ZStack {
                    MorphingPanel(time: time, phase: 2.5, wobble: 4).fill(Theme.cyan).offset(x: 5, y: 4)
                    MorphingPanel(time: time, wobble: 3).fill(Theme.ice)
                }
            }
        } else {
            Slant(amount: amount).fill(active ? Theme.ice : .clear)
        }
    }
}

/// Nudges an active row sideways; the phantom theme also snaps it into a tilt with an overshooting pop.
struct ActiveShift: ViewModifier {
    var active: Bool
    var offset: CGFloat

    func body(content: Content) -> some View {
        let pop = Theme.isPhantom && active
        content
            .rotationEffect(.degrees(pop ? -3 : 0))
            .scaleEffect(pop ? 1.06 : 1)
            .offset(x: active ? offset : 0)
            .animation(Theme.isPhantom ? .spring(response: 0.18, dampingFraction: 0.4) : .spring(response: 0.25, dampingFraction: 0.7),
                       value: active)
    }
}

extension View {
    func activeShift(_ active: Bool, offset: CGFloat = 6) -> some View {
        modifier(ActiveShift(active: active, offset: offset))
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

struct PhantomBackground: View {
    var body: some View {
        Canvas { context, size in
            let origin = CGPoint(x: size.width * 0.12, y: size.height * 1.1)
            let reach = hypot(size.width, size.height) * 1.3
            let rays = 28
            for ray in stride(from: 0, to: rays, by: 2) {
                let start = Double(ray) / Double(rays) * 2 * .pi
                let end = Double(ray + 1) / Double(rays) * 2 * .pi
                var wedge = Path()
                wedge.move(to: origin)
                wedge.addLine(to: CGPoint(x: origin.x + reach * cos(start), y: origin.y + reach * sin(start)))
                wedge.addLine(to: CGPoint(x: origin.x + reach * cos(end), y: origin.y + reach * sin(end)))
                wedge.closeSubpath()
                context.fill(wedge, with: .color(Theme.ocean.opacity(0.7)))
            }
            let corner = CGPoint(x: size.width, y: 0)
            let spread = min(size.width, size.height) * 0.6
            for x in stride(from: size.width - spread, through: size.width, by: 14) {
                for y in stride(from: 0, through: spread, by: 14) {
                    let radius = 4 * (1 - hypot(x - corner.x, y - corner.y) / spread)
                    guard radius > 0.3 else { continue }
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(Theme.cyan.opacity(0.35)))
                }
            }
        }
        .background(Theme.deep)
    }
}

/// `@State` is a macro in recent SDKs; Command Line Tools ship without the SwiftUI macro plugin,
/// so naming the property-wrapper type through an alias keeps the app buildable without Xcode.
typealias ViewState = SwiftUI.State
