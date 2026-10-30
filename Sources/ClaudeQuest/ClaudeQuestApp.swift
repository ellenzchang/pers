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
                ForEach(Array(ClaudeModel.allCases.enumerated()), id: \.element) { index, model in
                    Button("Model: \(model.label)") { store.selected?.model = model }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
                Divider()
                Button("Next Tab") { cycleTab(by: 1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { cycleTab(by: -1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }
    }

    private func cycleTab(by offset: Int) {
        guard let index = store.sessions.firstIndex(where: { $0.id == store.selectedId }) else { return }
        let count = store.sessions.count
        store.selectedId = store.sessions[(index + offset + count) % count].id
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM binary rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
