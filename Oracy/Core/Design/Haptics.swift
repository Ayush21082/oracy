import UIKit

/// Centralized haptic feedback — prefers soft, purposeful taps over noise.
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        softImpact.prepare()
        notification.prepare()
        selection.prepare()
    }

    /// Soft repeating tick for typewriter character reveals — keep cadence identical everywhere.
    static func typewriterTick() {
        selection.selectionChanged()
    }

    static func light() {
        lightImpact.impactOccurred()
    }

    static func soft() {
        softImpact.impactOccurred()
    }

    static func medium() {
        mediumImpact.impactOccurred()
    }

    static func rigid() {
        rigidImpact.impactOccurred()
    }

    static func selectionChanged() {
        selection.selectionChanged()
    }

    static func success() {
        notification.notificationOccurred(.success)
    }

    static func warning() {
        notification.notificationOccurred(.warning)
    }

    static func error() {
        notification.notificationOccurred(.error)
    }
}
