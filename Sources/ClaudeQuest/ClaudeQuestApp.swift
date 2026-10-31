import SwiftUI
import AppKit

@main
struct ClaudeQuestApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store = AppStore()

    static let modelKeys: [KeyEquivalent] = ["h", "j", "k", "l"]

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
                ForEach(Array(zip(ClaudeModel.allCases, Self.modelKeys)), id: \.0) { model, key in
                    Button("Model: \(model.label)") { store.selected?.model = model }
                        .keyboardShortcut(key, modifiers: [.command, .shift])
                }
                Divider()
                Button("Toggle Diff") { store.selected?.toggleDiff() }.keyboardShortcut("d")
                Button("Toggle Diff Base") { store.selected?.toggleDiffBase() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Previous Tab") { cycleTab(by: -1) }.keyboardShortcut("1")
                Button("Next Tab") { cycleTab(by: 1) }.keyboardShortcut("2")
            }
        }
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
