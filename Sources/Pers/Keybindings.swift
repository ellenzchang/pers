import SwiftUI
import AppKit

/// A key with its modifiers, written the way hints show it: "j", "G", "⌘T", "⇧↑", "ESC".
/// An uppercase letter means Shift; named keys spell Shift out as "⇧".
struct Shortcut: Hashable, Codable, ExpressibleByStringLiteral {
    var text: String

    init(stringLiteral text: String) { self.text = text }

    init(from decoder: Decoder) throws { text = try decoder.singleValueContainer().decode(String.self) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    /// Nil for keys a binding can't hold, like function keys.
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags
        var text = flags.contains(.control) ? "⌃" : ""
        if flags.contains(.option) { text += "⌥" }
        if let named = Self.keyCodes[event.keyCode] {
            if flags.contains(.shift) { text += "⇧" }
            if flags.contains(.command) { text += "⌘" }
            text += named
        } else {
            guard let key = event.charactersIgnoringModifiers, key.count == 1,
                  let scalar = key.unicodeScalars.first, scalar.value >= 0x20, scalar.value < 0xF700 else { return nil }
            if flags.contains(.command) { text += "⌘" }
            text += key
        }
        self.text = text
    }

    private static let modifierSymbols: [Character: EventModifiers] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]
    private static let shortcutModifiers: EventModifiers = [.command, .control, .option]
    private static let namedKeys: [String: KeyEquivalent] = [
        "↑": .upArrow, "↓": .downArrow, "←": .leftArrow, "→": .rightArrow, "⏎": .return, "ESC": .escape,
        "⇥": .tab, "␣": .space, "⌫": .delete, "⌦": .deleteForward,
    ]
    private static let typedCharacters: [String: Set<String>] = ["⌫": ["\u{7F}", "\u{08}"], "⌦": ["\u{F728}"]]
    private static let keyCodes: [UInt16: String] = [
        126: "↑", 125: "↓", 123: "←", 124: "→", 36: "⏎", 76: "⏎", 53: "ESC", 48: "⇥", 49: "␣", 51: "⌫", 117: "⌦",
    ]

    private var parts: (modifiers: EventModifiers, key: String) {
        var modifiers: EventModifiers = []
        var rest = Substring(text)
        while rest.count > 1, let first = rest.first, let modifier = Self.modifierSymbols[first] {
            modifiers.insert(modifier)
            rest = rest.dropFirst()
        }
        return (modifiers, String(rest))
    }

    var keyboardShortcut: KeyboardShortcut {
        let (modifiers, key) = parts
        if let named = Self.namedKeys[key] { return KeyboardShortcut(named, modifiers: modifiers) }
        let shift: EventModifiers = key != key.lowercased() ? .shift : []
        return KeyboardShortcut(KeyEquivalent(key.lowercased().first ?? " "), modifiers: modifiers.union(shift))
    }

    func matches(_ press: KeyPress) -> Bool {
        let (modifiers, key) = parts
        guard press.modifiers.intersection(Self.shortcutModifiers) == modifiers.intersection(Self.shortcutModifiers) else { return false }
        if let named = Self.namedKeys[key] {
            // The ⌫ key types DEL (U+007F) while KeyEquivalent.delete is BS (U+0008), so a press can carry either.
            let typed = press.key == named || Self.typedCharacters[key]?.contains(press.characters) == true
            return typed && press.modifiers.contains(.shift) == modifiers.contains(.shift)
        }
        if modifiers.isDisjoint(with: Self.shortcutModifiers) { return press.characters == key }
        guard press.modifiers.contains(.shift) == (key != key.lowercased()) else { return false }
        // With Control held, `characters` can be the control code (⌃c is U+0003) rather than the letter.
        let controlCode = key.lowercased().first?.asciiValue.map { String(UnicodeScalar($0 & 0x1F)) }
        return String(press.key.character).lowercased() == key.lowercased() || (modifiers.contains(.control) && press.characters == controlCode)
    }
}

enum KeyPreset: String, CaseIterable {
    case vim, videoGame

    var title: String {
        switch self {
        case .vim: "Vim"
        case .videoGame: "Video game"
        }
    }
}

