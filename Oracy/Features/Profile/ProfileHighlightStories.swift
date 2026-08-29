import SwiftUI
import UIKit
import Photos

// MARK: - Story model

struct ProfileHighlightStory: Identifiable {
    let id = UUID()
    let eyebrow: String
    let title: String
    let subtitle: String
    let accentEmoji: String
    let gradient: [Color]
}

enum ProfileCelebration {
    private static let forceKey = "debug.forceCelebrate"

    /// Settings toggle — forces the glowing border + highlights regardless of stats.
    static var debugForceCelebrate: Bool {
        get { UserDefaults.standard.bool(forKey: forceKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceKey) }
    }

    /// Warm “doing great” bar — streak or a lively practice week.
    static func isDoingGreat(streak: Int, daysPracticedThisWeek: Int, activeDays: Int) -> Bool {
        if debugForceCelebrate { return true }
        return streak >= 3 || daysPracticedThisWeek >= 4 || activeDays >= 12
    }

    static func stories(
        displayName: String,
        streak: Int,
        totalWords: Int,
        totalMinutes: Int,
        daysPracticedThisWeek: Int,
        activeDays: Int
    ) -> [ProfileHighlightStory] {
        [
            ProfileHighlightStory(
                eyebrow: "Oracy",
                title: "You’re on a roll,\n\(displayName).",
                subtitle: "Tap through your highlights — a little proof that showing up compounds.",
                accentEmoji: "✨",
                gradient: [
                    Color(red: 0.42, green: 0.28, blue: 0.24),
                    Color(red: 0.66, green: 0.42, blue: 0.34),
                    Color(red: 0.88, green: 0.62, blue: 0.48)
                ]
            ),
            ProfileHighlightStory(
                eyebrow: "Streak",
                title: streak > 0 ? "\(streak) day streak" : "Fresh start",
                subtitle: streak > 0
                    ? "Consistency is the quiet flex. Keep the flame lit."
                    : "Your next session starts the streak.",
                accentEmoji: "🔥",
                gradient: [
                    Color(red: 0.55, green: 0.28, blue: 0.18),
                    Color(red: 0.92, green: 0.48, blue: 0.28),
                    Color(red: 0.95, green: 0.72, blue: 0.40)
                ]
            ),
            ProfileHighlightStory(
                eyebrow: "Voice",
                title: formattedWords(totalWords),
                subtitle: "Words spoken out loud — not typed, not thought. Spoken.",
                accentEmoji: "💬",
                gradient: [
                    Color(red: 0.22, green: 0.32, blue: 0.48),
                    Color(red: 0.35, green: 0.55, blue: 0.78),
                    Color(red: 0.55, green: 0.78, blue: 0.82)
                ]
            ),
            ProfileHighlightStory(
                eyebrow: "Practice",
                title: "\(totalMinutes) min practiced",
                subtitle: activeDays == 1
                    ? "1 day alive on your year grid."
                    : "\(activeDays) days alive on your year grid.",
                accentEmoji: "🎙️",
                gradient: [
                    Color(red: 0.22, green: 0.38, blue: 0.32),
                    Color(red: 0.40, green: 0.62, blue: 0.48),
                    Color(red: 0.72, green: 0.82, blue: 0.55)
                ]
            ),
            ProfileHighlightStory(
                eyebrow: "This week",
                title: "\(daysPracticedThisWeek)/7 days",
                subtitle: daysPracticedThisWeek >= 4
                    ? "A strong week — your pulse is loud and clear."
                    : "Room to grow. One more session tilts the week.",
                accentEmoji: "📈",
                gradient: [
                    Color(red: 0.32, green: 0.24, blue: 0.38),
                    Color(red: 0.58, green: 0.40, blue: 0.55),
                    Color(red: 0.88, green: 0.68, blue: 0.58)
                ]
            )
        ]
    }

    private static func formattedWords(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk words", Double(n) / 1000.0)
        }
        return "\(n) words"
    }
}

