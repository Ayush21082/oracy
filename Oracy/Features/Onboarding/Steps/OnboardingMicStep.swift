import SwiftUI
import AVFoundation
import UIKit

struct OnboardingMicStep: View {
    var onContinue: () -> Void

    @State private var showActions = false
    @State private var isRequesting = false
    @State private var showDeniedHint = false
    @State private var permission = AVAudioApplication.shared.recordPermission

    private var isDenied: Bool { permission == .denied }
    private var isGranted: Bool { permission == .granted }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ConversationalText(
                lines: [
                    "Almost ready.",
                    "I'll need access to your microphone so I can listen when you speak."
                ],
                mode: .sequenced(delay: 0.55),
                font: Theme.fraunces(30, weight: .bold)
            ) {
                withAnimation(.themeBounce) { showActions = true }
            }
            .padding(.horizontal, 32)

            if showDeniedHint || isDenied {
                Text("Permission was declined. You can enable it later in Settings.")
                    .font(Theme.grotesk(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .transition(.opacity)
            }

            Spacer()

            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: isDenied ? "Open Settings" : "Allow microphone",
                    isLoading: isRequesting
                ) {
                    Task { await handlePrimary() }
                }

                if isDenied || showDeniedHint {
                    Button("Continue anyway") {
                        Haptics.light()
                        onContinue()
                    }
                    .font(Theme.grotesk(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .onboardingReveal(showActions)
        }
        .task {
            refreshPermission()
            if isGranted {
                onContinue()
            }
        }
    }

    private func refreshPermission() {
        permission = AVAudioApplication.shared.recordPermission
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
            AnalyticsService.shared.track(.onboardingMicResult, ["granted": "true"])
            onContinue()
        } else {
            Haptics.warning()
            AnalyticsService.shared.track(.onboardingMicResult, ["granted": "false"])
            withAnimation(.easeOut(duration: 0.2)) {
                showDeniedHint = true
            }
        }
    }
}
