import Foundation
import UserNotifications
import UIKit

/// Local practice reminders + same-day streak-keep nudges.
@MainActor
final class PracticeReminderService {
    static let shared = PracticeReminderService()

    static let enabledKey = "settings.practiceReminders"
    static let hourKey = "settings.practiceReminderHour"
    static let minuteKey = "settings.practiceReminderMinute"

    private let center = UNUserNotificationCenter.current()
    private let dailyPrefix = "oracy.practice.daily."
    private let streakId = "oracy.practice.streak"
    private let streakNudgeDayKey = "practice.streakNudgeDay"
    private let dailyHorizonDays = 7

    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get {
            if defaults.object(forKey: Self.enabledKey) == nil { return true }
            return defaults.bool(forKey: Self.enabledKey)
        }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            Task { await refreshSchedule() }
        }
    }

    /// Hour component (0–23). Default 9 AM.
    var reminderHour: Int {
        get {
            if defaults.object(forKey: Self.hourKey) == nil { return 9 }
            return defaults.integer(forKey: Self.hourKey)
        }
        set {
            defaults.set(min(23, max(0, newValue)), forKey: Self.hourKey)
            Task { await rescheduleAfterTimeChange() }
        }
    }

    /// Minute component (0–59). Default :00.
    var reminderMinute: Int {
        get {
            if defaults.object(forKey: Self.minuteKey) == nil { return 0 }
            return defaults.integer(forKey: Self.minuteKey)
        }
        set {
            defaults.set(min(59, max(0, newValue)), forKey: Self.minuteKey)
            Task { await rescheduleAfterTimeChange() }
        }
    }

    /// Date used by Settings `DatePicker` (.hourAndMinute).
    var reminderTime: Date {
        get {
            Calendar.current.date(
                bySettingHour: reminderHour,
                minute: reminderMinute,
                second: 0,
                of: Date()
            ) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            defaults.set(min(23, max(0, comps.hour ?? 9)), forKey: Self.hourKey)
            defaults.set(min(59, max(0, comps.minute ?? 0)), forKey: Self.minuteKey)
            Task { await rescheduleAfterTimeChange() }
        }
    }

    var formattedReminderTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: reminderTime)
    }

    private init() {}

    /// If a streak nudge is still waiting, allow it to recompute after the daily time changes.
    private func rescheduleAfterTimeChange() async {
        let pending = await center.pendingNotificationRequests()
        if pending.contains(where: { $0.identifier == streakId }) {
            defaults.removeObject(forKey: streakNudgeDayKey)
            center.removePendingNotificationRequests(withIdentifiers: [streakId])
        }
        await refreshSchedule()
    }

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await refreshSchedule()
            } else {
                await cancelAll()
            }
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Recompute pending local notifications from current settings + streak state.
    func refreshSchedule(
        streakCount: Int? = nil,
        lastPracticeDate: String? = nil
    ) async {
        let status = await authorizationStatus()
        guard isEnabled, status == .authorized || status == .provisional else {
            await cancelAll()
            return
        }

        let streak = streakCount ?? AuthService.shared.profile?.streakCount ?? 0
        let last = lastPracticeDate ?? AuthService.shared.profile?.lastPracticeDate

        await scheduleUpcomingDailyReminders()
        await scheduleStreakNudgeIfNeeded(streakCount: streak, lastPracticeDate: last)
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let dailyIds = pending.map(\.identifier).filter { $0.hasPrefix(dailyPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: dailyIds + [streakId])
        center.removeDeliveredNotifications(withIdentifiers: dailyIds + [streakId])
    }

    /// Call after a successful practice session so today's streak nudge is cleared.
    func didCompletePracticeToday() async {
        defaults.set(Self.todayString(), forKey: streakNudgeDayKey)
        center.removePendingNotificationRequests(withIdentifiers: [streakId])
        center.removeDeliveredNotifications(withIdentifiers: [streakId])
        await refreshSchedule()
    }

    // MARK: - Private — daily

    /// One-shot reminders for the next N days (fresh copy each day).
    /// Repeating triggers freeze content; rolling one-shots stay lively.
    private func scheduleUpcomingDailyReminders() async {
        let pending = await center.pendingNotificationRequests()
        let oldDaily = pending.map(\.identifier).filter { $0.hasPrefix(dailyPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldDaily)

        let calendar = Calendar.current
        let now = Date()
        guard let startDay = calendar.dateInterval(of: .day, for: now)?.start else { return }

        var scheduled = 0
        for offset in 0..<dailyHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            guard let fire = calendar.date(
                bySettingHour: reminderHour,
                minute: reminderMinute,
                second: 0,
                of: day
            ) else { continue }

            // Today's slot already passed → skip to keep the horizon filled with future days.
            if fire <= now { continue }

            let copy = NotificationCopy.daily(for: fire, dayOffset: offset)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            content.threadIdentifier = "oracy.practice"
            content.categoryIdentifier = "PRACTICE_REMINDER"

            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            comps.second = 0

            let id = "\(dailyPrefix)\(Self.dayKey(fire))"
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                #if DEBUG
                print("[PracticeReminder] daily schedule failed: \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[PracticeReminder] scheduled \(scheduled) daily reminder(s) at \(reminderHour):\(String(format: "%02d", reminderMinute))")
        #endif
    }

    // MARK: - Private — streak

    /// Soft “keep the streak alive” nudge later the same day if they already have a streak
    /// and haven’t practiced yet.
    private func scheduleStreakNudgeIfNeeded(streakCount: Int, lastPracticeDate: String?) async {
        if streakCount < 1 {
            center.removePendingNotificationRequests(withIdentifiers: [streakId])
            return
        }

        if Self.practicedToday(lastPracticeDate) {
            defaults.set(Self.todayString(), forKey: streakNudgeDayKey)
            center.removePendingNotificationRequests(withIdentifiers: [streakId])
            center.removeDeliveredNotifications(withIdentifiers: [streakId])
            return
        }

        let pending = await center.pendingNotificationRequests()
        let hasPendingStreak = pending.contains { $0.identifier == streakId }
        if defaults.string(forKey: streakNudgeDayKey) == Self.todayString() {
            // Already scheduled or delivered a streak nudge today — don't touch it.
            if hasPendingStreak { return }
            return
        }

        guard let fireDate = streakNudgeFireDate() else { return }

        center.removePendingNotificationRequests(withIdentifiers: [streakId])

        let copy = NotificationCopy.streak(streakCount: streakCount, fireDate: fireDate)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.threadIdentifier = "oracy.practice"
        content.categoryIdentifier = "STREAK_NUDGE"

        let calendar = Calendar.current
        let interval = fireDate.timeIntervalSinceNow
        let request: UNNotificationRequest
        if interval < 90 {
            // Near-term — time-interval is more reliable than a calendar slot seconds away.
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(5, interval),
                repeats: false
            )
            request = UNNotificationRequest(identifier: streakId, content: content, trigger: trigger)
        } else {
            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            request = UNNotificationRequest(identifier: streakId, content: content, trigger: trigger)
        }

        do {
            try await center.add(request)
            defaults.set(Self.todayString(), forKey: streakNudgeDayKey)
            #if DEBUG
            print("[PracticeReminder] streak nudge at \(fireDate) (streak \(streakCount))")
            #endif
        } catch {
            #if DEBUG
            print("[PracticeReminder] streak schedule failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Prefer ~7:30 PM local, or 3 hours after the daily reminder — whichever is later.
    /// If that window already passed, nudge once soon (before 10:30 PM).
    private func streakNudgeFireDate() -> Date? {
        let calendar = Calendar.current
        let now = Date()

        let evening = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: now)
        let afterDaily = calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: now
        ).flatMap { calendar.date(byAdding: .hour, value: 3, to: $0) }

        let preferred = [evening, afterDaily].compactMap { $0 }.max()
        if let preferred, preferred > now.addingTimeInterval(60) {
            return preferred
        }

        // Missed the evening window — one catch-up ping, not too late.
        guard let latest = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: now),
              now < latest else {
            return nil
        }

        let soon = now.addingTimeInterval(20 * 60) // ~20 minutes
        return min(soon, latest)
    }

    // MARK: - Helpers

    private static func practicedToday(_ lastPracticeDate: String?) -> Bool {
        guard let day = normalizedDay(lastPracticeDate) else { return false }
        return day == todayString()
    }

    private static func todayString() -> String {
        dayKey(Date())
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Accepts `yyyy-MM-dd` or ISO timestamps from the API.
    private static func normalizedDay(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.count >= 10 {
            let prefix = String(raw.prefix(10))
            if prefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            return dayKey(date)
        }
        return nil
    }
}

// MARK: - Copy

enum NotificationCopy {
    struct Payload {
        let title: String
        let body: String
    }

    static func daily(for date: Date, dayOffset: Int) -> Payload {
        let hour = Calendar.current.component(.hour, from: date)
        let pool: [Payload]
        if hour < 11 {
            pool = morning
        } else if hour < 17 {
            pool = afternoon
        } else {
            pool = evening
        }
        return pool[abs(dayOffset) % pool.count]
    }

    static func streak(streakCount: Int, fireDate: Date) -> Payload {
        if let milestone = milestone(for: streakCount) {
            return milestone
        }
        let hour = Calendar.current.component(.hour, from: fireDate)
        let pool = hour >= 20 ? streakLate : streakStandard
        let pick = pool[streakCount % pool.count]
        return Payload(
            title: streakTitle(streakCount),
            body: pick
        )
    }

    private static func streakTitle(_ streak: Int) -> String {
        switch streak {
        case 1: return "Day 1 is still open"
        case 2: return "Don’t drop day 2"
        case 3...6: return "Keep your \(streak)-day streak"
        case 7...13: return "A full week is in reach"
        case 14...29: return "Protect the \(streak)-day run"
        default: return "Your \(streak)-day streak needs you"
        }
    }

    private static func milestone(for streak: Int) -> Payload? {
        switch streak {
        case 3:
            return Payload(
                title: "3 days strong",
                body: "One more minute locks in the habit. Don’t break it tonight."
            )
        case 7:
            return Payload(
                title: "One week on the line",
                body: "Seven days of speaking — one short take keeps the chain whole."
            )
        case 14:
            return Payload(
                title: "Two weeks. Still yours.",
                body: "You’ve built something real. Sixty seconds protects it."
            )
        case 21:
            return Payload(
                title: "21 days — habit territory",
                body: "This is where most people fade. You’re not most people."
            )
        case 30:
            return Payload(
                title: "30-day streak at stake",
                body: "A whole month of voice. One prompt keeps it unbroken."
            )
        case 50:
            return Payload(
                title: "50 days. Legendary.",
                body: "Don’t let a busy evening erase a streak like that."
            )
        case 100:
            return Payload(
                title: "100 days — protect it",
                body: "A century of practice. One minute is all it asks of you."
            )
        default:
            return nil
        }
    }

    // MARK: Daily pools

    private static let morning: [Payload] = [
        Payload(title: "Morning voice check", body: "Sixty seconds before the day gets loud. Tap in."),
        Payload(title: "Start with a sentence", body: "One prompt. One minute. Clear head, warmer voice."),
        Payload(title: "Speak while it’s quiet", body: "The best practice often happens before the inbox wakes up."),
        Payload(title: "Oracy is ready", body: "A short take now beats a perfect one you skip."),
        Payload(title: "Warm up the words", body: "Show up for yourself — even a quick session counts."),
        Payload(title: "One minute of courage", body: "Say the thing out loud. We’ll meet you on the other side."),
        Payload(title: "Make today count early", body: "Lock in practice before the calendar fills up."),
    ]

    private static let afternoon: [Payload] = [
        Payload(title: "Midday reset", body: "Step out of the scroll. Speak for one focused minute."),
        Payload(title: "Your prompt is waiting", body: "A short practice keeps the muscle warm."),
        Payload(title: "Break the silence", body: "You’ve been thinking all day — give it a voice."),
        Payload(title: "Sixty seconds, no slides", body: "Just you, a prompt, and a cleaner thought."),
        Payload(title: "Still time to speak", body: "A quick session now means you won’t owe yourself later."),
        Payload(title: "Find the words", body: "Clarity loves a deadline. Yours is one minute."),
        Payload(title: "Practice beats polish", body: "Jump in messy. Feedback will meet you there."),
    ]

    private static let evening: [Payload] = [
        Payload(title: "Close the day with your voice", body: "One minute before you wind down. You’ve got this."),
        Payload(title: "Evening check-in", body: "Leave today with one clear thought spoken out loud."),
        Payload(title: "Don’t sleep on practice", body: "A short take tonight keeps tomorrow easier."),
        Payload(title: "Last light, first draft", body: "Speak once. Mean it. Then rest."),
        Payload(title: "Your streak-friendly minute", body: "Even a soft session counts — show up anyway."),
        Payload(title: "Quiet courage", body: "The room is yours. One prompt. One breath. Go."),
        Payload(title: "End on a spoken note", body: "Sixty seconds of honesty with yourself."),
    ]

    private static let streakStandard: [String] = [
        "One short session keeps the chain alive.",
        "You’re so close to keeping it going.",
        "Don’t let today be the gap in the story.",
        "A quick practice locks in another day.",
        "The streak doesn’t need perfect — it needs present.",
        "Come back for sixty seconds. Future you will thank you.",
        "You’ve already started. Finishing today is the hard part — and the good part.",
        "Momentum is fragile at night. Protect it with one take.",
    ]

    private static let streakLate: [String] = [
        "Still time tonight — one minute keeps the streak honest.",
        "Before the day closes: a short practice seals it.",
        "Late is fine. Missing isn’t. Tap in for sixty seconds.",
        "The streak is waiting by the door. Don’t leave it outside.",
        "One prompt. Then you’re done. Don’t break the chain in the last hour.",
    ]
}
