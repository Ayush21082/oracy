import AuthenticationServices
import PhotosUI
import SwiftUI

struct MyAccountView: View {
    @State private var auth = AuthService.shared
    @State private var remoteConfig = RemoteConfigService.shared
    @State private var showSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var showSignInSheet = false
    @State private var showPhoneLinkSheet = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhoto: UIImage?
    @State private var isSaving = false
    @State private var linkingProvider: LinkedProvider?
    @State private var applePresenter = AppleSignInPresenter()

    private enum LinkedProvider {
        case apple, google

        var title: String {
            switch self {
            case .apple: return "Apple"
            case .google: return "Google"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                photoHeader
                profileFields
                if pendingPhoto != nil {
                    savePhotoButton
                }
                if remoteConfig.isPhoneAuthEnabled {
                    phoneSection
                }
                linkedAccountsSection
                authActionSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .themeBackground()
        .navigationTitle("My Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll continue as a guest on this device. Link again anytime to save progress across devices.")
        }
        .sheet(isPresented: $showSignInSheet) {
            AuthSheet(showsSkip: false)
                .onDisappear {
                    Task { await auth.refreshLinkedIdentities() }
                }
        }
        .sheet(isPresented: $showPhoneLinkSheet) {
            PhoneLinkSheet {
                showPhoneLinkSheet = false
                Task { await auth.refreshLinkedIdentities() }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPickedPhoto(item) }
        }
        .task {
            await remoteConfig.refresh()
            await auth.refreshLinkedIdentities()
            if auth.profile == nil {
                await auth.fetchProfile()
            }
        }
    }

