import SwiftUI

struct Popup<Content: View>: View {
    var title: String
    var accent: Color = Theme.cyan
    var width: CGFloat = 380
    var dismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
            VStack(alignment: .leading, spacing: 12) {
                NamePlate(name: title, color: accent, shadowColor: Theme.deep)
                content
            }
            .panel(accent: accent, padding: 20)
            .frame(width: width)
        }
        .background {
            Button("", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}
