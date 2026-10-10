import SwiftUI

struct CueSettingsStatusLabel: View {
    let text: String
    let color: Color
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func cueSettingsFormAppearance() -> some View {
        // Form owns scrolling and section surfaces on both supported UI generations.
        formStyle(.grouped)
    }
}