enum KeySection: CaseIterable {
    case app, chatInput, navigation, messages, diff, actions, apiTester, apiRequests, apiResponse, permission

    var title: String {
        switch self {
        case .app: "App"
        case .chatInput: "Chat input"
        case .navigation: "Lists"
        case .messages: "Messages"
        case .diff: "Diff"
        case .actions: "Actions panel"
        case .apiTester: "API tester"
        case .apiRequests: "API tester · requests"
        case .apiResponse: "API tester · response"
        case .permission: "API tester · permission prompt"
        }
    }

    var note: String {
        switch self {
        case .app: "Work on every page"
        case .chatInput: "While typing to Claude or the terminal"
        case .navigation: "Messages, diff, git log, map, actions, prompts, load data and the API tester"
        case .messages: "In navigate mode"
        case .diff: "Also the git log's commits"
        case .actions: "With the actions panel open"
        case .apiTester: "Both panes"
        case .apiRequests: "With the request pane selected"
        case .apiResponse: "With the response pane selected"
        case .permission: "While Claude asks to use a tool"
        }
    }

    var actions: [KeyAction] { KeyAction.allCases.filter { $0.section == self } }

    /// Sections whose keys are live at the same time, so a key shared between them is a clash.
    func overlaps(_ other: KeySection) -> Bool {
        self == other || live.contains(other) || other.live.contains(self)
    }

    private var live: [KeySection] {
        switch self {
        case .app: KeySection.allCases
        case .navigation: [.messages, .diff, .actions, .apiTester, .apiRequests, .apiResponse]
        case .apiTester: [.apiRequests, .apiResponse]
        default: []
        }
    }
}

enum KeyAction: String, CaseIterable, Identifiable {
    case newTab, newWorktree, closeTab, previousTab, nextTab, map, actions, previousModel, nextModel, nextMode, nextEffort,
         toggleDiff, toggleDiffBase, toggleLog, terminal, sprite, openInIntelliJ, sendRequest
    case send, navigate, switchInput, interrupt, reset, load, olderHistory, newerHistory, pageUp, pageDown, scrollLeft, scrollRight,
         acceptSuggestion
    case up, down, top, bottom, previousGroup, nextGroup, select, back, copy
    case type, fork
    case backToLog
    case switchScope, stopAction, toggleOutput, editAction, newAction, deleteAction
    case switchPane, askClaude, askTerminal, backToChat, stop
    case editURL, renameRequest, editHeaders, editBody, cycleMethod, newRequest, deleteRequest
    case toggleNode, expand, collapse, expandAll, collapseAll, search, nextMatch, previousMatch, toggleHeaders, copyAll
    case allow, allowAlways, deny

    var id: String { rawValue }
    var section: KeySection { info.section }
    var title: String { info.title }

    func defaults(for preset: KeyPreset) -> [Shortcut] {
        preset == .vim ? info.vim : info.videoGame
    }

