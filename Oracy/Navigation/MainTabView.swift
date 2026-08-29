import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0
    /// Bumps when Home should shuffle from a device shake.
    @State private var homeShakeToken = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: 0) {
                HomeView(shakeShuffleToken: homeShakeToken)
            } label: {
                Label {
                    Text("Home")
                } icon: {
                    Image(uiImage: homeTabIcon)
                }
            }

            Tab("History", systemImage: "clock.fill", value: 1) {
                HistoryView()
            }
        }
        .tint(Theme.accent)
        // System Liquid Glass tab bar; minimize on scroll so content stays primary.
        .tabBarMinimizeBehavior(.onScrollDown)
        .onShake {
            guard selectedTab == 0 else { return }
            homeShakeToken &+= 1
        }
    }

    /// Match SF Symbol tab size (25pt). Light `app-logo-with-bg` reads small
    /// against the glass bar, so it gets +10. Dark uses `app-no-bg-dark`.
    private var homeTabIcon: UIImage {
        let isDark = colorScheme == .dark
        let name = isDark ? "app-no-bg-dark" : "app-logo-with-bg"
        return Self.makeHomeTabIcon(named: name, pointSize: isDark ? 25 : 35)
    }

    private static func makeHomeTabIcon(named: String, pointSize: CGFloat) -> UIImage {
        let source = UIImage(named: named) ?? UIImage()
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let size = CGSize(width: pointSize, height: pointSize)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}