// MARK: - Stories viewer

struct ProfileHighlightStoriesView: View {
    let stories: [ProfileHighlightStory]
    let displayName: String
    var avatarImage: UIImage? = nil
    var avatarURL: URL? = nil
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var progress: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var showConfetti = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var pauseTimer = false
    @State private var advanceTask: Task<Void, Never>?

    private let storyDuration: TimeInterval = 5.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                storyCanvas(size: geo.size)
                    .offset(y: dragOffset)
                    .gesture(dismissDrag)

                // Tap zones
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { goPrevious() }
                        .frame(width: geo.size.width * 0.28)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { goNext() }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    progressBars
                        .padding(.horizontal, 12)
                        .padding(.top, 10)

                    topChrome
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    Spacer()
                }
                .offset(y: dragOffset)

                if showConfetti && !reduceMotion {
                    ConfettiCannonView()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .statusBarHidden(true)
        .task {
            showConfetti = true
            startStoryClock(from: 0)
        }
        .onDisappear { advanceTask?.cancel() }
        .onChange(of: index) { _, _ in
            progress = 0
            startStoryClock(from: 0)
        }
        .onChange(of: pauseTimer) { _, paused in
            if paused {
                advanceTask?.cancel()
            } else {
                startStoryClock(from: progress)
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            pauseTimer = false
        }) {
            if let shareImage {
                ProfileStoryShareSheet(
                    image: shareImage,
                    storyTitle: stories[index].title.replacingOccurrences(of: "\n", with: " "),
                    onDismiss: { showShareSheet = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
    }

    private var current: ProfileHighlightStory { stories[index] }

    private func storyCanvas(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: current.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft parchment wash
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    .clear,
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Text(current.accentEmoji)
                    .font(.system(size: 54))
                    .padding(.bottom, 4)

                Text(current.eyebrow.uppercased())
                    .font(Theme.grotesk(12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.7))

                Text(current.title)
                    .font(Theme.fraunces(40, weight: .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.8)

                Text(current.subtitle)
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 24)

                ProfileAvatarView(
                    size: 72,
                    borderWidth: 2.5,
                    isCelebrating: true,
                    uiImage: avatarImage,
                    imageURL: avatarImage == nil ? avatarURL : nil
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 96)
            .padding(.bottom, 48)
            .frame(width: size.width, height: size.height)
            .id(current.id)
            .transition(.opacity)
        }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(stories.indices, id: \.self) { i in
                GeometryReader { bar in
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: bar.size.width * fill(for: i))
                }
                .frame(height: 2.5)
            }
        }
    }

    private func fill(for i: Int) -> CGFloat {
        if i < index { return 1 }
        if i > index { return 0 }
        return progress
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                size: 32,
                borderWidth: 1.5,
                isCelebrating: false,
                uiImage: avatarImage,
                imageURL: avatarImage == nil ? avatarURL : nil
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(Theme.grotesk(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Highlights")
                    .font(Theme.grotesk(11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Spacer()
            Button {
                pauseTimer = true
                renderAndShare()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")

            Button {
                Haptics.light()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if value.translation.height > 0 {
                    pauseTimer = true
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 140 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                    pauseTimer = false
                }
            }
    }

    private func goNext() {
        Haptics.selectionChanged()
        if index < stories.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                index += 1
            }
        } else {
            onClose()
        }
    }

    private func goPrevious() {
        Haptics.selectionChanged()
        if progress > 0.2 {
            progress = 0
            startStoryClock(from: 0)
            return
        }
        if index > 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                index -= 1
            }
        } else {
            progress = 0
            startStoryClock(from: 0)
        }
    }

    private func startStoryClock(from start: CGFloat) {
        advanceTask?.cancel()
        progress = start
        guard !pauseTimer else { return }

        if reduceMotion {
            // Manual advance only when reduce motion is on.
            progress = 0
            return
        }

        let remaining = storyDuration * (1 - Double(start))
        advanceTask = Task { @MainActor in
            let steps = 60
            let step = remaining / Double(steps)
            for i in 0..<steps {
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled else { return }
                progress = start + CGFloat(i + 1) / CGFloat(steps) * (1 - start)
            }
            guard !Task.isCancelled else { return }
            goNext()
        }
    }

    private func renderAndShare() {
        let card = ShareableStoryCard(
            story: current,
            displayName: displayName,
            avatarImage: avatarImage
        )
            .frame(width: 390, height: 694)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            shareImage = uiImage
            showShareSheet = true
            Haptics.soft()
        } else {
            pauseTimer = false
        }
    }
}