    private var info: (section: KeySection, title: String, vim: [Shortcut], videoGame: [Shortcut]) {
        switch self {
        case .newTab: (.app, "New tab", ["⌘t"], ["⌘t"])
        case .newWorktree: (.app, "New worktree tab", ["⌘T"], ["⌘T"])
        case .closeTab: (.app, "Close tab", ["⌘w"], ["⌘w"])
        case .previousTab: (.app, "Previous tab", ["⌘1"], ["⌘1"])
        case .nextTab: (.app, "Next tab", ["⌘2"], ["⌘2"])
        case .map: (.app, "Map", ["⌃m"], ["⌃m"])
        case .actions: (.app, "Actions panel", ["⌘A"], ["⌘I"])
        case .previousModel: (.app, "Previous model", ["⌘j"], ["⌘3"])
        case .nextModel: (.app, "Next model", ["⌘k"], ["⌘4"])
        case .nextMode: (.app, "Next permission mode", ["⌘M"], ["⌘M"])
        case .nextEffort: (.app, "Next effort", ["⌘E"], ["⌘E"])
        case .toggleDiff: (.app, "Diff", ["⌘d"], ["⌘d"])
        case .toggleDiffBase: (.app, "Diff against main or unstaged", ["⌘B"], ["⌘B"])
        case .toggleLog: (.app, "Git log", ["⌘l"], ["⌘l"])
        case .terminal: (.app, "Terminal, or stop Claude when the tab has none", ["⌘."], ["⌘."])
        case .sprite: (.app, "Show portrait", ["⌘P"], ["⌘P"])
        case .openInIntelliJ: (.app, "Open diff file in IntelliJ", ["⌘O"], ["⌘O"])
        case .sendRequest: (.app, "Send request while editing it", ["⌘⏎"], ["⌘⏎"])

        case .send: (.chatInput, "Send", ["⏎"], ["⏎"])
        case .navigate: (.chatInput, "Navigate mode, or back to a prompt's options", ["ESC"], ["ESC"])
        case .switchInput: (.chatInput, "Switch between Claude and terminal", ["⇥"], ["⇥"])
        case .interrupt: (.chatInput, "Interrupt", ["⌃c"], ["⌃c"])
        case .reset: (.chatInput, "Reset session", ["⌃r"], ["⌃r"])
        case .load: (.chatInput, "Load a saved session", ["⌃l"], ["⌃l"])
        case .olderHistory: (.chatInput, "Older input", ["↑"], ["↑"])
        case .newerHistory: (.chatInput, "Newer input", ["↓"], ["↓"])
        case .pageUp: (.chatInput, "Scroll up", ["⇧↑"], ["⇧↑"])
        case .pageDown: (.chatInput, "Scroll down", ["⇧↓"], ["⇧↓"])
        case .scrollLeft: (.chatInput, "Scroll left", ["⇧←"], ["⇧←"])
        case .scrollRight: (.chatInput, "Scroll right", ["⇧→"], ["⇧→"])
        case .acceptSuggestion: (.chatInput, "Accept suggestion", ["→"], ["→"])

        case .up: (.navigation, "Up", ["k", "↑"], ["w", "↑"])
        case .down: (.navigation, "Down", ["j", "↓"], ["s", "↓"])
        case .top: (.navigation, "Top", ["g"], ["W"])
        case .bottom: (.navigation, "Bottom", ["G"], ["S"])
        case .previousGroup: (.navigation, "Previous file or folder", ["K"], ["q"])
        case .nextGroup: (.navigation, "Next file or folder", ["J"], ["e"])
        case .select: (.navigation, "Select", ["⏎"], ["f", "⏎"])
        case .back: (.navigation, "Back or close", ["ESC"], ["ESC"])
        case .copy: (.navigation, "Copy, press twice", ["y"], ["c"])

        case .type: (.messages, "Back to typing", ["i"], ["t"])
        case .fork: (.messages, "Fork from message, press twice", ["f"], ["b"])

        case .backToLog: (.diff, "Back to git log", ["⌫"], ["⌫"])

        case .switchScope: (.actions, "Repo or global actions", ["⇥"], ["⇥"])
        case .stopAction: (.actions, "Stop", ["s"], ["x"])
        case .toggleOutput: (.actions, "Show output", ["␣"], ["␣"])
        case .editAction: (.actions, "Edit", ["e"], ["r"])
        case .newAction: (.actions, "New action", ["n"], ["n"])
        case .deleteAction: (.actions, "Delete, press twice", ["x"], ["⌦"])

        case .switchPane: (.apiTester, "Switch pane", ["⇥"], ["⇥"])
        case .askClaude: (.apiTester, "Ask Claude", ["c"], ["t"])
        case .askTerminal: (.apiTester, "Terminal", ["t"], ["`"])
        case .backToChat: (.apiTester, "Back to chat", ["o"], ["⌫"])
        case .stop: (.apiTester, "Stop", ["s"], ["x"])

        case .editURL: (.apiRequests, "Edit URL", ["e"], ["u"])
        case .renameRequest: (.apiRequests, "Rename", ["r"], ["r"])
        case .editHeaders: (.apiRequests, "Edit headers", ["h"], ["h"])
        case .editBody: (.apiRequests, "Edit body", ["b"], ["b"])
        case .cycleMethod: (.apiRequests, "Next method", ["m"], ["m"])
        case .newRequest: (.apiRequests, "New request", ["n"], ["n"])
        case .deleteRequest: (.apiRequests, "Delete, press twice", ["x"], ["⌦"])

        case .toggleNode: (.apiResponse, "Expand or fold row", ["␣"], ["␣"])
        case .expand: (.apiResponse, "Expand", ["l", "→"], ["d", "→"])
        case .collapse: (.apiResponse, "Fold", ["h", "←"], ["a", "←"])
        case .expandAll: (.apiResponse, "Expand all", ["E"], ["D"])
        case .collapseAll: (.apiResponse, "Fold all", ["C"], ["A"])
        case .search: (.apiResponse, "Search", ["/"], ["/"])
        case .nextMatch: (.apiResponse, "Next match", ["n"], ["n"])
        case .previousMatch: (.apiResponse, "Previous match", ["N"], ["N"])
        case .toggleHeaders: (.apiResponse, "Headers", ["H"], ["H"])
        case .copyAll: (.apiResponse, "Copy all, press twice", ["Y"], ["C"])

        case .allow: (.permission, "Allow", ["y"], ["y"])
        case .allowAlways: (.permission, "Always allow", ["a"], ["a"])
        case .deny: (.permission, "Deny", ["n"], ["n"])
        }
    }
}

