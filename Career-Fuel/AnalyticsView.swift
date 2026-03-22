import Charts
import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject private var jobStore: JobApplicationStore
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var aiService: AIInsightService
    @EnvironmentObject private var appModeStore: AppModeStore

    @State private var spendWindow: SpendWindow = .weekly

    private var weeklySpendPoints: [WeeklySpendPoint] {
        expenseStore.analyticsSummary.weeklySpendHistory
    }

    private var monthlySpendPoints: [MonthlySpendPoint] {
        expenseStore.analyticsSummary.monthlySpendHistory
    }

    private var pipelinePoints: [ApplicationStagePoint] {
        jobStore.analyticsSummary.pipelinePoints
    }

    private var timeToHireEstimate: Int {
        jobStore.analyticsSummary.timeToHireEstimate
    }

    private var hiringLikelihood: Int {
        jobStore.analyticsSummary.hiringLikelihood
    }

    private var forecastWindowDays: Int {
        min(max(expenseStore.daysLeft, 7), 30)
    }

    private var projectedShortage: Double {
        max((expenseStore.dailyBurnRate - aiService.recommendedDailyBudget) * Double(forecastWindowDays), 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Analytics",
                subtitle: appModeStore.mode == .jobSearch
                    ? "Track spend cadence, pipeline health, and the likely pressure points ahead."
                    : "Track spending trends, your accepted role, and how stable your finances stay after getting hired."
            )

            SurfaceCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Spend trend")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)

                            Text("Weekly and monthly spending against the AI target pace.")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textSecondary)
                        }

                        Spacer()

                        Picker("Spend window", selection: $spendWindow) {
                            ForEach(SpendWindow.allCases) { window in
                                Text(window.title).tag(window)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }

                    Group {
                        switch spendWindow {
                        case .weekly:
                            weeklyChart
                        case .monthly:
                            monthlyChart
                        }
                    }
                    .frame(height: 240)
                    .animation(.easeInOut(duration: 0.25), value: spendWindow)
                }
            }

            Group {
                if horizontalCompact {
                    VStack(spacing: 16) {
                        pipelineCard
                        forecastCard
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        pipelineCard
                        forecastCard
                    }
                }
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var horizontalCompact: Bool {
        horizontalSizeClass != .regular
    }

    private var weeklyChart: some View {
        Chart {
            ForEach(weeklySpendPoints) { point in
                AreaMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Spend", point.amount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppPalette.primary.opacity(0.22), AppPalette.primary.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Spend", point.amount)
                )
                .foregroundStyle(AppPalette.primary)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Spend", point.amount)
                )
                .foregroundStyle(AppPalette.primary)
            }

            RuleMark(y: .value("AI target", aiService.recommendedDailyBudget * 7))
                .foregroundStyle(AppPalette.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private var monthlyChart: some View {
        Chart {
            ForEach(monthlySpendPoints) { point in
                BarMark(
                    x: .value("Month", point.monthStart, unit: .month),
                    y: .value("Spend", point.amount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppPalette.primary, AppPalette.primary.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(10)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private var pipelineCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Application pipeline")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)

                Text("See where applications are concentrating over time so you know whether to apply, prep, or negotiate.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)

                Chart {
                    ForEach(pipelinePoints) { point in
                        BarMark(
                            x: .value("Stage", point.stageTitle),
                            y: .value("Count", point.count)
                        )
                        .foregroundStyle(point.tone.color)
                        .cornerRadius(10)
                    }
                }
                .frame(height: 220)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var forecastCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                if appModeStore.mode == .jobSearch {
                    Text("Forecast")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text("Uses live pipeline stages and average daily spend to estimate hiring pressure over the next few weeks.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)

                    VStack(spacing: 12) {
                        MiniStatCard(title: "Time to hire estimate", value: timeToHireEstimate == 0 ? "Role secured" : "\(timeToHireEstimate) days")
                        MiniStatCard(title: "Hiring likelihood", value: "\(hiringLikelihood)% in 30 days")
                        MiniStatCard(
                            title: "Projected shortage",
                            value: projectedShortage > 0 ? projectedShortage.currencyString : "On plan"
                        )
                    }

                    if projectedShortage > 0 {
                        Label(
                            "Current average daily spend suggests a potential shortage within the next \(forecastWindowDays) days. Use the AI budget cards to slow the outflow.",
                            systemImage: "bolt.badge.clock"
                        )
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                    } else {
                        Label(
                            "Your current trajectory is inside the target runway pace.",
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.success)
                    }
                } else {
                    Text("Financial stability")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text("Once a role is accepted, the forecast shifts from hiring odds to income durability and fallback runway.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)

                    VStack(spacing: 12) {
                        MiniStatCard(
                            title: "Current role",
                            value: appModeStore.acceptedEmployment.map { "\($0.companyName) · \($0.role)" } ?? "Accepted role"
                        )
                        MiniStatCard(
                            title: "Monthly margin",
                            value: expenseStore.monthlySavingsCapacity.currencyString
                        )
                        MiniStatCard(
                            title: "Runway if unemployed again",
                            value: "\(expenseStore.runwayIfUnemployedAgainDays) days"
                        )
                    }

                    Label(
                        expenseStore.employmentSnapshot.stabilityMessage,
                        systemImage: expenseStore.employmentSnapshot.stabilityTone == .danger
                            ? "exclamationmark.triangle.fill"
                            : "shield.checkered"
                    )
                    .font(.subheadline)
                    .foregroundStyle(expenseStore.employmentSnapshot.stabilityTone.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension AnalyticsView {
    enum SpendWindow: String, CaseIterable, Identifiable {
        case weekly
        case monthly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weekly:
                return "Weekly"
            case .monthly:
                return "Monthly"
            }
        }
    }
}

private extension Collection where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
