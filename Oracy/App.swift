//
//  OracyApp.swift
//  OneWord
//

import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct OracyApp: App {
    // Creates the AppDelegate early; Firebase is configured in didFinishLaunching.
    @UIApplicationDelegateAdaptor(OracyAppDelegate.self) private var appDelegate

    init() {
        // Do NOT call FirebaseApp.configure() here. Auth is always-eager and will skip
        // phone-auth managers (tokenManager / notificationManager) if UIApplication isn't
        // ready yet — that yields FIRAuthError 17054 and setAPNSToken crashes.
        // Configure only in OracyAppDelegate.didFinishLaunchingWithOptions.
        Haptics.prepare()
        SubscriptionService.shared.configure()
        Task { @MainActor in
            await RemoteConfigService.shared.refresh()
        }
        #if canImport(GoogleSignIn)
        if !AppConfig.useMockBackend, AppConfig.isGoogleSignInConfigured {
            let serverID = AppConfig.googleServerClientID
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: AppConfig.googleClientID,
                serverClientID: serverID.isEmpty ? nil : serverID
            )
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    #endif
                    _ = FirebaseBootstrap.handleOpenURL(url)
                }
        }
    }
}
