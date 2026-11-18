import SwiftUI
import AppKit

struct SettingsPage: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var sprites = SpriteSettings.shared
    @ObservedObject private var fonts = FontSettings.shared
    @AppStorage(DialogueBox.showSpriteKey) private var showSprite = false
    // Changing the font size rebuilds the whole window, so the cursor has to live outside the view.
    @AppStorage("settingsRow") private var selected = 0
    @FocusState private var focused: Bool

    private enum Row: Hashable {
        case portrait, sprite(ClaudeModel), folder, fontSize, fontDefault, fontPrevious
    }

    private let rows: [Row] = [.portrait] + ClaudeModel.allCases.map(Row.sprite) + [.folder, .fontSize, .fontDefault, .fontPrevious]

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            NamePlate(name: "SETTINGS", color: Theme.gold, shadowColor: Theme.ocean)
                .padding(.horizontal, 18)
                .zIndex(1)
            HStack(alignment: .top, spacing: 18) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            portraitRow.id(Row.portrait)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("SPRITES").font(Theme.ui(13, weight: .black)).foregroundStyle(Theme.gold)
                                Text("The portrait each model wears").font(Theme.ui(11)).foregroundStyle(Theme.dim)
                            }
                            .padding(.top, 6)
                            ForEach(ClaudeModel.allCases) { spriteRow($0).id(Row.sprite($0)) }
                            folderRow.id(Row.folder)
                            fontSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: selected) { proxy.scrollTo(rows[selected]) }
                }
                preview
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
        .onAppear {
            focused = true
            sprites.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in sprites.reload() }
    }

    private var hints: [(key: String, action: String)] {
        let options = KeyAction.label(.previousOption, .nextOption)
        let change: (String, String) = switch rows[selected] {
        case .fontSize: (options, "resize")
        case .sprite: (options, "switch")
        default: (KeyAction.select.label, "change")
        }
        return [(KeyAction.label(.down, .up), "select"), change, (KeyAction.back.label, "map")]
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
                option(PixelSprite.of(model).name, active: chosen == nil) { choose(nil, for: model) }
                ForEach(sprites.packs, id: \.name) { pack in
                    option(pack.name, active: chosen === pack) { choose(pack, for: model) }
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

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("FONT SIZE").font(Theme.ui(13, weight: .black)).foregroundStyle(Theme.gold)
                Text("Scales the text across the app").font(Theme.ui(11)).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 10) {
                RowMarker(active: rows[selected] == .fontSize)
                Text("A").font(Theme.ui(11, scale: 1)).foregroundStyle(Theme.dim)
                Slider(value: $fonts.draft, in: FontSettings.range, step: FontSettings.step) { editing in
                    if editing {
                        selected = rows.firstIndex(of: .fontSize) ?? selected
                    } else {
                        fonts.applyDraft()
                        focused = true
                    }
                }
                .tint(Theme.gold)
                Text("A").font(Theme.ui(18, scale: 1)).foregroundStyle(Theme.dim)
                Text(FontSettings.label(fonts.draft))
                    .font(Theme.ui(13, weight: .black))
                    .foregroundStyle(rows[selected] == .fontSize ? Theme.gold : Theme.ice)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .id(Row.fontSize)
            fontPreview
            HStack(spacing: 10) {
                RowMarker(active: rows[selected] == .fontDefault)
                Button { fonts.choose(FontSettings.defaultScale) } label: { Chip(color: Theme.red) { Text("RESET TO DEFAULT") } }
                    .buttonStyle(.plain)
                    .disabled(fonts.scale == FontSettings.defaultScale)
                Text(FontSettings.label(FontSettings.defaultScale)).font(Theme.ui(12)).foregroundStyle(Theme.dim)
            }
            .id(Row.fontDefault)
            HStack(spacing: 10) {
                RowMarker(active: rows[selected] == .fontPrevious)
                Button { fonts.restorePrevious() } label: { Chip(color: Theme.cyan) { Text("BACK TO PREVIOUS") } }
                    .buttonStyle(.plain)
                    .disabled(fonts.previous == nil)
                Text(fonts.previous.map(FontSettings.label) ?? "No earlier size yet").font(Theme.ui(12)).foregroundStyle(Theme.dim)
            }
            .id(Row.fontPrevious)
        }
        .padding(.top, 6)
    }

    private var fontPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREVIEW").font(Theme.ui(10, weight: .black)).foregroundStyle(Theme.dim)
            Text("Claude reads the file and proposes a fix.").font(Theme.body(scale: fonts.draft)).foregroundStyle(Theme.text)
            Text("swift build -c release").font(Theme.code(scale: fonts.draft)).foregroundStyle(Theme.cyan)
            Text("Labels, hints and buttons use this size.").font(Theme.ui(12, scale: fonts.draft)).foregroundStyle(Theme.dim)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Slant(amount: 6).fill(Theme.codeBackground))
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
        switch press.action(in: .navigation, .settings) {
        case .previousOption: return adjust(by: -1)
        case .nextOption: return adjust(by: 1)
        case .back: store.showingMap = true
        case .down: selected = min(selected + 1, rows.count - 1)
        case .up: selected = max(selected - 1, 0)
        case .top: selected = 0
        case .bottom: selected = rows.count - 1
        case .select where press.phase == .down:
            switch rows[selected] {
            case .portrait: showSprite.toggle()
            case .sprite(let model): cycleSprite(for: model, by: 1)
            case .folder: openFolder()
            case .fontSize: return .ignored
            case .fontDefault: fonts.choose(FontSettings.defaultScale)
            case .fontPrevious: fonts.restorePrevious()
            }
        default: return .ignored
        }
        return .handled
    }

    private func adjust(by offset: Int) -> KeyPress.Result {
        switch rows[selected] {
        case .fontSize: fonts.nudge(by: offset)
        case .sprite(let model): cycleSprite(for: model, by: offset)
        default: return .ignored
        }
        return .handled
    }

    private func cycleSprite(for model: ClaudeModel, by offset: Int) {
        let options: [SpritePack?] = [nil] + sprites.packs
        let index = options.firstIndex { $0 === sprites.pack(for: model) } ?? 0
        sprites.choose(options[(index + offset + options.count) % options.count], for: model)
    }

    private func choose(_ pack: SpritePack?, for model: ClaudeModel) {
        selected = rows.firstIndex(of: .sprite(model)) ?? selected
        sprites.choose(pack, for: model)
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: SpriteSettings.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(SpriteSettings.folder)
    }
}
