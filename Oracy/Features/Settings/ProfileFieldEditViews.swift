import SwiftUI

// MARK: - Shared chrome

private struct SettingsEditPageChrome<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(Theme.fraunces(32, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(Theme.grotesk(16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .themeBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsEditTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var monospaced = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(
                monospaced
                    ? .system(size: 22, weight: .semibold, design: .monospaced)
                    : Theme.grotesk(20, weight: .medium)
            )
            .foregroundStyle(Theme.textPrimary)
            .keyboardType(keyboard)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .focused($focused)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardBackground.opacity(0.82))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.textSecondary.opacity(0.18), lineWidth: 1)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focused = true
                }
            }
    }
}

private struct SettingsEditSaveButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .tint(Color(red: 0.98, green: 0.97, blue: 0.96))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minTapTarget)
            } else {
                Text(title)
                    .font(Theme.grotesk(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minTapTarget)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Name

struct EditDisplayNameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @State private var draft = ""
    @State private var isSaving = false

    var body: some View {
        SettingsEditPageChrome(
            title: "Your name",
            subtitle: "This is how you show up across Oracy."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsEditTextField(
                    placeholder: "Name",
                    text: $draft,
                    textContentType: .name,
                    autocapitalization: .words,
                    onSubmit: { Task { await save() } }
                )

                SettingsEditSaveButton(
                    title: "Save",
                    isEnabled: canSave,
                    isLoading: isSaving
                ) {
                    Task { await save() }
                }
            }
        }
        .navigationTitle("Name")
        .onAppear {
            if draft.isEmpty {
                draft = auth.profile?.displayName ?? ""
            }
        }
    }

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AuthService.isRealDisplayName(trimmed) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await auth.updateProfile(ProfileUpdate(displayName: trimmed))
            LastSignedInIdentity.updateDisplayNameIfNeeded(trimmed)
            Haptics.success()
            dismiss()
        } catch {
            AppErrorCenter.shared.present(
                title: "Couldn’t save name",
                message: "Check your connection and try again."
            )
        }
    }
}

// MARK: - Occupation

struct EditOccupationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @State private var draft = ""
    @State private var isSaving = false

    var body: some View {
        SettingsEditPageChrome(
            title: "Occupation",
            subtitle: "A short label for what you do — student, designer, founder…"
        ) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsEditTextField(
                    placeholder: "Occupation",
                    text: $draft,
                    autocapitalization: .words,
                    onSubmit: { Task { await save() } }
                )

                SettingsEditSaveButton(
                    title: "Save",
                    isLoading: isSaving
                ) {
                    Task { await save() }
                }
            }
        }
        .navigationTitle("Occupation")
        .onAppear {
            if draft.isEmpty {
                draft = Self.currentOccupation(from: auth.profile)
            }
        }
    }

    static func currentOccupation(from profile: Profile?) -> String {
        let tags = profile?.personality ?? []
        let names = tags.compactMap { OnboardingPersonalityTag(rawValue: $0)?.displayName }
        if !names.isEmpty {
            return names.sorted().joined(separator: ", ")
        }
        return UserDefaults.standard.string(forKey: "profile.occupation") ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let matched = OnboardingPersonalityTag.allCases.filter { tag in
            tokens.contains { $0.caseInsensitiveCompare(tag.displayName) == .orderedSame }
                || tokens.contains { $0.caseInsensitiveCompare(tag.rawValue) == .orderedSame }
        }

        do {
            if !matched.isEmpty {
                try await auth.updateProfile(
                    ProfileUpdate(personality: matched.map(\.rawValue).sorted())
                )
                UserDefaults.standard.removeObject(forKey: "profile.occupation")
            } else {
                UserDefaults.standard.set(trimmed, forKey: "profile.occupation")
                if trimmed.isEmpty {
                    try await auth.updateProfile(ProfileUpdate(personality: []))
                }
            }
            Haptics.success()
            dismiss()
        } catch {
            AppErrorCenter.shared.present(
                title: "Couldn’t save occupation",
                message: "Check your connection and try again."
            )
        }
    }
}

// MARK: - Age

struct EditAgeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @State private var age = 25
    @State private var isSaving = false
    @State private var didLoad = false

    var body: some View {
        SettingsEditPageChrome(
            title: "Your age",
            subtitle: "Helps us keep prompts feeling right for you."
        ) {
            VStack(alignment: .leading, spacing: 28) {
                AgeSelector(age: $age, range: 13...120)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                SettingsEditSaveButton(
                    title: "Save",
                    isLoading: isSaving
                ) {
                    Task { await save() }
                }
            }
        }
        .navigationTitle("Age")
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let existing = auth.profile?.age, (13...120).contains(existing) {
                age = existing
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await auth.updateProfile(ProfileUpdate(age: age))
            Haptics.success()
            dismiss()
        } catch {
            AppErrorCenter.shared.present(
                title: "Couldn’t save age",
                message: "Check your connection and try again."
            )
        }
    }
}

// MARK: - Referral code

struct EnterReferralCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWorking = false
    @State private var feedback: String?
    @State private var didSucceed = false

    private var subtitle: String {
        RemoteConfigService.shared.isInviteOnlyEnabled
            ? "Enter a friend’s Guest Pass. You both get +2 weekly speaks."
            : "Enter a friend’s code. You both get +2 weekly speaks."
    }

    var body: some View {
        SettingsEditPageChrome(
            title: "Referral code",
            subtitle: subtitle
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Code")
                        .font(Theme.grotesk(13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Spacer()

                    ReferralCodePasteButton {
                        pasteCode()
                    }
                }

                SettingsEditTextField(
                    placeholder: "ABCDEFGH",
                    text: $code,
                    autocapitalization: .characters,
                    monospaced: true,
                    submitLabel: .go,
                    onSubmit: { Task { await submit() } }
                )
                .onChange(of: code) { _, value in
                    let parsed = InviteService.parseReferralCode(value)
                    let cleaned: String
                    if (6...10).contains(parsed.count) {
                        cleaned = parsed
                    } else {
                        cleaned = String(
                            value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(10)
                        )
                    }
                    if cleaned != value {
                        code = cleaned
                    }
                    feedback = nil
                    didSucceed = false
                }

                if let feedback {
                    Text(feedback)
                        .font(Theme.grotesk(14, weight: .medium))
                        .foregroundStyle(didSucceed ? Theme.success : Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsEditSaveButton(
                    title: didSucceed ? "Done" : "Apply code",
                    isEnabled: didSucceed || !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isLoading: isWorking
                ) {
                    if didSucceed {
                        dismiss()
                    } else {
                        Task { await submit() }
                    }
                }
            }
        }
        .navigationTitle("Referral")
    }

    private func pasteCode() {
        guard let pasted = ReferralCodePaste.cleanedClipboardCode() else {
            feedback = "No invite code found on the clipboard."
            didSucceed = false
            Haptics.warning()
            return
        }
        code = pasted
        feedback = nil
        didSucceed = false
        Haptics.success()
    }

    private func submit() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }

        let result = await InviteService.shared.redeem(trimmed)
        feedback = result.userMessage

        switch result {
        case .success, .alreadyRedeemed:
            didSucceed = true
            Haptics.success()
        default:
            didSucceed = false
            Haptics.warning()
        }
    }
}
