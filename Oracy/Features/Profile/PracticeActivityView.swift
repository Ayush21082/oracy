import SwiftUI

// MARK: - Model

struct PracticeActivityDay: Identifiable, Equatable, Hashable {
    let date: Date
    let sessionCount: Int
    let totalSeconds: Double
    /// Outside the active window (leading pad before range start).
    let isPlaceholder: Bool
    /// Day after today — year-ahead cells; may still have mock/preview sessions.
    let isFuture: Bool

    var id: Date { date }

    var minutes: Int { Int((totalSeconds / 60.0).rounded()) }

    /// 0 = empty … 4 = strongest day. -1 = hidden pad.
    var intensity: Int {
        if isPlaceholder { return -1 }
        switch sessionCount {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        case 3: return 3
        default: return 4
        }
    }
}

struct PracticeActivityModel: Equatable {
    /// Weeks left→right: join week → year ahead of today.
    let weeks: [[PracticeActivityDay]]
    let totalMinutes: Int
    let activeDays: Int
    /// Week index containing today (for optional jump-ahead).
    let todayWeekIndex: Int

    init(
        sessions: [SpeakingSession],
        joinedAt: Date? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let joinedDay = cal.startOfDay(for: joinedAt ?? today)
        // Dots begin on the join day (never after today).
        let rangeStart = min(joinedDay, today)
        let yearAhead = cal.date(byAdding: .year, value: 1, to: today) ?? today

        let startWeek = cal.dateInterval(of: .weekOfYear, for: rangeStart)?.start ?? rangeStart
        let endWeek = cal.dateInterval(of: .weekOfYear, for: yearAhead)?.end
            ?? yearAhead.addingTimeInterval(24 * 60 * 60)
        let lastDay = cal.date(byAdding: .day, value: -1, to: endWeek) ?? yearAhead

        var totals: [Date: (count: Int, seconds: Double)] = [:]
        for session in sessions {
            guard let created = session.createdAt else { continue }
            let day = cal.startOfDay(for: created)
            guard day >= rangeStart, day <= yearAhead else { continue }
            let prior = totals[day] ?? (0, 0)
            totals[day] = (
                prior.count + 1,
                prior.seconds + (session.durationSeconds ?? 0)
            )
        }

        var builtWeeks: [[PracticeActivityDay]] = []
        var todayWeek = 0
        var cursor = startWeek
        while cursor <= lastDay {
            var week: [PracticeActivityDay] = []
            for offset in 0..<7 {
                let day = cal.date(byAdding: .day, value: offset, to: cursor) ?? cursor
                let dayStart = cal.startOfDay(for: day)
                // Hide weekday cells before the join day in the first week.
                let leadingPad = dayStart < rangeStart
                let trailingPad = dayStart > yearAhead
                let future = dayStart > today && !trailingPad
                let placeholder = leadingPad || trailingPad
                let stats = totals[dayStart] ?? (0, 0)
                week.append(
                    PracticeActivityDay(
                        date: dayStart,
                        sessionCount: placeholder ? 0 : stats.count,
                        totalSeconds: placeholder ? 0 : stats.seconds,
                        isPlaceholder: placeholder,
                        isFuture: future
                    )
                )
                if dayStart == today {
                    todayWeek = builtWeeks.count
                }
            }
            builtWeeks.append(week)
            guard let next = cal.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }

        weeks = builtWeeks
        todayWeekIndex = min(todayWeek, max(builtWeeks.count - 1, 0))
        totalMinutes = Int((totals.values.reduce(0) { $0 + $1.seconds } / 60.0).rounded())
        activeDays = totals.values.filter { $0.count > 0 }.count
    }

    static let empty = PracticeActivityModel(sessions: [])
}

// MARK: - Section

struct PracticeActivitySection: View {
    let model: PracticeActivityModel
    let streak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay: PracticeActivityDay?
    @State private var revealProgress: CGFloat = 0

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3
    private let edgeFade: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            grid
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { playEntrance() }
        .onChange(of: model) { _, _ in
            selectedDay = nil
            playEntrance(reset: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Practice activity")
                    .font(Theme.fraunces(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                ProfileSectionInfoButton(
                    title: "Practice activity",
                    message: "Each square is a day from when you joined through the year ahead. Soft empty dots are quiet or upcoming; warmer fills mean you spoke. Scroll to see further ahead. Tap a day for sessions and minutes.",
                    point: .bottom
                )
            }

            Text("From the day you joined — scroll to peek ahead.")
                .font(Theme.grotesk(13))
                .foregroundStyle(Theme.textSecondary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Text(summaryLine)
                .font(Theme.grotesk(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: selectedDay?.id)
        }
    }

    private var summaryLine: String {
        if let selectedDay {
            return detailLine(for: selectedDay)
        }
        if streak > 0 {
            return "\(streak) day streak · \(model.totalMinutes) min practiced"
        }
        return "\(model.totalMinutes) min practiced · \(model.activeDays) days"
    }

    private func detailLine(for day: PracticeActivityDay) -> String {
        let date = Self.dayFormatter.string(from: day.date)
        if day.isPlaceholder {
            return date
        }
        if day.sessionCount == 0 {
            return day.isFuture ? "\(date) · upcoming" : "\(date) · no practice"
        }
        let sessions = day.sessionCount == 1 ? "1 session" : "\(day.sessionCount) sessions"
        let minutes = day.minutes == 1 ? "1 min" : "\(max(day.minutes, 1)) min"
        return "\(date) · \(sessions) · \(minutes)"
    }

    private var grid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                monthRow
                weeksRow
            }
            // Align with section title; only pad/fade the trailing edge while scrolling.
            .padding(.trailing, edgeFade)
            .padding(.vertical, 2)
        }
        .mask {
            HorizontalEdgeFadeMask(fadeWidth: edgeFade, fadeLeading: false)
        }
    }

