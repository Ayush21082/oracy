import SwiftUI

/// App brand mark from the `app-logo` asset.
struct AppLogoMark: View {
    var size: CGFloat = 96
    var showsWordmark: Bool = false

    private let brandName = "Oracy"
    private let tagline = "Speak once. Mean it."

    var body: some View {
        VStack(spacing: size * 0.14) {
            Image("app-logo")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.224, style: .continuous))
                .accessibilityHidden(true)

            if showsWordmark {
                VStack(spacing: 2) {
                    Text(brandName)
                        .font(Theme.fraunces(size * 0.28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(tagline)
                        .font(Theme.grotesk(size * 0.11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview {
    AppLogoMark(size: 96, showsWordmark: true)
        .padding()
        .themeBackground()
}
#endif
