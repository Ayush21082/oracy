import SwiftUI
import SceneKit
import UIKit

/// SceneKit-backed 3D dice view.
/// - Important: Deprecated for Home shuffle UX. Kept for possible future use (e.g. practice mode).
@available(*, deprecated, message: "3D dice overlay is no longer shown on Home. Prefer text shuffle animation.")
struct DiceSceneView: UIViewRepresentable {
    var reducedMotion: Bool
    var rollToken: UUID
    var onFinished: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        context.coordinator.controller.prepareView(view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onFinished = onFinished
        if context.coordinator.lastRollToken != rollToken {
            context.coordinator.lastRollToken = rollToken
            context.coordinator.controller.roll(reducedMotion: reducedMotion) { face in
                context.coordinator.onFinished(face)
            }
        }
    }

    final class Coordinator {
        var controller = DiceSceneController()
        var onFinished: (Int) -> Void
        var lastRollToken: UUID?

        init(onFinished: @escaping (Int) -> Void) {
            self.onFinished = onFinished
        }
    }
}

/// Full-screen overlay that rolls the die then dismisses.
/// - Important: Deprecated — Home no longer presents this. Shuffle animates the topic text instead.
@available(*, deprecated, message: "Removed from HomeView. Shuffle Topics now animates the prompt text directly.")
struct DiceRollOverlay: View {
    let reducedMotion: Bool
    let onComplete: (Int) -> Void

    @State private var rollToken = UUID()
    @State private var finished = false
    @State private var announced = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 20) {
                Text(finished ? "New topic ready" : "Rolling…")
                    .font(Theme.grotesk(15, weight: .medium))
                    .foregroundStyle(.white)

                // Intentionally still uses DiceSceneView for archival/demo; both are deprecated.
                DeprecatedDiceSceneBridge(
                    reducedMotion: reducedMotion,
                    rollToken: rollToken,
                    onFinished: { face in
                        guard !finished else { return }
                        finished = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            onComplete(face)
                        }
                    }
                )
                .frame(height: 280)
                .accessibilityLabel(finished ? "Dice settled" : "Rolling dice")
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 32)
        }
        .onAppear {
            if !announced {
                announced = true
                UIAccessibility.post(notification: .announcement, argument: "Rolling dice")
            }
        }
    }
}

/// Non-deprecated wrapper so the deprecated overlay can still compile without warning cascades.
private struct DeprecatedDiceSceneBridge: UIViewRepresentable {
    var reducedMotion: Bool
    var rollToken: UUID
    var onFinished: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        context.coordinator.controller.prepareView(view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onFinished = onFinished
        if context.coordinator.lastRollToken != rollToken {
            context.coordinator.lastRollToken = rollToken
            context.coordinator.controller.roll(reducedMotion: reducedMotion) { face in
                context.coordinator.onFinished(face)
            }
        }
    }

    final class Coordinator {
        var controller = DiceSceneController()
        var onFinished: (Int) -> Void
        var lastRollToken: UUID?

        init(onFinished: @escaping (Int) -> Void) {
            self.onFinished = onFinished
        }
    }
}
