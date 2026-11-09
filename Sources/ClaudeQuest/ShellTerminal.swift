import AppKit
import SwiftTerm
import SwiftUI

/// The tab's zsh, kept open so its state carries from command to command, and shown in place of the chat when opened.
/// The shell marks where each command starts and ends, and each command's output is also played into an emulator
/// of its own for its chat message.
@MainActor
final class ShellTerminal: NSObject, TerminalViewDelegate, LocalProcessDelegate {
    let view: TerminalView
    private var process: LocalProcess!
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

    /// A command started, at this scroll-invariant row of the terminal.
    var onCommand: (_ command: String, _ row: Int) -> Void = { _, _ in }
    var onOutput: (String, [ColorRun], Mode) -> Void = { _, _, _ in }
    /// The shell is back at its prompt after a line, which may not have run a command if it didn't parse.
    var onPrompt: (_ status: Int32, _ directory: String) -> Void = { _, _ in }
    var onExit: () -> Void = {}
    /// The running command's output, for the chat.
    private var output: Terminal?
    private let outputSink = OutputSink()
    private var mode = Mode()
    private var ready = false
    /// The start of a mark that hasn't fully arrived.
    private var pending: [UInt8] = []
    private var refreshPending = false
    /// The chat shows only the tail, since re-reading and laying out the whole scrollback on every refresh lags behind
    /// long builds. The opened terminal keeps all of it.
    private static let chatLines = 500
    private static let markStart = Array("\u{1B}]133;".utf8)
    private static let bell: UInt8 = 0x07

    init(in directory: String) {
        // Offscreen it still needs a size; a wide one keeps long lines from wrapping in the chat.
        view = TerminalView(frame: NSRect(x: 0, y: 0, width: 1400, height: 600), options: TerminalOptions(scrollback: 10_000, ansi256PaletteStrategy: .xterm))
        super.init()
        view.nativeBackgroundColor = NSColor(Theme.codeBackground)
        view.nativeForegroundColor = NSColor(Theme.text)
        // The chat draws bright colours like their base ones, and SwiftTerm brightens bold text, so both halves get the same colours.
        view.installColors((Theme.ansi + Theme.ansi).map(SwiftTerm.Color.init))
        view.terminalDelegate = self
        process = LocalProcess(delegate: self, dispatchQueue: .main)
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        environment["CQ_USER_ZDOTDIR"] = environment["ZDOTDIR"] ?? NSHomeDirectory()
        environment["ZDOTDIR"] = Self.integration
        process.startProcess(executable: "/bin/zsh", args: ["-il"],
                             environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: directory)
    }

    /// Startup files that load the user's own, then add the hooks that mark commands. Pagers are off since the chat
    /// can't scroll them.
    private static let integration: String = {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-quest-zsh")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let load = { (file: String) in "ZDOTDIR=$CQ_USER_ZDOTDIR\n[[ -f $ZDOTDIR/\(file) ]] && source $ZDOTDIR/\(file)\n" }
        let files = [
            ".zshenv": "CQ_ZDOTDIR=$ZDOTDIR\n" + load(".zshenv") + "CQ_USER_ZDOTDIR=$ZDOTDIR\nZDOTDIR=$CQ_ZDOTDIR\n",
            ".zprofile": load(".zprofile") + "ZDOTDIR=$CQ_ZDOTDIR\n",
            ".zshrc": load(".zshrc") + """
                ZDOTDIR=$CQ_ZDOTDIR
                export PAGER=cat GIT_PAGER=cat
                __cq_prompt() { print -rn -- $'\\e]133;D;'"$?;$PWD"$'\\a' }
                __cq_command() { print -rn -- $'\\e]133;C;'"${${1//$'\\a'}//$'\\e'}"$'\\a' }
                precmd_functions=(__cq_prompt $precmd_functions)
                preexec_functions+=(__cq_command)

                """,
            ".zlogin": load(".zlogin") + "unset CQ_ZDOTDIR CQ_USER_ZDOTDIR\n",
        ]
        for (name, script) in files { try? script.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        return directory.path
    }()

    func send(_ text: String) {
        process.send(data: ArraySlice(text.utf8))
    }

    var isFocused: Bool { view.window?.firstResponder === view }

    func focus() {
        view.window?.makeFirstResponder(view)
    }

    /// Scrolls the terminal so this scroll-invariant row is at the top.
    func scroll(to row: Int) {
        guard let liveTop = view.terminalContentSnapshot(region: .history(maximumScrollbackRows: 0))?.liveTopRow else { return }
        view.scroll(toPosition: 1)
        if row < liveTop { view.scrollUp(lines: liveTop - row) }
    }

    /// ⌃C first, like a terminal. Programs that catch or ignore it are killed after a second. The shell itself stays.
    func stop() {
        send("\u{03}")
        let command = output
        let pid = process.shellPid
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard let command, output === command else { return }
            ActionRun.descendants(of: pid).forEach { kill($0, SIGKILL) }
        }
    }

