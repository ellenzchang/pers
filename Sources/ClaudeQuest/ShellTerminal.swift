import AppKit
import SwiftTerm
import SwiftUI

/// A terminal command running in its own emulator. The chat shows its text, and the view can be opened to use it like a native terminal.
@MainActor
final class ShellTerminal: NSObject, LocalProcessTerminalViewDelegate {
    let view: LocalProcessTerminalView
    let command: String
    private(set) var directory: String?
    /// What the running program wants from the keyboard.
    struct Mode: Equatable {
        /// Drawing on the alternate screen, like vim or less.
        var fullScreen = false
        /// Line mode is off, so keys count as they're pressed, like a single-key [Y/n] prompt.
        var wantsKeys = false
        /// A whole line is read without echo, like a password.
        var hidesInput = false

        var interactive: Bool { fullScreen || wantsKeys }
    }

    var onOutput: (String, [ColorRun], Mode) -> Void = { _, _, _ in }
    private var mode = Mode()
    var onExit: (Int32?) -> Void = { _ in }
    private var refreshPending = false
    /// The chat shows only the tail, since re-reading and laying out the whole scrollback on every refresh lags behind
    /// long builds. The opened terminal keeps all of it.
    private static let chatLines = 500

    init(_ command: String, script: String, in directory: String) {
        self.command = command
        // Offscreen it still needs a size; a wide one keeps long lines from wrapping in the chat.
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 1400, height: 600), options: TerminalOptions(scrollback: 10_000, ansi256PaletteStrategy: .xterm))
        super.init()
        view.nativeBackgroundColor = NSColor(Theme.codeBackground)
        view.nativeForegroundColor = NSColor(Theme.text)
        // The chat draws bright colours like their base ones, and SwiftTerm brightens bold text, so both halves get the same colours.
        view.installColors((Theme.ansi + Theme.ansi).map(SwiftTerm.Color.init))
        view.processDelegate = self
        view.setProcessOutputHandler { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        view.startProcess(executable: "/bin/zsh", args: ["-ilc", script],
                          environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: directory)
        pollMode()
    }

    func send(_ text: String) {
        view.send(txt: text)
    }

    var isFocused: Bool { view.window?.firstResponder === view }

    func focus() {
        view.window?.makeFirstResponder(view)
    }

    /// ⌃C first, like a terminal. Programs that catch or ignore it are killed after a second, along with
    /// the interactive shell, which ignores SIGTERM. Collected before signalling, since orphans lose their parent.
    func stop() {
        send("\u{03}")
        let pid = view.process.shellPid
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard view.process.running, view.process.shellPid == pid else { return }
            ([pid] + ActionRun.descendants(of: pid)).forEach { kill($0, SIGKILL) }
        }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            refresh()
        }
    }

    /// The normal buffer holds the scrollback; full-screen programs draw on the alternate one, which the chat leaves out.
    private func refresh() {
        refreshPending = false
        mode = currentMode()
        var rows = view.terminalContentSnapshot(region: .history(maximumScrollbackRows: Self.chatLines), buffer: .normal)?.rows ?? []
        while rows.first?.text.isEmpty == true { rows.removeFirst() }
        while rows.last?.text.isEmpty == true { rows.removeLast() }
        var text = ""
        var runs: [ColorRun] = []
        func append(_ string: String, _ style: ColorRun.Style) {
            text += string
            if runs.last?.style == style {
                runs[runs.count - 1].length += string.count
            } else {
                runs.append(ColorRun(length: string.count, style: style))
            }
        }
        for row in rows {
            if !row.isWrapped && !text.isEmpty { append("\n", ColorRun.Style()) }
            // Wide characters leave an empty cell after them, and `text` is trimmed of the row's trailing blanks.
            for cell in row.cells.filter({ $0.width > 0 }).prefix(row.text.count) {
                append(cell.text.isEmpty ? " " : cell.text, ColorRun.Style(cell.attribute))
            }
        }
        onOutput(text, runs, mode)
    }

    /// Programs often switch modes after printing their prompt, so output alone doesn't catch every change.
    private func pollMode() {
        Task { [weak self] in
            while let self, view.process.running {
                if currentMode() != mode { refresh() }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// The pty master reports the line discipline the program set on its end.
    private func currentMode() -> Mode {
        let fullScreen = view.terminalInputStateSnapshot()?.isAlternateBuffer ?? false
        var settings = termios()
        guard tcgetattr(view.process.childfd, &settings) == 0 else { return Mode(fullScreen: fullScreen) }
        let canonical = settings.c_lflag & tcflag_t(ICANON) != 0
        let echo = settings.c_lflag & tcflag_t(ECHO) != 0
        return Mode(fullScreen: fullScreen, wantsKeys: !canonical, hidesInput: canonical && !echo)
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor in self.directory = directory }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            refresh()
            onExit(exitCode)
        }
    }
}

/// The running command's terminal, shown in place of the chat. ⌘. goes back.
struct TerminalPane: NSViewRepresentable {
    var terminal: ShellTerminal

    func makeNSView(context: Context) -> Container {
        let container = Container()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        if terminal.view.superview !== container { attach(to: container) }
    }

    private func attach(to container: Container) {
        container.subviews.forEach { $0.removeFromSuperview() }
        container.terminal = terminal
        terminal.view.frame = container.bounds
        terminal.view.autoresizingMask = [.width, .height]
        container.addSubview(terminal.view)
        container.focusTerminal()
    }

    /// A freshly opened pane isn't in the window yet, so focusing it has to wait until it is.
    final class Container: NSView {
        var terminal: ShellTerminal?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusTerminal()
        }

        func focusTerminal() {
            guard window != nil else { return }
            DispatchQueue.main.async { [terminal] in terminal?.focus() }
        }
    }
}

private extension ColorRun.Style {
    init(_ attribute: Attribute) {
        switch attribute.fg {
        case .ansi256(let code): ansi = code
        case .trueColor(let red, let green, let blue): rgb = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        case .defaultColor, .defaultInvertedColor: break
        }
        bold = attribute.style.contains(.bold)
    }
}

private extension SwiftTerm.Color {
    convenience init(_ color: SwiftUI.Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        let component = { (value: CGFloat) in UInt16(max(0, min(1, value)) * 65535) }
        self.init(red: component(rgb.redComponent), green: component(rgb.greenComponent), blue: component(rgb.blueComponent))
    }
}
