import SwiftUI

#if DEBUG

struct SystemStatusView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var service = SystemStatusService.shared
    @State private var appeared = false

    private var grouped: [(String, [SystemCheckItem])] {
        let order = ["App", "Device", "Supabase", "Database", "Storage", "Edge", "OpenAI"]
        let dict = Dictionary(grouping: service.report.items, by: \.category)
        return order.compactMap { key in
            guard let items = dict[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryCard
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                ForEach(grouped, id: \.0) { category, items in
                    categorySection(title: category, items: items)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .themeBackground()
        .navigationTitle("System Status")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.medium()
                    Task { await service.runAllChecks() }
                } label: {
                    if service.isRunning {
                        ProgressView()
                            .tint(Theme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .disabled(service.isRunning)
                .accessibilityLabel("Run checks again")
            }
        }
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce) {
                appeared = true
            }
            if service.report.items.isEmpty || service.report.finishedAt == nil {
                await service.runAllChecks()
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summaryTitle)
                .font(Theme.fraunces(28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text(summarySubtitle)
                .font(Theme.grotesk(15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                summaryPill(count: service.report.okCount, label: "OK", color: Theme.success)
                summaryPill(count: service.report.failCount, label: "Fail", color: Theme.accent)
                summaryPill(count: service.report.skipCount, label: "Skip", color: Theme.textSecondary)
            }

            if service.report.estimatedCostUsd > 0 {
                Text(String(format: "Probe cost ≈ $%.5f", service.report.estimatedCostUsd))
                    .font(Theme.grotesk(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else if service.report.finishedAt != nil {
                Text("Probe cost ≈ $0–0.00001 (free models list + optional 1-token)")
                    .font(Theme.grotesk(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.cardBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var summaryTitle: String {
        if service.isRunning { return "Checking…" }
        if service.report.finishedAt == nil { return "System status" }
        if service.report.failCount == 0 { return "All clear" }
        return "Needs attention"
    }

    private var summarySubtitle: String {
        if service.isRunning {
            return "Probing config, Supabase, database, storage, and a tiny OpenAI quota check."
        }
        if let finished = service.report.finishedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Last run \(formatter.localizedString(for: finished, relativeTo: Date())). Debug builds only."
        }
        return "Verifies everything the app depends on."
    }

    private func summaryPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(Theme.fraunces(22, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.grotesk(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func categorySection(title: String, items: [SystemCheckItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Theme.grotesk(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.6)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    checkRow(item)
                    if index < items.count - 1 {
                        Divider()
                            .overlay(Theme.textSecondary.opacity(0.18))
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Theme.cardBackground.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
    }

    private func checkRow(_ item: SystemCheckItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusMark(item.status)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(Theme.grotesk(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.grotesk(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let cost = item.costUsd, cost > 0 {
                    Text(String(format: "~$%.5f", cost))
                        .font(Theme.grotesk(11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(accessibilityStatus(item.status))")
        .accessibilityValue(item.detail ?? "")
    }

    @ViewBuilder
    private func statusMark(_ status: SystemCheckStatus) -> some View {
        switch status {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.success)
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accent)
        case .skip:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textSecondary.opacity(0.55))
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.4))
        }
    }

    private func accessibilityStatus(_ status: SystemCheckStatus) -> String {
        switch status {
        case .ok: return "working"
        case .fail: return "not working"
        case .skip: return "skipped"
        case .running: return "checking"
        case .pending: return "pending"
        }
    }
}

#Preview {
    NavigationStack {
        SystemStatusView()
    }
}

#endif