/// The chosen preset plus the keys the user reassigned on top of it, kept in UserDefaults.
@MainActor
final class Keymap: ObservableObject {
    static let shared = Keymap()
    private static let presetKey = "keyPreset"
    private static let overridesKey = "keyOverrides"

    @Published var preset: KeyPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: Self.presetKey) }
    }
    @Published private(set) var overrides: [KeyAction: [Shortcut]] {
        didSet {
            let saved = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
            UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.overridesKey)
        }
    }

    private init() {
        preset = UserDefaults.standard.string(forKey: Self.presetKey).flatMap(KeyPreset.init) ?? .vim
        let saved = UserDefaults.standard.data(forKey: Self.overridesKey)
            .flatMap { try? JSONDecoder().decode([String: [Shortcut]].self, from: $0) } ?? [:]
        overrides = Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in KeyAction(rawValue: key).map { ($0, value) } })
    }

    func shortcuts(for action: KeyAction) -> [Shortcut] {
        overrides[action] ?? action.defaults(for: preset)
    }

    func assign(_ shortcut: Shortcut, to action: KeyAction, at index: Int) {
        var shortcuts = shortcuts(for: action)
        if shortcuts.indices.contains(index) { shortcuts[index] = shortcut } else { shortcuts.append(shortcut) }
        overrides[action] = shortcuts == action.defaults(for: preset) ? nil : shortcuts
    }

    func reset(_ action: KeyAction) { overrides[action] = nil }

    func resetAll() { overrides = [:] }

    func conflicts(of action: KeyAction) -> [KeyAction] {
        let own = Set(shortcuts(for: action))
        return KeyAction.allCases.filter {
            $0 != action && $0.section.overlaps(action.section) && !own.isDisjoint(with: shortcuts(for: $0))
        }
    }
}

@MainActor
extension KeyAction {
    /// The first key, which is the one hints show.
    var label: String { Keymap.shared.shortcuts(for: self).first?.text ?? "" }

    static func label(_ actions: KeyAction...) -> String { actions.map(\.label).joined(separator: " ") }

    var keyboardShortcut: KeyboardShortcut? { Keymap.shared.shortcuts(for: self).first?.keyboardShortcut }
}

@MainActor
extension KeyPress {
    func matches(_ action: KeyAction) -> Bool {
        Keymap.shared.shortcuts(for: action).contains { $0.matches(self) }
    }

    /// The first action in these sections, in order, that this press is bound to.
    func action(in sections: KeySection...) -> KeyAction? {
        sections.lazy.flatMap(\.actions).first { matches($0) }
    }
}

extension View {
    @MainActor
    func keyboardShortcut(_ action: KeyAction) -> some View {
        keyboardShortcut(action.keyboardShortcut)
    }
}
