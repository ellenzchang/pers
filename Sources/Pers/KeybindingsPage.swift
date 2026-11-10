import SwiftUI
import AppKit

struct KeybindingsPage: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var keymap = Keymap.shared
    @ViewState private var selected = 0
    @ViewState private var recording: Recording?
    @ViewState private var monitor: Any?
    @FocusState private var focused: Bool

    private struct Recording: Equatable {
        var action: KeyAction
        var index: Int
    }

    private enum Row: Hashable {
        case preset, reset, action(KeyAction)
    }

    private let rows: [Row] = [.preset, .reset] + KeyAction.allCases.map(Row.action)

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            NamePlate(name: "KEYBINDINGS & SHORTCUTS", color: Theme.gold, shadowColor: Theme.ocean)
                .padding(.horizontal, 18)
                .zIndex(1)
            VStack(alignment: .leading, spacing: 14) {
                header
                list
            }
            .padding(.top, 6)
            .padding(.bottom, 18)
            .panel(accent: Theme.gold, padding: 18, opacity: 1)
            .overlay(alignment: .bottomTrailing) {
                KeyHints(hints: hints)
                    .padding(.horizontal, 10)
                    .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
                    .padding(.trailing, 18)
                    .offset(y: 10)
            }
        }
        .frame(width: 720)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handle)
        .onAppear { focused = true }
        .onChange(of: recording) { record() }
        .onDisappear { monitor.map(NSEvent.removeMonitor) }
    }

    private var hints: [(key: String, action: String)] {
        if recording != nil { return [("any key", "assign"), ("same key", "keep")] }
        return [(KeyAction.label(.down, .up), "select"), (KeyAction.select.label, "change"), (KeyAction.back.label, "map")]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                marker(.preset)
                Text("Preset").font(Theme.body).foregroundStyle(Theme.ice)
                ForEach(KeyPreset.allCases, id: \.self) { preset in
                    Button { keymap.preset = preset } label: {
                        Chip(active: keymap.preset == preset, color: Theme.gold) { Text(preset.title.uppercased()) }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                marker(.reset)
                Button(action: keymap.resetAll) { Chip(color: Theme.red) { Text("RESET TO DEFAULT KEYBINDINGS") } }
                    .buttonStyle(.plain)
                    .disabled(keymap.overrides.isEmpty)
                Text(keymap.overrides.isEmpty ? "Using the \(keymap.preset.title.lowercased()) keys" : "\(keymap.overrides.count) changed")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(KeySection.allCases, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.title.uppercased()).font(Theme.ui(13, weight: .black)).foregroundStyle(Theme.gold)
                            Text(section.note).font(Theme.ui(11)).foregroundStyle(Theme.dim)
                        }
                        .padding(.top, 12)
                        ForEach(section.actions) { action in
                            row(action).id(Row.action(action))
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: selected) { proxy.scrollTo(rows[selected]) }
        }
    }

    private func row(_ action: KeyAction) -> some View {
        let conflicts = keymap.conflicts(of: action)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker(.action(action))
            VStack(alignment: .leading, spacing: 0) {
                Text(action.title).font(Theme.body).foregroundStyle(rows[selected] == .action(action) ? Theme.gold : Theme.ice)
                if !conflicts.isEmpty {
                    Text("Same key as " + conflicts.map { "\($0.title) (\($0.section.title))" }.joined(separator: ", "))
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.red)
                }
            }
            Spacer(minLength: 8)
            if keymap.overrides[action] != nil {
                Button { keymap.reset(action) } label: { Text("↺ \(keymap.preset.title.uppercased())") }
                    .buttonStyle(.plain)
                    .font(Theme.ui(10, weight: .black))
                    .foregroundStyle(Theme.dim)
                    .help("Back to the \(keymap.preset.title.lowercased()) key")
            }
            ForEach(Array(keymap.shortcuts(for: action).enumerated()), id: \.offset) { index, shortcut in
                let listening = recording == Recording(action: action, index: index)
                Button { recording = listening ? nil : Recording(action: action, index: index) } label: {
                    Chip(active: listening, color: keymap.overrides[action] != nil ? Theme.gold : Theme.cyan) {
                        Text(listening ? "PRESS A KEY" : shortcut.text)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = rows.firstIndex(of: .action(action)) ?? selected }
    }

    private func marker(_ row: Row) -> some View {
        RowMarker(active: rows[selected] == row)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.action(in: .navigation) {
        case .back: store.showingMap = true
        case .down: selected = min(selected + 1, rows.count - 1)
        case .up: selected = max(selected - 1, 0)
        case .top: selected = 0
        case .bottom: selected = rows.count - 1
        case .select where press.phase == .down:
            switch rows[selected] {
            case .preset: keymap.preset = keymap.preset == .vim ? .videoGame : .vim
            case .reset: keymap.resetAll()
            case .action(let action): recording = Recording(action: action, index: 0)
            }
        default: return .ignored
        }
        return .handled
    }

    /// A local monitor sees the key before menus do, so ⌘ shortcuts can be recorded instead of firing.
    private func record() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        guard let target = recording else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let shortcut = Shortcut(event) else { return nil }
            MainActor.assumeIsolated {
                Keymap.shared.assign(shortcut, to: target.action, at: target.index)
                recording = nil
            }
            return nil
        }
    }
}
