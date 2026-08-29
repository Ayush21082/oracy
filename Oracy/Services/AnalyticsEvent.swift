import Foundation

/// Stable product analytics event names.
enum AnalyticsEvent: String, Sendable {
    // App lifecycle
    case appOpened = "app_opened"
    case appBackgrounded = "app_backgrounded"
    case routeResolved = "route_resolved"
    case screenViewed = "screen_viewed"
    case tabSelected = "tab_selected"

    // Auth
    case authAnonymous = "auth_anonymous"
    case authAppleSuccess = "auth_apple_success"
    case authAppleFailed = "auth_apple_failed"
    case authGoogleSuccess = "auth_google_success"
    case authGoogleFailed = "auth_google_failed"
    case authPhoneSuccess = "auth_phone_success"
    case authPhoneFailed = "auth_phone_failed"
    case authSignedOut = "auth_signed_out"
    case authAccountDeleted = "auth_account_deleted"
    case authLinkStarted = "auth_link_started"

    // Onboarding
    case onboardingStarted = "onboarding_started"
    case onboardingBeat = "onboarding_beat"
    case onboardingPhase = "onboarding_phase"
    case onboardingCompleted = "onboarding_completed"
    case onboardingMicResult = "onboarding_mic_result"
    case onboardingNotificationsResult = "onboarding_notifications_result"

    // Invite / referral
    case inviteGateShown = "invite_gate_shown"
    case inviteRedeemed = "invite_redeemed"
    case inviteRedeemFailed = "invite_redeem_failed"
    case referralShared = "referral_shared"
    case referralMilestoneClaimed = "referral_milestone_claimed"
    case referralMilestoneFailed = "referral_milestone_failed"

    // Practice / recording
    case challengeViewed = "challenge_viewed"
    case challengeShuffled = "challenge_shuffled"
    case recordingStarted = "recording_started"
    case recordingCompleted = "recording_completed"
    case recordingCancelled = "recording_cancelled"
    case sessionCreated = "session_created"
    case analysisStarted = "analysis_started"
    case analysisSucceeded = "analysis_succeeded"
    case analysisFailed = "analysis_failed"
    case feedbackViewed = "feedback_viewed"
    case completionViewed = "completion_viewed"
    case historyOpened = "history_opened"
    case historyDetailOpened = "history_detail_opened"
    case sessionDeleted = "session_deleted"

    // Paywall / subscription
    case paywallShown = "paywall_shown"
    case paywallDismissed = "paywall_dismissed"
    case purchaseStarted = "purchase_started"
    case purchaseSucceeded = "purchase_succeeded"
    case purchaseFailed = "purchase_failed"
    case purchaseCancelled = "purchase_cancelled"
    case restoreSucceeded = "restore_succeeded"
    case restoreFailed = "restore_failed"

    // Profile / settings
    case profileOpened = "profile_opened"
    case settingsOpened = "settings_opened"
    case accountOpened = "account_opened"
    case profileUpdated = "profile_updated"
    case avatarUpdated = "avatar_updated"
    case practiceReminderChanged = "practice_reminder_changed"
}
