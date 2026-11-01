import SwiftUI
import AppKit

@main
struct ClaudeQuestApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Claude Quest") {
            ContentView()
                .environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.save()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { store.newTab() }.keyboardShortcut("t")
                Button("Close Tab") { store.selected.map(store.close) }.keyboardShortcut("w")
            }
            CommandMenu("Party") {
                Button("Previous Model") { cycleModel(by: -1) }.keyboardShortcut("j")
                Button("Next Model") { cycleModel(by: 1) }.keyboardShortcut("k")
                Divider()
                Button("Toggle Diff") { store.selected?.toggleDiff() }.keyboardShortcut("d")
                Button("Toggle Diff Base") { store.selected?.toggleDiffBase() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Previous Tab") { cycleTab(by: -1) }.keyboardShortcut("1")
                Button("Next Tab") { cycleTab(by: 1) }.keyboardShortcut("2")
            }
        }
    }

    private func cycleModel(by offset: Int) {
        guard let session = store.selected else { return }
        let models = ClaudeModel.allCases
        let index = models.firstIndex(of: session.model) ?? 0
        session.model = models[(index + offset + models.count) % models.count]
    }

    private func cycleTab(by offset: Int) {
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