    private var monthRow: some View {
        // Labels keep a cell-wide layout slot but draw at natural width so “Sep” isn’t clipped.
        HStack(alignment: .center, spacing: gap) {
            ForEach(Array(model.weeks.enumerated()), id: \.offset) { weekIndex, week in
                ZStack(alignment: .leading) {
                    Color.clear.frame(width: cell, height: 14)
                    if shouldShowMonthLabel(at: weekIndex, week: week) {
                        Text(Self.monthFormatter.string(from: labelDate(for: week)))
                            .font(Theme.grotesk(11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary.opacity(0.9))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(width: cell, height: 14, alignment: .leading)
            }
        }
        .allowsHitTesting(false)
    }

    private func labelDate(for week: [PracticeActivityDay]) -> Date {
        (week.first(where: { !$0.isPlaceholder }) ?? week.first)?.date ?? Date()
    }

    private var weeksRow: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(model.weeks.enumerated()), id: \.offset) { weekIndex, week in
                VStack(spacing: gap) {
                    ForEach(Array(week.enumerated()), id: \.element.id) { dayIndex, day in
                        ActivityDot(
                            intensity: day.intensity,
                            size: cell,
                            reveal: revealAmount(weekIndex: weekIndex, dayIndex: dayIndex),
                            isSelected: selectedDay?.date == day.date
                        )
                        .onTapGesture {
                            guard !day.isPlaceholder else { return }
                            Haptics.selectionChanged()
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedDay = selectedDay?.date == day.date ? nil : day
                            }
                        }
                        .accessibilityLabel(detailLine(for: day))
                        .accessibilityAddTraits(selectedDay?.date == day.date ? .isSelected : [])
                        .accessibilityHidden(day.isPlaceholder)
                    }
                }
                .id(weekIndex)
            }
        }
    }

    private func shouldShowMonthLabel(at weekIndex: Int, week: [PracticeActivityDay]) -> Bool {
        guard let firstVisible = week.first(where: { !$0.isPlaceholder }) ?? week.first else {
            return false
        }
        let cal = Calendar.current
        let month = cal.component(.month, from: firstVisible.date)
        if weekIndex == 0 { return true }
        guard let prev = model.weeks[weekIndex - 1].first(where: { !$0.isPlaceholder })
                ?? model.weeks[weekIndex - 1].first else {
            return true
        }
        return cal.component(.month, from: prev.date) != month
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(Theme.grotesk(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: gap) {
                ForEach(0..<5, id: \.self) { level in
                    ActivityDot(intensity: level, size: cell - 1, reveal: 1, isSelected: false)
                }
            }

            Text("More")
                .font(Theme.grotesk(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity intensity from less to more")
    }

    private func revealAmount(weekIndex: Int, dayIndex: Int) -> CGFloat {
        guard revealProgress < 1 else { return 1 }
        let weeks = max(model.weeks.count - 1, 1)
        let t = (CGFloat(weekIndex) + CGFloat(dayIndex) * 0.08) / CGFloat(weeks)
        return min(1, max(0, (revealProgress - t * 0.55) / 0.45))
    }

    private func playEntrance(reset: Bool = false) {
        if reduceMotion {
            revealProgress = 1
            return
        }
        if reset { revealProgress = 0 }
        withAnimation(.easeOut(duration: 1.1)) {
            revealProgress = 1
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()
}

// MARK: - Soft scroll edges

struct HorizontalEdgeFadeMask: View {
    var fadeWidth: CGFloat = 28
    /// When false, the leading edge stays solid so the first dots align with section text.
    var fadeLeading: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            if fadeLeading {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
            }

            Color.black

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
        }
    }
}

/// Softens content as it scrolls under the status bar / top edge.
struct VerticalEdgeFadeMask: View {
    var fadeHeight: CGFloat = 52
    var fadeTop: Bool = true
    var fadeBottom: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if fadeTop {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }

            Color.black

            if fadeBottom {
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
        }
    }
}

// MARK: - Section info

struct ProfileSectionInfoButton: View {
    let title: String
    let message: String
    /// Where on the info button the popover anchors.
    var point: UnitPoint = .bottom
    /// Edge of the popover that faces the button (arrow side).
    /// Use `.top` to open below the button; `.bottom` to open above (better near screen bottom).
    var arrowEdge: Edge = .top

    @State private var showInfo = false

    var body: some View {
        Button {
            Haptics.light()
            showInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.75))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $showInfo, attachmentAnchor: .point(point), arrowEdge: arrowEdge) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Theme.fraunces(18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(message)
                    .font(Theme.grotesk(14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(width: 280, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Dot

private struct ActivityDot: View {
    /// -1 = placeholder, 0 = empty, 1…4 = intensity.
    let intensity: Int
    let size: CGFloat
    let reveal: CGFloat
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.55), lineWidth: 1)
                }
            }
            .opacity(intensity < 0 ? 0 : Double(reveal))
            .scaleEffect(intensity < 0 ? 1 : (0.82 + 0.18 * reveal))
            .accessibilityHidden(intensity < 0)
    }

    private var fill: Color {
        switch intensity {
        case -1:
            return .clear
        case 0:
            return colorScheme == .dark
                ? Color.white.opacity(0.07)
                : Color.black.opacity(0.06)
        case 1:
            return Theme.accent.opacity(colorScheme == .dark ? 0.28 : 0.22)
        case 2:
            return Theme.accent.opacity(colorScheme == .dark ? 0.48 : 0.42)
        case 3:
            return Theme.accent.opacity(colorScheme == .dark ? 0.72 : 0.68)
        default:
            return Theme.accent
        }
    }
}
