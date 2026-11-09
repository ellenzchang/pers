import SwiftUI
import AppKit

@main
struct ClaudeQuestApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = AppStore()
    @ObservedObject private var keymap = Keymap.shared

    var body: some Scene {
        WindowGroup("Claude Quest") {
            ContentView()
                .environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.save()
                    store.runs.forEach { $0.stop() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { store.newTab() }.keyboardShortcut(.newTab)
                Button("Close Tab") { store.selected.map(store.close) }.keyboardShortcut(.closeTab)
            }
            CommandMenu("Party") {
                Button("Previous Model") { cycleModel(by: -1) }.keyboardShortcut(.previousModel)
                Button("Next Model") { cycleModel(by: 1) }.keyboardShortcut(.nextModel)
                Button("Next Mode") { cycleMode() }.keyboardShortcut(.nextMode)
                Button("Next Effort") { cycleEffort() }.keyboardShortcut(.nextEffort)
                Divider()
                Button("Toggle Diff") { store.selected?.toggleDiff() }.keyboardShortcut(.toggleDiff)
                Button("Toggle Diff Base") { store.selected?.toggleDiffBase() }.keyboardShortcut(.toggleDiffBase)
                Button("Toggle Git Log") { store.selected?.toggleLog() }.keyboardShortcut(.toggleLog)
                Button("Previous Tab") { cycleTab(by: -1) }.keyboardShortcut(.previousTab)
                Button("Next Tab") { cycleTab(by: 1) }.keyboardShortcut(.nextTab)
            }
            CommandMenu("Go") {
                Button("Map") { store.showingMap.toggle() }.keyboardShortcut(.map)
            }
        }
    }

    private func cycleModel(by offset: Int) {
        guard let session = store.selected else { return }
        session.model = cycled(session.model, in: ClaudeModel.allCases, by: offset)
    }

    private func cycleMode() {
        guard let session = store.selected else { return }
        session.mode = cycled(session.mode, in: PermissionMode.allCases)
    }

    private func cycleEffort() {
        guard let session = store.selected else { return }
        session.effort = cycled(session.effort, in: [nil] + Effort.allCases)
    }

    private func cycled<Value: Equatable>(_ value: Value, in values: [Value], by offset: Int = 1) -> Value {
        let index = values.firstIndex(of: value) ?? 0
        return values[(index + offset + values.count) % values.count]
    }

    private func cycleTab(by offset: Int) {
        if store.page != .sessions && !store.showingMap { return }
        let sessions = store.repos.flatMap(\.sessions)
        guard let index = sessions.firstIndex(where: { $0.id == store.selectedId }) else { return }
        store.selectedId = sessions[(index + offset + sessions.count) % sessions.count].id
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM binary rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Answering a permission prompt after the CLI has exited writes to a closed pipe; don't let that kill the app.
        signal(SIGPIPE, SIG_IGN)
    }
}
