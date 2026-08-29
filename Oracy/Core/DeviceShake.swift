import UIKit
import SwiftUI

extension UIDevice {
    /// Posted when the user shakes the device.
    static let deviceDidShakeNotification = Notification.Name("Oracy.deviceDidShake")
}

/// Invisible first-responder host so motion shake events are delivered reliably.
private final class ShakeViewController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
    }
}

private struct ShakeDetector: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeViewController {
        ShakeViewController()
    }

    func updateUIViewController(_ uiViewController: ShakeViewController, context: Context) {}
}

extension View {
    /// Calls `action` when the user shakes the phone.
    func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeDetector())
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                action()
            }
    }
}