    private var photoHeader: some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(
                        size: 112,
                        isCelebrating: false,
                        isSubscriber: SubscriptionService.shared.isProActive,
                        uiImage: displayedPhoto,
                        imageURL: pendingPhoto == nil ? remoteAvatarURL : nil
                    )

                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.96))
                        .frame(width: 32, height: 32)
                        .background(Theme.accent, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                        }
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile photo")

            Text(displayName)
                .font(Theme.fraunces(24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Tap photo to change")
                .font(Theme.grotesk(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var profileFields: some View {
        VStack(spacing: 0) {
            NavigationLink {
                EditDisplayNameView()
            } label: {
                fieldRow(title: "Name", value: displayName)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.35)

            NavigationLink {
                EditOccupationView()
            } label: {
                fieldRow(
                    title: "Occupation",
                    value: occupation.isEmpty ? "Add occupation" : occupation,
                    valueIsPlaceholder: occupation.isEmpty
                )
            }
            .buttonStyle(.plain)

            Divider().opacity(0.35)

            NavigationLink {
                EditAgeView()
            } label: {
                fieldRow(
                    title: "Age",
                    value: ageLabel.isEmpty ? "Add age" : ageLabel,
                    valueIsPlaceholder: ageLabel.isEmpty
                )
            }
            .buttonStyle(.plain)
        }
        .background(Theme.cardBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var savePhotoButton: some View {
        Button {
            Task { await savePhoto() }
        } label: {
            if isSaving {
                ProgressView()
                    .tint(Color(red: 0.98, green: 0.97, blue: 0.96))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minTapTarget)
            } else {
                Text("Save photo")
                    .font(Theme.grotesk(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minTapTarget)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isSaving)
    }

    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Phone number")
                .font(Theme.grotesk(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 4)

            if auth.isPhoneLinked, let display = AuthService.displayPhone(auth.linkedPhone) {
                HStack(spacing: 10) {
                    phoneBadge
                    Text(display)
                        .font(Theme.grotesk(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.success)
                        .accessibilityLabel("Verified")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.cardBackground.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.success.opacity(0.28), lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Phone number \(display)")
            } else {
                Button {
                    Haptics.soft()
                    showPhoneLinkSheet = true
                } label: {
                    HStack(spacing: 10) {
                        phoneBadge
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.hasLinkedAccount ? "Add phone number" : "Link phone number")
                                .font(Theme.grotesk(16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(
                                auth.hasLinkedAccount
                                    ? "Verify a mobile number for this account"
                                    : "Guests can link a number to keep progress"
                            )
                            .font(Theme.grotesk(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.cardBackground.opacity(0.4))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                Theme.textSecondary.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    auth.hasLinkedAccount ? "Add phone number" : "Link phone number"
                )
            }
        }
    }

    private var phoneBadge: some View {
        ZStack {
            Circle()
                .fill(Theme.textPrimary.opacity(0.06))
                .frame(width: 34, height: 34)
            Image(systemName: "iphone")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityHidden(true)
    }

    private var linkedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Linked accounts")
                .font(Theme.grotesk(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                linkedProviderRow(provider: .apple, linked: auth.isAppleLinked)
                linkedProviderRow(provider: .google, linked: auth.isGoogleLinked)
            }
        }
    }

    @ViewBuilder
    private func linkedProviderRow(provider: LinkedProvider, linked: Bool) -> some View {
        let isBusy = linkingProvider == provider
        let row = HStack(spacing: 10) {
            if linked {
                providerBadge(provider)
                Text(provider.title)
                    .font(Theme.grotesk(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .accessibilityLabel("Linked")
            } else {
                providerBadge(provider)

                Text("Link with \(provider.title)")
                    .font(Theme.grotesk(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView()
                        .tint(Theme.accent)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(linked ? 0.72 : 0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    linked
                        ? Theme.success.opacity(0.28)
                        : Theme.textSecondary.opacity(0.45),
                    style: StrokeStyle(
                        lineWidth: linked ? 1 : 1.2,
                        dash: linked ? [] : [5, 4]
                    )
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            linked
                ? "\(provider.title) linked"
                : "Link with \(provider.title)"
        )

        if linked {
            row
        } else {
            Button {
                Task { await link(provider) }
            } label: {
                row
            }
            .buttonStyle(.plain)
            .disabled(linkingProvider != nil)
        }
    }

    @ViewBuilder
    private func providerBadge(_ provider: LinkedProvider) -> some View {
        ZStack {
            Circle()
                .fill(Theme.textPrimary.opacity(0.06))
                .frame(width: 34, height: 34)

            switch provider {
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            case .google:
                GoogleMark()
                    .frame(width: 16, height: 16)
            }
        }
        .accessibilityHidden(true)
    }

    private func link(_ provider: LinkedProvider) async {
        guard linkingProvider == nil else { return }
        linkingProvider = provider
        Haptics.soft()
        defer { linkingProvider = nil }

        do {
            switch provider {
            case .apple:
                let (credential, nonce) = try await applePresenter.signIn()
                let idToken = try AppleSignInSupport.idToken(from: credential)
                try await auth.signInWithApple(idToken: idToken, nonce: nonce)
                await auth.applyAppleDisplayNameIfNeeded(credential.fullName)
                let name = AuthService.preferredDisplayName(
                    auth.profile?.displayName,
                    AppleSignInSupport.displayName(from: credential.fullName)
                )
                LastSignedInIdentity.rememberApple(userID: credential.user, displayName: name)
            case .google:
                try await auth.signInWithGoogle()
                LastSignedInIdentity.rememberGoogle(
                    displayName: AuthService.preferredDisplayName(auth.profile?.displayName)
                )
            }
            await auth.refreshLinkedIdentities()
            Haptics.success()
        } catch {
            if AppleSignInSupport.isUserCancel(error) { return }
            AppErrorCenter.shared.present(
                title: "Couldn’t link \(provider.title)",
                message: "Check your connection and try again."
            )
        }
    }

    private var authActionSection: some View {
        Group {
            if auth.hasLinkedAccount {
                Button {
                    showSignOutConfirm = true
                } label: {
                    if isSigningOut {
                        ProgressView().tint(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Sign out")
                            .font(Theme.grotesk(16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.plain)
                .background(Theme.cardBackground.opacity(0.72))
                .clipShape(Capsule())
                .disabled(isSigningOut)
            } else {
                Button {
                    Haptics.soft()
                    showSignInSheet = true
                } label: {
                    Text("Sign in")
                        .font(Theme.grotesk(16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.96))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fieldRow(
        title: String,
        value: String,
        valueIsPlaceholder: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.grotesk(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.grotesk(16, weight: .medium))
                .foregroundStyle(valueIsPlaceholder ? Theme.textSecondary.opacity(0.7) : Theme.textPrimary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Profile display

    private var displayName: String {
        let name = auth.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Speaker" : name
    }

    private var occupation: String {
        EditOccupationView.currentOccupation(from: auth.profile)
    }

    private var ageLabel: String {
        auth.profile?.age.map(String.init) ?? ""
    }

    private var remoteAvatarURL: URL? {
        guard let raw = auth.profile?.avatarUrl, let url = URL(string: raw) else { return nil }
        return url
    }

    private var displayedPhoto: UIImage? {
        if let pendingPhoto { return pendingPhoto }
        if let userId = auth.userId {
            return ProfileLocalCache.loadAvatarImage(userId: userId)
        }
        return nil
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                pendingPhoto = image
                Haptics.soft()
            }
        } catch {
            AppErrorCenter.shared.presentFriendly()
        }
    }

    private func savePhoto() async {
        guard let pendingPhoto else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await auth.uploadAvatar(pendingPhoto)
            self.pendingPhoto = nil
            photoItem = nil
            Haptics.success()
        } catch {
            AppErrorCenter.shared.present(
                title: "Couldn’t save photo",
                message: "Check your connection and try again.",
                retry: { Task { await savePhoto() } }
            )
        }
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await auth.signOut()
            if !auth.isAuthenticated {
                try await auth.signInAnonymously()
            }
            await auth.refreshLinkedIdentities()
            Haptics.soft()
        } catch {
            AppErrorCenter.shared.presentFriendly()
        }
    }
}

// MARK: - Phone link sheet

struct PhoneLinkSheet: View {
    var onLinked: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PhoneOTPFlowView(
                    title: "Link your phone",
                    subtitle: "We'll text a 6-digit code so you can keep progress across devices.",
                    onVerified: {
                        onLinked()
                        dismiss()
                    },
                    onCancel: nil
                )
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .themeBackground()
            .navigationTitle("Phone number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .appErrorOverlay()
        .presentationDetents([.medium, .large])
    }
}

// MARK: - About

struct AboutOracyView: View {
    private let bodyParagraphs = [
        "Most of us practice thinking in our heads. Almost nobody practices speaking.",
        "Oracy is a quiet daily habit for your voice: one minute, one prompt, honest feedback. No audience. No pressure. Just you, speaking out loud, and getting better at it.",
        "Open the app. Take a breath. Speak for sixty seconds. Then see what landed: your clarity, your pace, your fillers, what to try next time. Small notes. Real progress. A streak that rewards showing up, not perfection.",
        "Use it before a meeting. Before an interview. Before a hard conversation. Or just because you want to feel more like yourself when you speak.",
        "A week in, you’ll notice it: fewer “ums,” cleaner thoughts, a little more confidence in the room. A month in, speaking stops feeling like something you survive — and starts feeling like something you’re good at."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AppLogoMark(size: 96, showsWordmark: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(Theme.grotesk(16))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("One minute a day. That’s all it asks.")
                        Text("The rest of your life gets the benefit.")
                    }
                    .font(Theme.fraunces(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    aboutRow("Version", "1.0.0")
                    aboutRow("Made for", "iPhone")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(24)
        }
        .themeBackground()
        .navigationTitle("About Oracy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.grotesk(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.grotesk(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
