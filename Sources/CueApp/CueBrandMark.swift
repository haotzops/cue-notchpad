import AppKit
import SwiftUI

/// The supplied black SVG is treated as a template so the prompt chrome can
/// render it in white on its dark background.
struct CueBrandMark: View {
    private static let logo: NSImage? = {
        let url = Bundle.main.url(forResource: "logo", withExtension: "svg")
            ?? Bundle.module.url(forResource: "logo", withExtension: "svg")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        HStack(spacing: 5) {
            if let logo = Self.logo {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.white)
            }

            Text("cue")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white)
        }
    }
}