// MARK: - Shareable card (for ImageRenderer)

private struct ShareableStoryCard: View {
    let story: ProfileHighlightStory
    let displayName: String
    var avatarImage: UIImage? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: story.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [Color.white.opacity(0.12), .clear, Color.black.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 20) {
                Spacer()
                Text(story.accentEmoji)
                    .font(.system(size: 56))
                Text(story.eyebrow.uppercased())
                    .font(Theme.grotesk(12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(story.title)
                    .font(Theme.fraunces(40, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text(story.subtitle)
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                HStack(spacing: 10) {
                    ProfileAvatarView(
                        size: 36,
                        borderWidth: 1.5,
                        isCelebrating: false,
                        uiImage: avatarImage
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(Theme.grotesk(14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Oracy")
                            .font(Theme.grotesk(11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Custom share sheet

struct ProfileStoryShareSheet: View {
    let image: UIImage
    let storyTitle: String
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSystemShare = false
    @State private var statusMessage: String?
    @State private var burstConfetti = false

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 22) {
                Capsule()
                    .fill(Theme.textSecondary.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                Text("Share this moment")
                    .font(Theme.fraunces(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(storyTitle)
                    .font(Theme.grotesk(14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Theme.shadow, radius: 16, y: 8)
                    .padding(.horizontal, 40)

                VStack(spacing: 10) {
                    shareRow(
                        icon: "square.and.arrow.up",
                        title: "Share image",
                        subtitle: "Messages, Mail, and more"
                    ) {
                        showSystemShare = true
                    }

                    shareRow(
                        icon: "camera.fill",
                        title: "Instagram Stories",
                        subtitle: instagramAvailable ? "Post as a story background" : "Instagram isn’t installed"
                    ) {
                        shareToInstagramStories()
                    }
                    .opacity(instagramAvailable ? 1 : 0.45)
                    .disabled(!instagramAvailable)

                    shareRow(
                        icon: "photo.on.rectangle",
                        title: "Save to Photos",
                        subtitle: "Keep a copy in your library"
                    ) {
                        saveToPhotos()
                    }
                }
                .padding(.horizontal, 20)

                if let statusMessage {
                    Text(statusMessage)
                        .font(Theme.grotesk(13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                }

                Spacer(minLength: 8)
            }

            if burstConfetti && !reduceMotion {
                ConfettiCannonView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showSystemShare) {
            ActivityView(activityItems: [image])
        }
    }

    private var instagramAvailable: Bool {
        UIApplication.shared.canOpenURL(URL(string: "instagram-stories://share")!)
    }

    private func shareRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accentMuted)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.grotesk(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.grotesk(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.cardBackground.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func shareToInstagramStories() {
        guard let url = URL(string: "instagram-stories://share"),
              let data = image.pngData() else {
            statusMessage = "Couldn’t open Instagram"
            return
        }

        let item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": data
        ]
        UIPasteboard.general.setItems(
            [item],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(url) { success in
            DispatchQueue.main.async {
                if success {
                    burstConfetti = true
                    statusMessage = "Opening Instagram…"
                } else {
                    statusMessage = "Couldn’t open Instagram"
                }
            }
        }
    }

    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    statusMessage = "Photos access needed"
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                burstConfetti = true
                Haptics.success()
                statusMessage = "Saved to Photos"
            }
        }
    }
}

// MARK: - UIKit activity bridge

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