    /// The interactive shell ignores SIGTERM, but a hangup ends it and its jobs, like closing a terminal window.
    func close() {
        if process.running { kill(process.shellPid, SIGHUP) }
    }

    private func received(_ bytes: ArraySlice<UInt8>) {
        var data = pending + bytes
        pending = []
        if let cut = Self.unfinishedMark(in: data) {
            pending = Array(data[cut...])
            data.removeSubrange(cut...)
        }
        var start = data.startIndex
        while let open = data[start...].firstRange(of: Self.markStart), let end = data[open.upperBound...].firstIndex(of: Self.bell) {
            play(data[start..<open.lowerBound])
            mark(String(decoding: data[open.upperBound..<end], as: UTF8.self))
            start = end + 1
        }
        play(data[start...])
    }

    /// Where a mark split across reads begins, so it waits for the rest instead of being shown.
    private static func unfinishedMark(in data: [UInt8]) -> Int? {
        guard let escape = data.lastIndex(of: 0x1B) else { return nil }
        let tail = data[escape...]
        if tail.starts(with: markStart) { return tail.contains(bell) ? nil : escape }
        return markStart.starts(with: tail) ? escape : nil
    }

    private func play(_ bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty else { return }
        view.feed(byteArray: bytes)
        guard let output else { return }
        output.feed(buffer: bytes)
        scheduleRefresh()
    }

    private func mark(_ payload: String) {
        let fields = payload.split(separator: ";", maxSplits: payload.hasPrefix("D") ? 2 : 1, omittingEmptySubsequences: false).map(String.init)
        switch fields.first {
        case "C":
            let size = view.terminalDimensions
            output = Terminal(delegate: outputSink, options: TerminalOptions(cols: size.cols, rows: size.rows, scrollback: Self.chatLines))
            mode = Mode()
            let row = view.terminalContentSnapshot(region: .history(maximumScrollbackRows: 0))?.cursorRow ?? 0
            onCommand(fields.count > 1 ? fields[1] : "", row)
            pollMode()
        case "D" where fields.count == 3:
            if output != nil { refresh() }
            output = nil
            // The first prompt comes before any line the shell has read.
            if ready { onPrompt(Int32(fields[1]) ?? 0, fields[2]) }
            ready = true
        default:
            break
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
        guard let output else { return }
        mode = currentMode()
        let snapshot = output.contentSnapshot(region: .history(maximumScrollbackRows: Self.chatLines), buffer: .normal).rows
        // Printed spaces aren't trimmed like unwritten cells, and zsh prints a line of them before each prompt to mark
        // output without a final newline. Spaces before a soft wrap are kept, since they separate words.
        var rows = snapshot.indices.map { index in
            let wraps = snapshot.indices.contains(index + 1) && snapshot[index + 1].isWrapped
            return (row: snapshot[index], text: wraps ? snapshot[index].text : String(snapshot[index].text.reversed().drop(while: \.isWhitespace).reversed()))
        }
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
        for (row, rowText) in rows {
            if !row.isWrapped && !text.isEmpty { append("\n", ColorRun.Style()) }
            // Wide characters leave an empty cell after them.
            for cell in row.cells.filter({ $0.width > 0 }).prefix(rowText.count) {
                append(cell.text.isEmpty ? " " : cell.text, ColorRun.Style(cell.attribute))
            }
        }
        onOutput(text, runs, mode)
    }

    /// Programs often switch modes after printing their prompt, so output alone doesn't catch every change.
    private func pollMode() {
        Task { [weak self] in
            while let self, output != nil {
                if currentMode() != mode { refresh() }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// The pty master reports the line discipline the program set on its end. At the prompt it's the shell's own
    /// line editor, so this only means something while a command runs.
    private func currentMode() -> Mode {
        let fullScreen = view.terminalInputStateSnapshot()?.isAlternateBuffer ?? false
        var settings = termios()
        guard tcgetattr(process.childfd, &settings) == 0 else { return Mode(fullScreen: fullScreen) }
        let canonical = settings.c_lflag & tcflag_t(ICANON) != 0
        let echo = settings.c_lflag & tcflag_t(ECHO) != 0
        return Mode(fullScreen: fullScreen, wantsKeys: !canonical, hidesInput: canonical && !echo)
    }

    nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { received(slice) }
    }

    nonisolated func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        MainActor.assumeIsolated { onExit() }
    }

    /// Only asked for when the process starts, on the main thread.
    nonisolated func getWindowSize() -> winsize {
        MainActor.assumeIsolated {
            let size = view.terminalDimensions
            return winsize(ws_row: UInt16(size.rows), ws_col: UInt16(size.cols), ws_xpixel: 0, ws_ypixel: 0)
        }
    }

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { process.send(data: data) }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated {
            var size = getWindowSize()
            _ = process.updateWindowSize(&size)
            output?.resize(cols: newCols, rows: newRows)
        }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// The chat's copy of a command's output only reads; the opened terminal answers the program's queries.
private final class OutputSink: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

/// The tab's terminal, shown in place of the chat. ⌘. goes back.
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
