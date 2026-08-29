import SwiftUI
import UIKit
import CoreMotion
import Combine

/// Full-bleed expanded profile photo with gyro tilt.
struct ProfilePhotoLightbox: View {
    var displayName: String
    var isCelebrating: Bool
    var uiImage: UIImage? = nil
    var imageURL: URL? = nil
    var onClose: () -> Void
    var onOpenHighlights: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = PhotoGyroSampler()
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var motionActive = false

    private var hasCustomPhoto: Bool { uiImage != nil || imageURL != nil }

    var body: some View {
        ZStack {
            lightboxBackdrop
                .opacity((appeared ? 1 : 0) * (1 - min(dragOffset / 320, 0.7)))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 20) {
                Spacer(minLength: 24)

                gyroPhoto
                    .scaleEffect(appeared ? 1 : 0.42)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: dragOffset)
                    .gesture(dismissDrag)

                VStack(spacing: 6) {
                    Text(displayName)
                        .font(Theme.fraunces(26, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(isCelebrating ? "Looking sharp today" : "Profile photo")
                        .font(Theme.grotesk(14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .opacity(appeared ? (1 - Double(min(dragOffset / 180, 1))) : 0)
                .offset(y: appeared ? 0 : 12)

                VStack(spacing: 12) {
                    if isCelebrating, let onOpenHighlights {
                        Button {
                            Haptics.soft()
                            onOpenHighlights()
                        } label: {
                            Text("View highlights")
                                .font(Theme.grotesk(15, weight: .semibold))
                                .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.96))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .opacity(appeared ? (1 - Double(min(dragOffset / 180, 1))) : 0)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
        }
        .statusBarHidden(true)
        .onAppear {
            Haptics.soft()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.78)) {
                appeared = true
            }
            guard !reduceMotion else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                motion.start()
                motionActive = true
            }
        }
        .onDisappear {
            motion.stop()
            motionActive = false
        }
    }

    private var gyroPhoto: some View {
        let tiltX = motionActive ? Double(motion.nx - 0.5) * 10 : 0
        let tiltY = motionActive ? Double(0.5 - motion.ny) * 8 : 0
        let parallaxX = motionActive ? (motion.nx - 0.5) * 14 : 0
        let parallaxY = motionActive ? (motion.ny - 0.5) * 10 : 0

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.accent.opacity(hasCustomPhoto ? 0.28 : 0.42),
                            Color(red: 0.98, green: 0.86, blue: 0.55).opacity(0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 170
                    )
                )
                .frame(width: 340, height: 340)
                .blur(radius: 36)
                .offset(x: parallaxX * 0.4, y: parallaxY * 0.4)

            ZStack {
                Color.white
                photoContent
                    .scaledToFill()
                    .frame(width: 280, height: 280)
                    .scaleEffect(1.08)
                    .offset(x: parallaxX, y: parallaxY)
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.12),
                                    Theme.accent.opacity(0.45)
                                ],
                                startPoint: UnitPoint(x: motion.nx, y: 0),
                                endPoint: UnitPoint(x: 1 - motion.nx, y: 1)
                            ),
                            lineWidth: 1.5
                        )
                }
                .overlay(alignment: .topLeading) {
                    // Gyro light sheen
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    .clear,
                                    .clear
                                ],
                                startPoint: UnitPoint(x: motion.nx - 0.2, y: 0),
                                endPoint: UnitPoint(x: motion.nx + 0.35, y: 0.7)
                            )
                        )
                        .blendMode(.softLight)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 28, y: 16)
        }
        .rotation3DEffect(.degrees(tiltX), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
        .rotation3DEffect(.degrees(tiltY), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
        .accessibilityLabel("Profile photo")
        .accessibilityHint("Tilt your phone for a parallax effect. Drag down or tap outside to close.")
    }

    private var lightboxBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.08, blue: 0.07).opacity(0.55),
                    Color(red: 0.18, green: 0.12, blue: 0.10).opacity(0.72),
                    Color.black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Theme.accent.opacity(0.34),
                    Color(red: 0.98, green: 0.86, blue: 0.55).opacity(0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.52, green: 0.72, blue: 0.56).opacity(0.16),
                    .clear
                ],
                center: UnitPoint(x: 0.15, y: 0.88),
                startRadius: 10,
                endRadius: 280
            )
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
        } else if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                case .failure, .empty:
                    defaultPhotoFill
                @unknown default:
                    defaultPhotoFill
                }
            }
        } else {
            defaultPhotoFill
        }
    }

    private var defaultPhotoFill: some View {
        ZStack {
            Color.white
            Image("bird")
                .resizable()
                .scaledToFit()
                .padding(48)
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 220 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        motion.stop()
        motionActive = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.88)) {
            appeared = false
            dragOffset = 160
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.12 : 0.28)) {
            onClose()
        }
    }
}

// MARK: - Gyro

@MainActor
private final class PhotoGyroSampler: ObservableObject {
    @Published var nx: CGFloat = 0.5
    @Published var ny: CGFloat = 0.5

    private let manager = CMMotionManager()
    private var timer: AnyCancellable?

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        timer = Timer.publish(every: 1 / 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard let motion = manager.deviceMotion else { return }
        let roll = CGFloat(motion.attitude.roll) / (.pi * 1.6)
        let pitch = CGFloat(motion.attitude.pitch) / (.pi * 1.3)
        let targetX = min(1, max(0, roll + 0.5))
        let targetY = min(1, max(0, pitch + 0.5))
        let nextX = nx + (targetX - nx) * 0.1
        let nextY = ny + (targetY - ny) * 0.1
        if abs(nextX - nx) > 0.003 { nx = nextX }
        if abs(nextY - ny) > 0.003 { ny = nextY }
    }
}
