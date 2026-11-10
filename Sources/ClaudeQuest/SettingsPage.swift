import SwiftUI
import AppKit

struct SettingsPage: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var sprites = SpriteSettings.shared
    @AppStorage(DialogueBox.showSpriteKey) private var showSprite = false
    @ViewState private var selected = 0
    @FocusState private var focused: Bool

    private enum Row: Hashable {
        case portrait, sprite(ClaudeModel), folder
    }

    private let rows: [Row] = [.portrait] + ClaudeModel.allCases.map(Row.sprite) + [.folder]

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            NamePlate(name: "SETTINGS", color: Theme.gold, shadowColor: Theme.ocean)
                .padding(.horizontal, 18)
                .zIndex(1)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    portraitRow
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SPRITES").font(Theme.ui(13, weight: .black)).foregroundStyle(Theme.gold)
                        Text("The portrait each model wears").font(Theme.ui(11)).foregroundStyle(Theme.dim)
                    }
                    .padding(.top, 6)
                    ForEach(ClaudeModel.allCases) { spriteRow($0) }
                    folderRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                preview
            }
            .padding(.top, 6)
            .padding(.bottom, 18)
            .panel(accent: Theme.gold, padding: 18, opacity: 1)
            .overlay(alignment: .bottomTrailing) {
                KeyHints(hints: [(KeyAction.label(.down, .up), "select"), (KeyAction.select.label, "change"), (KeyAction.back.label, "map")])
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
        .onAppear {
            focused = true
            sprites.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in sprites.reload() }
    }

    private var portraitRow: some View {
        HStack(spacing: 10) {
            RowMarker(active: rows[selected] == .portrait)
            Text("Show portrait").font(Theme.body).foregroundStyle(Theme.ice)
            Button { showSprite.toggle() } label: { Chip(active: showSprite, color: Theme.gold) { Text(showSprite ? "ON" : "OFF") } }
                .buttonStyle(.plain)
            Text(KeyAction.sprite.label).font(Theme.ui(12)).foregroundStyle(Theme.dim)
        }
    }

    private func spriteRow(_ model: ClaudeModel) -> some View {
        let chosen = sprites.pack(for: model)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            RowMarker(active: rows[selected] == .sprite(model))
            Text(model.label).font(Theme.body).foregroundStyle(Theme.ice).frame(width: 70, alignment: .leading)
            FlowLayout(spacing: 8, lineSpacing: 6) {
                option(PixelSprite.of(model).name, active: chosen == nil) { sprites.choose(nil, for: model) }
                ForEach(sprites.packs, id: \.name) { pack in
                    option(pack.name, active: chosen === pack) { sprites.choose(pack, for: model) }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = rows.firstIndex(of: .sprite(model)) ?? selected }
    }

    private func option(_ name: String, active: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) { Chip(active: active, color: Theme.gold) { Text(name.uppercased()) } }
            .buttonStyle(.plain)
    }

    private var folderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            RowMarker(active: rows[selected] == .folder)
            VStack(alignment: .leading, spacing: 6) {
                Button(action: openFolder) { Chip(color: Theme.cyan) { Text("OPEN SPRITES FOLDER") } }
                    .buttonStyle(.plain)
                Text("Add a set as a folder holding idle.png, and optionally thinking.png, talking.png and worried.png, "
                     + "<mood>-blink.png frames and talking-open.png. Sets with several outfits use a manifest.json; see the README.")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
    }

    private var previewModel: ClaudeModel {
        if case .sprite(let model) = rows[selected] { return model }
        return store.selected?.model ?? .sonnet
    }

    private var preview: some View {
        TimelineView(.periodic(from: .now, by: 1.6)) { timeline in
            let moods = Mood.allCases
            let mood = moods[Int(timeline.date.timeIntervalSinceReferenceDate / 1.6) % moods.count]
            VStack(spacing: 4) {
                Portrait(mood: mood, outfit: 0, model: previewModel, pack: sprites.pack(for: previewModel))
                    .frame(width: 168, height: 198)
                Text(mood.rawValue.uppercased()).font(Theme.ui(11, weight: .black)).foregroundStyle(Theme.dim)
            }
        }
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
            case .portrait: showSprite.toggle()
            case .sprite(let model): chooseNext(for: model)
            case .folder: openFolder()
            }
        default: return .ignored
        }
        return .handled
    }

    private func chooseNext(for model: ClaudeModel) {
        let options: [SpritePack?] = [nil] + sprites.packs
        let index = options.firstIndex { $0 === sprites.pack(for: model) } ?? 0
        sprites.choose(options[(index + 1) % options.count], for: model)
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: SpriteSettings.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(SpriteSettings.folder)
    }
}
