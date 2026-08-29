import SwiftUI
import FirebaseAuth

/// Liquid-glass 10-digit Indian mobile field (`+91` prefix).
struct PhoneNumberGlassField: View {
    @Binding var digits: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: (() -> Void)? = nil

    private let maxDigits = 10

    var body: some View {
        HStack(spacing: 12) {
            Text("+91")
                .font(Theme.grotesk(18, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)

            TextField("98765 43210", text: $digits)
                .font(Theme.grotesk(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .autocorrectionDisabled()
                .focused(isFocused)
                .onChange(of: digits) { _, newValue in
                    let cleaned = String(newValue.filter(\.isNumber).prefix(maxDigits))
                    if cleaned != newValue { digits = cleaned }
                }
                .onSubmit { onSubmit?() }
                .accessibilityLabel("Mobile number")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.72)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Color.white.opacity(0.18),
                            Theme.accent.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
    }

    var isComplete: Bool { digits.filter(\.isNumber).count == maxDigits }
}

/// Animated 5-box OTP entry with liquid-glass cells.
struct OTPGlassField: View {
    @Binding var code: String
    var isFocused: FocusState<Bool>.Binding
    var onComplete: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let length = 6

    var body: some View {
        ZStack {
            // Invisible field drives keyboard + paste.
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(isFocused)
                .opacity(0.02)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .onChange(of: code) { oldValue, newValue in
                    let cleaned = String(newValue.filter(\.isNumber).prefix(length))
                    if cleaned != newValue { code = cleaned }
                    if cleaned.count == length {
                        Haptics.success()
                        onComplete?(cleaned)
                    } else if cleaned.count > oldValue.filter(\.isNumber).count {
                        Haptics.selectionChanged()
                    }
                }

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { index in
                    otpCell(at: index)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .scaleEffect(appeared ? 1 : 0.92)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.2)
                                : .themeBounce.delay(Double(index) * 0.05),
                            value: appeared
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused.wrappedValue = true
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.2)) {
                isFocused.wrappedValue = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verification code")
        .accessibilityValue(code.isEmpty ? "Empty" : code)
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private func otpCell(at index: Int) -> some View {
        let chars = Array(code)
        let char = index < chars.count ? String(chars[index]) : ""
        let isActive = index == chars.count && chars.count < length
        let isFilled = !char.isEmpty

        return Text(char)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(isFilled || isActive ? 0.88 : 0.55)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isActive
                                ? [Theme.accent.opacity(0.75), Theme.accent.opacity(0.35)]
                                : [
                                    Color.white.opacity(0.65),
                                    Color.white.opacity(0.18),
                                    Theme.accent.opacity(isFilled ? 0.28 : 0.12)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isActive ? 1.6 : 1
                    )
            }
            .shadow(color: Color.black.opacity(isActive ? 0.08 : 0.04), radius: isActive ? 8 : 5, y: 2)
            .scaleEffect(isFilled && !reduceMotion ? 1.04 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .themeBounceSnappy, value: char)
    }
}

/// Shared phone → OTP flow used by onboarding and account linking.
struct PhoneOTPFlowView: View {
    var title: String = "What's your number?"
    var subtitle: String = "We'll text a 6-digit code to verify it's you."
    var onVerified: () -> Void
    var onCancel: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .phone
    @State private var phoneDigits = ""
    @State private var otpCode = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// Earliest time the user may tap Resend (nil = allowed).
    @State private var resendAvailableAt: Date?
    @FocusState private var phoneFocused: Bool
    @FocusState private var otpFocused: Bool

    private enum Step {
        case phone, otp
    }

    private let resendCooldownSeconds: TimeInterval = 59

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step == .phone ? title : "Enter the code")
                    .font(Theme.grotesk(17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(step == .phone ? subtitle : "Sent to +91 \(phoneDigits)")
                    .font(Theme.grotesk(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step == .phone {
                PhoneNumberGlassField(digits: $phoneDigits, isFocused: $phoneFocused) {
                    Task { await sendCode() }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                OTPGlassField(code: $otpCode, isFocused: $otpFocused) { code in
                    Task { await verify(code) }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step == .phone {
                OnboardingPrimaryButton(
                    title: "Send code",
                    isEnabled: phoneDigits.count == 10 && !isWorking,
                    isLoading: isWorking
                ) {
                    Task { await sendCode() }
                }
            } else {
                OnboardingPrimaryButton(
                    title: "Verify",
                    isEnabled: otpCode.count == 6 && !isWorking,
                    isLoading: isWorking
                ) {
                    Task { await verify(otpCode) }
                }

                HStack(spacing: 16) {
                    Button {
                        Haptics.light()
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce) {
                            step = .phone
                            otpCode = ""
                            errorMessage = nil
                        }
                    } label: {
                        Text("Change number")
                            .font(Theme.grotesk(14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Spacer()

                    resendControl
                }
                .padding(.top, 2)
            }

            if let onCancel {
                Button {
                    Haptics.light()
                    onCancel()
                } label: {
                    Text("Back")
                        .font(Theme.grotesk(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce, value: step)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                phoneFocused = true
            }
        }
    }

    @ViewBuilder
    private var resendControl: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secondsLeft = resendSecondsRemaining(at: context.date)
            if secondsLeft > 0 {
                Text("Resend in \(secondsLeft)s")
                    .font(Theme.grotesk(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .accessibilityLabel("Resend available in \(secondsLeft) seconds")
            } else {
                Button {
                    Task { await resend() }
                } label: {
                    Text("Resend code")
                        .font(Theme.grotesk(14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
    }

    private func resendSecondsRemaining(at date: Date) -> Int {
        guard let until = resendAvailableAt else { return 0 }
        return max(0, Int(ceil(until.timeIntervalSince(date))))
    }

    private func beginResendCooldown() {
        resendAvailableAt = Date().addingTimeInterval(resendCooldownSeconds)
    }

    private func sendCode() async {
        guard phoneDigits.count == 10, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await AuthService.shared.sendPhoneOTP(digits: phoneDigits)
            Haptics.success()
            beginResendCooldown()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce) {
                step = .otp
                otpCode = ""
            }
        } catch {
            Haptics.warning()
            errorMessage = Self.friendlySendError(error)
        }
    }

    private static func friendlySendError(_ error: Error) -> String {
        let ns = error as NSError
        let detail = "[\(ns.domain) \(ns.code)] \(ns.localizedDescription)"
        let blob = errorDebugBlob(ns).lowercased()

        if blob.contains("billing_not_enabled") {
            return "Firebase Phone SMS needs Blaze billing enabled on project oracy-efdfc (Console → Usage and billing). \(detail)"
        }
        if ns.code == AuthErrorCode.webContextCancelled.rawValue
            || blob.contains("cancelled by the user") {
            return "Verification was cancelled. Try again and complete the browser check. \(detail)"
        }
        if blob.contains("firebase") && blob.contains("configured") {
            return "Firebase isn’t configured. Check GoogleService-Info.plist. \(detail)"
        }
        if blob.contains("apns") || blob.contains("push") || blob.contains("token")
            || ns.code == AuthErrorCode.missingAppToken.rawValue
            || ns.code == AuthErrorCode.appNotVerified.rawValue {
            return "App verification failed (APNs/reCAPTCHA). \(detail)"
        }
        if blob.contains("quota") || blob.contains("blocked") || blob.contains("too many")
            || ns.code == AuthErrorCode.tooManyRequests.rawValue {
            return "Too many SMS attempts. \(detail)"
        }
        if blob.contains("region") || blob.contains("country") {
            return "SMS region blocked in Firebase. Allow India in SMS region policy. \(detail)"
        }
        if let localized = (error as? LocalizedError)?.errorDescription {
            return "\(localized) \(detail)"
        }
        return "Couldn’t send the code. \(detail)"
    }

    /// Walks nested Auth / HTTP errors so server messages like BILLING_NOT_ENABLED are visible.
    private static func errorDebugBlob(_ error: NSError) -> String {
        var parts: [String] = [error.localizedDescription, String(describing: error.userInfo)]
        var current: NSError? = error
        var depth = 0
        while let err = current, depth < 5 {
            if let response = err.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] {
                parts.append(String(describing: response))
            }
            current = err.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return parts.joined(separator: " ")
    }

    private func verify(_ code: String) async {
        guard code.count == 6, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            // Profile-save retry after Firebase already accepted OTP (e.g. missing column).
            if try await AuthService.shared.retryPendingPhoneProfileSaveIfNeeded() {
                Haptics.success()
                onVerified()
                return
            }
            try await AuthService.shared.verifyPhoneOTP(code: code)
            Haptics.success()
            onVerified()
        } catch {
            Haptics.warning()
            otpCode = ""
            errorMessage = Self.friendlyVerifyError(error)
            otpFocused = true
        }
    }

    private static func friendlyVerifyError(_ error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError {
            case .phoneAlreadyInUse,
                 .phoneOwnedByOAuthAccount,
                 .phoneAlreadyAssociatedWithAnotherAccount,
                 .phoneLoginSwitchFailed:
                return authError.errorDescription
                    ?? "This number is already associated with another account."
            default:
                break
            }
        }
        let ns = error as NSError
        let text = ns.localizedDescription
        if text.localizedCaseInsensitiveContains("phone_login_switch_required")
            || text.localizedCaseInsensitiveContains("phone_owned_by_oauth")
            || text.localizedCaseInsensitiveContains("phone_already_associated")
            || text.localizedCaseInsensitiveContains("profiles_phone_uidx")
            || text.localizedCaseInsensitiveContains("duplicate key")
            || text.localizedCaseInsensitiveContains("phone_already_in_use") {
            return "This number is already associated with another account. Sign in with that account to continue."
        }
        if text.localizedCaseInsensitiveContains("phone") && text.localizedCaseInsensitiveContains("schema") {
            return "Phone isn’t set up on the server yet. Apply migration 014_profile_phone, then request a new code."
        }
        if text.localizedCaseInsensitiveContains("Request a code first") {
            return "That code was already used. Request a new code and try again."
        }
        return "That code didn’t work. Try again. [\(ns.domain) \(ns.code)] \(text)"
    }

    private func resend() async {
        guard !isWorking, resendSecondsRemaining(at: Date()) == 0 else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await AuthService.shared.resendPhoneOTP(digits: phoneDigits)
            Haptics.soft()
            beginResendCooldown()
            otpCode = ""
            otpFocused = true
        } catch {
            Haptics.warning()
            errorMessage = "Couldn’t resend. Try again in a moment."
        }
    }
}
