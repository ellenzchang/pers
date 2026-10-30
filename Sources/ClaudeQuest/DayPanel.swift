import SwiftUI

struct DayPanel: View {
    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            let phase = Self.moonPhase(on: date)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .trailing, spacing: -1) {
                    Text(String(format: "%02d/%02d", Calendar.current.component(.month, from: date), Calendar.current.component(.day, from: date)))
                        .font(Theme.display(44))
                        .foregroundStyle(Theme.ice)
                        .shadow(color: Theme.cyan.opacity(0.6), radius: 0, x: 3, y: 3)
                    Text(Self.timeOfDay(date))
                        .font(Theme.ui(13, weight: .black))
                        .foregroundStyle(Theme.cyan)
                }
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(Theme.ui(18, weight: .black))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 10)
                        .background(Slant(amount: 6).fill(Theme.ice))
                    MoonGlyph(phase: phase)
                        .frame(width: 26, height: 26)
                        .help(Self.moonName(phase))
                }
            }
        }
    }

    /// Fraction of the synodic month since a reference new moon (2000-01-06 18:14 UTC).
    static func moonPhase(on date: Date) -> Double {
        let synodicMonth = 29.530588853
        let days = (date.timeIntervalSince1970 - 947_182_440) / 86_400
        let phase = days.truncatingRemainder(dividingBy: synodicMonth) / synodicMonth
        return phase < 0 ? phase + 1 : phase
    }

    static func moonName(_ phase: Double) -> String {
        let names = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                     "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        return names[Int((phase * 8).rounded()) % 8]
    }

    static func timeOfDay(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0: "DARK HOUR"
        case 5..<8: "EARLY MORNING"
        case 8..<12: "MORNING"
        case 12: "LUNCHTIME"
        case 13..<16: "AFTERNOON"
        case 16..<18: "AFTER SCHOOL"
        case 18..<23: "EVENING"
        default: "LATE NIGHT"
        }
    }
}

struct MoonGlyph: View {
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
            context.clip(to: disc)
            context.fill(disc, with: .color(Theme.gold))
            // An offset dark disc approximates the terminator well enough at icon size.
            let travel = phase < 0.5 ? -phase / 0.5 : 1 - (phase - 0.5) / 0.5
            let shadow = CGRect(x: travel * size.width, y: 0, width: size.width, height: size.height)
            context.fill(Path(ellipseIn: shadow), with: .color(Theme.navy))
        }
        .overlay(Circle().stroke(Theme.cyan.opacity(0.6), lineWidth: 1))
    }
}
