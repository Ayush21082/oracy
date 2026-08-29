import SwiftUI
import UserNotifications
import UIKit

struct OnboardingNotificationsStep: View {
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showActions = false
    @State private var isRequesting = false
    @State private var showDeniedHint = false
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var reminderTime = PracticeReminderService.shared.reminderTime
    @State private var showTimeWheel = false

    private var isDenied: Bool { status == .denied }
    private var isAuthorized: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ConversationalText(
                    lines: [
                        "One last thing.",
                        "Want a gentle nudge when it’s time to practice?"
                    ],
                    mode: .sequenced(delay: 0.55),
                    font: Theme.fraunces(30, weight: .bold)
                ) {
                    withAnimation(.themeBounce) {
                        showActions = true
                        showTimeWheel = true
                    }
                }
                .padding(.horizontal, 32)

                timePickerCard
                    .padding(.horizontal, 32)
                    .onboardingReveal(showActions)

                if showDeniedHint || isDenied {
                    Text("Permission was declined. You can turn reminders on later in Settings.")
                        .font(Theme.grotesk(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: isDenied ? "Open Settings" : "Allow notifications",
                    isLoading: isRequesting
                ) {
                    Task { await handlePrimary() }
                }

                if isDenied || showDeniedHint {
                    Button("Continue anyway") {
                        Haptics.light()
                        PracticeReminderService.shared.isEnabled = false
                        onContinue()
                    }
                    .font(Theme.grotesk(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                } else if showActions {
                    Button("Not now") {
                        Haptics.light()
                        PracticeReminderService.shared.isEnabled = false
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
            await refreshStatus()
            if isAuthorized {
                PracticeReminderService.shared.isEnabled = true
                PracticeReminderService.shared.reminderTime = reminderTime
                await PracticeReminderService.shared.refreshSchedule()
                onContinue()
            }
        }
    }

    private var timePickerCard: some View {
        VStack(spacing: 14) {
            Text("Remind me at")
                .font(Theme.grotesk(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(formattedReminderTime)
                .font(Theme.fraunces(44, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(
                    reduceMotion ? .easeOut(duration: 0.15) : .themeBounceSnappy,
                    value: formattedReminderTime
                )
                .accessibilityHidden(true)

            if showTimeWheel {
                DatePicker(
                    "Reminder time",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(Theme.accent)
                .frame(maxHeight: 132)
                .clipped()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityLabel("Reminder time")
                .onChange(of: reminderTime) { _, _ in
                    Haptics.selectionChanged()
                }
            }

            Text("You can change this anytime in Settings.")
                .font(Theme.grotesk(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
        }
    }

    private var formattedReminderTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: reminderTime)
    }

    private func refreshStatus() async {
        status = await PracticeReminderService.shared.authorizationStatus()
    }

    private func handlePrimary() async {
        Haptics.soft()
        if isDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }

        // Persist the chosen time even before permission resolves.
        PracticeReminderService.shared.reminderTime = reminderTime

        isRequesting = true
        let granted = await PracticeReminderService.shared.requestAuthorization()
        isRequesting = false
        await refreshStatus()

        if granted {
            PracticeReminderService.shared.isEnabled = true
            await PracticeReminderService.shared.refreshSchedule()
            Haptics.success()
            AnalyticsService.shared.track(.onboardingNotificationsResult, ["granted": "true"])
            onContinue()
        } else {
            Haptics.warning()
            PracticeReminderService.shared.isEnabled = false
            AnalyticsService.shared.track(.onboardingNotificationsResult, ["granted": "false"])
            withAnimation(.easeOut(duration: 0.2)) {
                showDeniedHint = true
            }
        }
    }
}
