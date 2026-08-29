import SwiftUI
import AVFoundation
import UIKit

/// Aesthetic first-run mic briefing. CTA triggers the system Allow / Don't Allow prompt.
struct MicrophonePermissionView: View {
    var onGranted: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false
    @State private var pulse = false
    @State private var isRequesting = false
    @State private var showDeniedHint = false
    @State private var permission = AVAudioApplication.shared.recordPermission

    private var isDenied: Bool {
        permission == .denied
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        Haptics.light()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)

                VStack(spacing: 28) {
                    micHero
                        .scaleEffect(appeared ? 1 : 0.86)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 12) {
                        Text(isDenied ? "Microphone is off" : "We need your voice")
                            .font(Theme.fraunces(34, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(
                            isDenied
                                ? "Oracy can’t start your one-minute practice without the mic. You can turn it on in Settings."
                                : "Oracy listens for one minute so we can transcribe your speaking and give private, personal feedback."
                        )
                        .font(Theme.grotesk(16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                    VStack(alignment: .leading, spacing: 14) {
                        reasonRow(
                            icon: "waveform",
                            title: "One minute of speaking",
                            detail: "We only record while you practice — up to 60 seconds."
                        )
                        reasonRow(
                            icon: "lock.shield",
                            title: "Used for your feedback",
                            detail: "Audio is analyzed to score fluency, clarity, and pace."
                        )
                        reasonRow(
                            icon: "hand.raised",
                            title: "Under your control",
                            detail: "Not used to train AI models. Delete recordings anytime."
                        )
                    }
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    if showDeniedHint || isDenied {
                        Text("Permission was declined. You can enable it in iOS Settings.")
                            .font(Theme.grotesk(13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    Button {
                        Task { await handlePrimary() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRequesting {
                                ProgressView()
                                    .tint(Color(red: 0.98, green: 0.97, blue: 0.96))
                            }
                            Text(primaryTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(minHeight: 56, fontSize: 17))
                    .disabled(isRequesting)

                    Button {
                        Haptics.light()
                        onDismiss()
                    } label: {
                        Text("Not now")
                            .font(Theme.grotesk(16, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            refreshPermission()
            showDeniedHint = isDenied
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermission()
            if permission == .granted {
                Haptics.success()
                onGranted()
            }
        }
    }

    private func refreshPermission() {
        permission = AVAudioApplication.shared.recordPermission
    }

    private var primaryTitle: String {
        if isDenied { return "Open Settings" }
        return "Continue"
    }

    private var micHero: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.accent.opacity(colorScheme == .dark ? 0.35 : 0.22),
                            Theme.accent.opacity(0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 140
                    )
                )
                .frame(width: 260, height: 260)
                .scaleEffect(pulse ? 1.06 : 0.94)

            Circle()
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
                .frame(width: 168, height: 168)
                .scaleEffect(pulse ? 1.04 : 0.98)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.82, green: 0.56, blue: 0.46),
                            Theme.accent,
                            Color(red: 0.48, green: 0.30, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 112)
                .shadow(
                    color: Theme.accent.opacity(colorScheme == .dark ? 0.35 : 0.18),
                    radius: 18,
                    y: 8
                )

            Image(systemName: "mic.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color(red: 0.99, green: 0.97, blue: 0.94))
                .accessibilityHidden(true)
        }
        .frame(height: 220)
        .accessibilityHidden(true)
    }

    private func reasonRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accentMuted)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.grotesk(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.grotesk(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func handlePrimary() async {
        Haptics.soft()
        if isDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }

        isRequesting = true
        let granted = await AVAudioApplication.requestRecordPermission()
        isRequesting = false
        refreshPermission()

        if granted {
            Haptics.success()
            onGranted()
        } else {
            Haptics.warning()
            withAnimation(.easeOut(duration: 0.2)) {
                showDeniedHint = true
            }
        }
    }
}
