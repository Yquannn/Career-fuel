import Combine
import SwiftUI

struct DashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appModeStore: AppModeStore

    @State private var showingBalanceEditor = false
    @State private var showingIncomeEditor = false

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DashboardHeaderSection(isWideLayout: isWideLayout) {
                showingBalanceEditor = true
            }

            Group {
                if appModeStore.mode == .jobSearch {
                    if isWideLayout {
                        HStack(alignment: .top, spacing: 20) {
                            RunwayCardSection(isWideLayout: true)

                            MetricStackSection {
                                showingBalanceEditor = true
                            }
                            .frame(width: 310)
                        }
                    } else {
                        VStack(spacing: 20) {
                            RunwayCardSection(isWideLayout: false)

                            MetricStackSection {
                                showingBalanceEditor = true
                            }
                        }
                    }
                } else {
                    if isWideLayout {
                        HStack(alignment: .top, spacing: 20) {
                            EmployedOverviewSection(isWideLayout: true)

                            MetricStackSection {
                                showingIncomeEditor = true
                            }
                            .frame(width: 310)
                        }
                    } else {
                        VStack(spacing: 20) {
                            EmployedOverviewSection(isWideLayout: false)

                            MetricStackSection {
                                showingIncomeEditor = true
                            }
                        }
                    }
                }
            }

            SmartAlertsSection()
            DecisionSignalsSection()
        }
        .sheet(isPresented: $showingBalanceEditor) {
            CurrentBalanceSheetBridge()
        }
        .sheet(isPresented: $showingIncomeEditor) {
            MonthlyIncomeSheetBridge()
        }
    }
}

private struct CurrentBalanceSheetBridge: View {
    @EnvironmentObject private var expenseStore: ExpenseStore

    var body: some View {
        CurrentBalanceSheet(currentBalance: expenseStore.currentBalance) { amount in
            expenseStore.setCurrentBalance(amount)
        }
    }
}

private struct MonthlyIncomeSheetBridge: View {
    @EnvironmentObject private var expenseStore: ExpenseStore

    var body: some View {
        MonthlyIncomeSheet(monthlyIncome: expenseStore.monthlyIncome) { amount in
            expenseStore.updateMonthlyIncome(amount)
        }
    }
}

private struct DashboardHeaderSection: View {
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var appModeStore: AppModeStore

    let isWideLayout: Bool
    let onEditBalance: () -> Void

    @StateObject private var viewModel = DashboardHeaderSectionModel()

    var body: some View {
        DashboardHeaderContentView(
            content: viewModel.content,
            isWideLayout: isWideLayout,
            onEditBalance: onEditBalance
        )
        .equatable()
        .task {
            viewModel.configureIfNeeded(
                expenseStore: expenseStore,
                cloudSyncManager: cloudSyncManager,
                appModeStore: appModeStore
            )
        }
    }
}

private struct EmployedOverviewSection: View {
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var appModeStore: AppModeStore

    let isWideLayout: Bool

    @StateObject private var viewModel = EmployedOverviewSectionModel()

    var body: some View {
        EmployedOverviewContentView(content: viewModel.content, isWideLayout: isWideLayout)
            .equatable()
            .task {
                viewModel.configureIfNeeded(
                    expenseStore: expenseStore,
                    appModeStore: appModeStore
                )
            }
    }
}

private struct RunwayCardSection: View {
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var aiService: AIInsightService
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var insightsStore: InsightsStore

    let isWideLayout: Bool

    @StateObject private var viewModel = RunwayCardSectionModel()

    var body: some View {
        RunwayCardContentView(content: viewModel.content, isWideLayout: isWideLayout)
            .equatable()
            .task {
                viewModel.configureIfNeeded(
                    expenseStore: expenseStore,
                    aiService: aiService,
                    cloudSyncManager: cloudSyncManager,
                    insightsStore: insightsStore
                )
            }
    }
}

private struct MetricStackSection: View {
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var jobStore: JobApplicationStore
    @EnvironmentObject private var appModeStore: AppModeStore
    @EnvironmentObject private var aiService: AIInsightService

    let onEditBalance: () -> Void

    @StateObject private var viewModel = MetricStackSectionModel()

    var body: some View {
        MetricStackContentView(content: viewModel.content, onEditBalance: onEditBalance)
            .equatable()
            .task {
                viewModel.configureIfNeeded(
                    expenseStore: expenseStore,
                    jobStore: jobStore,
                    appModeStore: appModeStore,
                    aiService: aiService
                )
            }
    }
}

private struct SmartAlertsSection: View {
    @EnvironmentObject private var aiService: AIInsightService

    @StateObject private var viewModel = SmartAlertsSectionModel()

    var body: some View {
        SmartAlertsContentView(content: viewModel.content)
            .equatable()
            .task {
                viewModel.configureIfNeeded(aiService: aiService)
            }
    }
}

private struct DecisionSignalsSection: View {
    @EnvironmentObject private var insightsStore: InsightsStore

    @StateObject private var viewModel = DecisionSignalsSectionModel()

    var body: some View {
        DecisionSignalsContentView(content: viewModel.content)
            .equatable()
            .task {
                viewModel.configureIfNeeded(insightsStore: insightsStore)
            }
    }
}

private struct DashboardHeaderContentView: View, Equatable {
    let content: DashboardHeaderContent
    let isWideLayout: Bool
    let onEditBalance: () -> Void

    static func == (lhs: DashboardHeaderContentView, rhs: DashboardHeaderContentView) -> Bool {
        lhs.content == rhs.content && lhs.isWideLayout == rhs.isWideLayout
    }

    var body: some View {
        Group {
            if isWideLayout {
                HStack(alignment: .top, spacing: 16) {
                    headerCopy
                    Spacer(minLength: 0)
                    headerChips(alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    headerCopy
                    headerChips(alignment: .leading)
                }
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Career Fuel")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.textPrimary)

            Text(content.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)

            Text(content.description)
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onEditBalance) {
                Label(content.balanceButtonTitle, systemImage: "wallet.pass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func headerChips(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 12) {
            InfoChip(symbol: "calendar", title: content.dateChipTitle)
            InfoChip(symbol: "dollarsign.circle", title: content.financeChipTitle)
            InfoChip(symbol: content.modeChipSymbol, title: content.modeChipTitle)
            InfoChip(symbol: content.cloudStatusSymbol, title: content.cloudStatusLabel)
        }
    }
}

private struct EmployedOverviewContentView: View, Equatable {
    let content: EmployedOverviewContent
    let isWideLayout: Bool

    static func == (lhs: EmployedOverviewContentView, rhs: EmployedOverviewContentView) -> Bool {
        lhs.content == rhs.content && lhs.isWideLayout == rhs.isWideLayout
    }

    var body: some View {
        SurfaceCard(spotlight: true) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Employment mode", systemImage: AppMode.employed.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppPalette.primary)

                        StatusBadge(label: content.stabilityLabel, tone: content.stabilityTone)
                    }

                    Spacer()

                    if !content.employmentTitle.isEmpty {
                        InfoChip(symbol: "building.2.fill", title: content.employmentTitle)
                    }
                }

                Group {
                    if isWideLayout {
                        HStack(spacing: 28) {
                            financialHeadline
                            savingsProgressCard
                        }
                    } else {
                        VStack(spacing: 16) {
                            financialHeadline
                            savingsProgressCard
                        }
                    }
                }

                Group {
                    if isWideLayout {
                        HStack(spacing: 12) {
                            MiniStatCard(title: "Current balance", value: content.currentBalance.currencyString)
                            MiniStatCard(title: "Savings rate", value: content.savingsRateLabel)
                            MiniStatCard(title: "Runway if unemployed", value: content.runwayFallbackLabel)
                        }
                    } else {
                        VStack(spacing: 12) {
                            MiniStatCard(title: "Current balance", value: content.currentBalance.currencyString)
                            MiniStatCard(title: "Savings rate", value: content.savingsRateLabel)
                            MiniStatCard(title: "Runway if unemployed", value: content.runwayFallbackLabel)
                        }
                    }
                }
            }
        }
    }

    private var financialHeadline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(content.monthlyMarginLabel)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(content.monthlyProjectionConfidence == .insufficient
                    ? AppPalette.accent
                    : (content.monthlySavingsCapacity >= 0 ? content.stabilityTone.color : AppPalette.danger))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.18), value: content.monthlyMarginLabel)

            Text("Net monthly margin after estimated expenses")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)

            Text(content.monthlySummary)
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(content.stabilityMessage)
                .font(.body)
                .foregroundStyle(AppPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savingsProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Emergency fund progress")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppPalette.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ProgressView(value: min(max(content.emergencyFundProgress, 0), 1))
                .tint(content.stabilityTone.color)

            Text(content.emergencyFundLabel)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)

            Text("Target three months of expenses so a future job gap does not become urgent again.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

private struct RunwayCardContentView: View, Equatable {
    let content: RunwayCardContent
    let isWideLayout: Bool

    static func == (lhs: RunwayCardContentView, rhs: RunwayCardContentView) -> Bool {
        lhs.content == rhs.content && lhs.isWideLayout == rhs.isWideLayout
    }

    var body: some View {
        SurfaceCard(spotlight: true) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Runway", systemImage: "gauge.with.dots.needle.50percent")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppPalette.primary)

                        StatusBadge(label: content.runwayLabel, tone: content.runwayTone)
                    }

                    Spacer()

                    InfoChip(
                        symbol: "calendar.badge.clock",
                        title: "Zero date \(content.projectedZeroDate.formatted(.dateTime.month(.abbreviated).day()))"
                    )
                }

                Group {
                    if isWideLayout {
                        HStack(spacing: 28) {
                            RunwayGauge(daysLeft: content.daysLeft, tone: content.runwayTone)
                                .frame(width: 230, height: 230)

                            runwayCopy

                            Spacer(minLength: 0)
                        }
                    } else {
                        VStack(spacing: 20) {
                            RunwayGauge(daysLeft: content.daysLeft, tone: content.runwayTone)
                                .frame(width: 220, height: 220)
                                .frame(maxWidth: .infinity)

                            runwayCopy
                        }
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: content.daysLeft)

                Group {
                    if isWideLayout {
                        HStack(spacing: 12) {
                            MiniStatCard(
                                title: "Projected zero date",
                                value: content.projectedZeroDate.formatted(.dateTime.month(.abbreviated).day())
                            )
                            MiniStatCard(
                                title: "Average daily spend (including zero days)",
                                value: content.burnRateConfidence == .insufficient
                                    ? "Not enough data"
                                    : content.dailyBurnRate.currencyString
                            )
                            MiniStatCard(
                                title: "Spend per active day",
                                value: content.burnRateConfidence == .insufficient
                                    ? "Not enough data"
                                    : content.activeDailySpendRate.currencyString
                            )
                            MiniStatCard(title: "AI target burn", value: content.recommendedDailyBudget.currencyString)
                        }
                    } else {
                        VStack(spacing: 12) {
                            MiniStatCard(
                                title: "Projected zero date",
                                value: content.projectedZeroDate.formatted(.dateTime.month(.abbreviated).day())
                            )
                            MiniStatCard(
                                title: "Average daily spend (including zero days)",
                                value: content.burnRateConfidence == .insufficient
                                    ? "Not enough data"
                                    : content.dailyBurnRate.currencyString
                            )
                            MiniStatCard(
                                title: "Spend per active day",
                                value: content.burnRateConfidence == .insufficient
                                    ? "Not enough data"
                                    : content.activeDailySpendRate.currencyString
                            )
                            MiniStatCard(title: "AI target burn", value: content.recommendedDailyBudget.currencyString)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("7-day burn trend")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppPalette.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    BurnTrendView(points: content.sevenDayTrend)
                }
            }
        }
    }

    private var runwayCopy: some View {
        VStack(alignment: .leading, spacing: 16) {
            if content.currentBalance <= 0 {
                Text("Set your current balance")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.accent)
                    .frame(minHeight: 46, alignment: .leading)
            } else if content.burnRateConfidence == .insufficient {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Not enough data")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.accent)
                        .frame(minHeight: 46, alignment: .leading)

                    Label("Log a few expense days so average daily spend and active-day intensity can settle.", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .frame(minHeight: 82, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You have \(content.daysLeft) days left")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(content.runwayTone.color)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.18), value: content.daysLeft)

                    HStack(spacing: 10) {
                        Label("Risk level", systemImage: "shield.lefthalf.filled")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppPalette.textSecondary)

                        StatusBadge(label: content.runwayLabel, tone: content.runwayTone)
                        StatusBadge(label: content.spendingTrend.title, tone: content.spendingTrend.tone)
                    }

                    Text(content.burnRateSupportingMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .frame(minHeight: 82, alignment: .topLeading)
            }

            if content.isAIRefreshing {
                ActivityPill(title: "Updating AI guidance")
                    .transition(.opacity)
            }

            Text(content.runwayMessage)
                .font(.body)
                .foregroundStyle(AppPalette.textPrimary)
                .frame(minHeight: 44, alignment: .topLeading)

            if let spendingAnomaly = content.spendingAnomaly {
                Label(spendingAnomaly.message, systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(spendingAnomaly.tone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(content.burnComparisonMessage, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)

                Text(content.syncMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 84, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppPalette.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppPalette.border, lineWidth: 1)
            )
        }
        .animation(.easeInOut(duration: 0.18), value: content.isAIRefreshing)
    }
}

private struct MetricStackContentView: View, Equatable {
    let content: MetricStackContent
    let onEditBalance: () -> Void

    static func == (lhs: MetricStackContentView, rhs: MetricStackContentView) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        VStack(spacing: 16) {
            MetricCard(
                title: content.balanceMetric.title,
                value: content.balanceMetric.value,
                tone: content.balanceMetric.tone,
                symbol: content.balanceMetric.symbol,
                footnote: content.balanceMetric.footnote
            )

            Button(action: onEditBalance) {
                Label(content.balanceButtonTitle, systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppPalette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppPalette.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            MetricCard(
                title: content.applicationsMetric.title,
                value: content.applicationsMetric.value,
                tone: content.applicationsMetric.tone,
                symbol: content.applicationsMetric.symbol,
                footnote: content.applicationsMetric.footnote
            )

            MetricCard(
                title: content.weeklySpendingMetric.title,
                value: content.weeklySpendingMetric.value,
                tone: content.weeklySpendingMetric.tone,
                symbol: content.weeklySpendingMetric.symbol,
                footnote: content.weeklySpendingMetric.footnote
            )
        }
    }
}

private struct SmartAlertsContentView: View, Equatable {
    let content: SmartAlertsContent

    static func == (lhs: SmartAlertsContentView, rhs: SmartAlertsContentView) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Smart alerts",
                    subtitle: "AI-led spending alerts and budget limits based on your recent patterns."
                )

                if content.isRefreshing {
                    ActivityPill(title: "Refreshing AI alerts")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if content.spendingAlerts.isEmpty, content.budgetRecommendations.isEmpty {
                        LoadingStateCard(
                            title: content.isRefreshing ? "Refreshing AI alerts" : "No alerts yet",
                            message: content.isRefreshing
                                ? "Reviewing your latest spending pattern and budget targets."
                                : "Once enough spending data is available, Career Fuel will surface learned alerts and budget targets here."
                        )
                        .frame(width: 280)
                    }

                    ForEach(content.spendingAlerts) { alert in
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: alert.symbol)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(alert.tone.color)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(alert.tone.fill)
                                        )

                                    Spacer()

                                    StatusBadge(label: alert.tone.title, tone: alert.tone)
                                }

                                Text(alert.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppPalette.textPrimary)

                                Text(alert.message)
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(minHeight: 176, alignment: .topLeading)
                            .frame(width: 280, alignment: .leading)
                        }
                    }

                    ForEach(content.budgetRecommendations) { budget in
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: budget.category.symbol)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(AppPalette.primary)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(AppPalette.primary.opacity(0.14))
                                        )

                                    Spacer()

                                    StatusBadge(label: "Budget", tone: .info)
                                }

                                Text("\(budget.category.title) limit")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppPalette.textPrimary)

                                Text(budget.weeklyLimit.currencyString + "/week")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppPalette.textPrimary)
                                    .monospacedDigit()

                                Text(budget.rationale)
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(minHeight: 176, alignment: .topLeading)
                            .frame(width: 280, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: content)
    }
}

private struct DecisionSignalsContentView: View, Equatable {
    @EnvironmentObject private var appModeStore: AppModeStore
    let content: DecisionSignalsContent

    static func == (lhs: DecisionSignalsContentView, rhs: DecisionSignalsContentView) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Decision signals",
                    subtitle: appModeStore.mode == .jobSearch
                        ? "Short, actionable guidance based on runway, application momentum, AI analysis, and cloud sync state."
                        : "Short, actionable guidance based on savings discipline, financial stability, AI analysis, and cloud sync state."
                )

                if content.isRefreshing {
                    ActivityPill(title: "Refreshing decision signals")
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                if content.insights.isEmpty {
                    LoadingStateCard(
                        title: content.isRefreshing ? "Refreshing decision signals" : "No decision signals yet",
                        message: content.isRefreshing
                            ? (appModeStore.mode == .jobSearch
                                ? "Re-evaluating runway, pipeline, AI alerts, and sync state."
                                : "Re-evaluating income, savings, spending alerts, and sync state.")
                            : "Decision signals will appear here once the app has enough live state to prioritize your next move."
                    )
                }

                ForEach(content.insights) { insight in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top) {
                                Image(systemName: insight.symbol)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(insight.tone.color)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(insight.tone.fill)
                                    )

                                Spacer()

                                StatusBadge(label: insight.priority, tone: insight.tone)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(insight.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppPalette.textPrimary)

                                Text(insight.message)
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(minHeight: 156, alignment: .topLeading)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: content)
    }
}

private struct DashboardHeaderContent: Equatable {
    var dateChipTitle: String
    var financeChipTitle: String
    var modeChipSymbol: String
    var modeChipTitle: String
    var headline: String
    var description: String
    var cloudStatusSymbol: String
    var cloudStatusLabel: String
    var balanceButtonTitle: String

    static let placeholder = DashboardHeaderContent(
        dateChipTitle: Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
        financeChipTitle: "Avg daily spend \(0.0.currencyString)/day",
        modeChipSymbol: AppMode.jobSearch.symbol,
        modeChipTitle: AppMode.jobSearch.title,
        headline: "Career runway control panel",
        description: "Make faster decisions on cash runway, job momentum, and the next move that buys you time.",
        cloudStatusSymbol: "icloud.slash",
        cloudStatusLabel: "Unavailable",
        balanceButtonTitle: "Set Current Balance"
    )
}

private struct RunwayCardContent: Equatable {
    var currentBalance: Double
    var daysLeft: Int
    var observedExpenseDays: Int
    var trackedCalendarDays: Int
    var weeklySpending: Double
    var projectedZeroDate: Date
    var dailyBurnRate: Double
    var activeDailySpendRate: Double
    var weightedDailyBurnRate: Double
    var recommendedDailyBudget: Double
    var burnRateConfidence: BurnRateConfidence
    var spendingTrend: SpendingTrend
    var spendingAnomaly: SpendingAnomaly?
    var runwayTone: StatusTone
    var runwayLabel: String
    var runwayMessage: String
    var syncMessage: String
    var sevenDayTrend: [DailyExpensePoint]
    var isAIRefreshing: Bool
    var spendingFrequency: Double
    var spenderBehavior: SpenderBehavior

    var burnComparisonMessage: String {
        if burnRateConfidence == .insufficient {
            return "Log at least 3 expense days to unlock a stable burn-rate estimate."
        }

        if burnRateConfidence == .low {
            return "This forecast is early and based on \(trackedCalendarDays) tracked calendar day\(trackedCalendarDays == 1 ? "" : "s"), with \(observedExpenseDays) active spend day\(observedExpenseDays == 1 ? "" : "s")."
        }

        if dailyBurnRate > 0, activeDailySpendRate >= dailyBurnRate * 1.35 {
            return "Your spend is concentrated on active days. Large transaction days can compress runway even when some days stay at zero."
        }

        return weeklySpending > recommendedDailyBudget * 7
            ? "Your average daily spend is above the AI target pace this week."
            : "Average daily spend and active-day intensity are both inside the target range this week."
    }

    var burnRateSupportingMessage: String {
        let frequencyPct = Int((spendingFrequency * 100).rounded())
        switch burnRateConfidence {
        case .insufficient:
            return "Not enough data yet"
        case .low:
            return "Based on \(trackedCalendarDays) calendar day\(trackedCalendarDays == 1 ? "" : "s") and \(observedExpenseDays) spend day\(observedExpenseDays == 1 ? "" : "s") (\(frequencyPct)% frequency, \(spenderBehavior.displayLabel)) · low confidence"
        case .medium:
            return "Based on \(trackedCalendarDays) calendar day\(trackedCalendarDays == 1 ? "" : "s") and \(observedExpenseDays) spend day\(observedExpenseDays == 1 ? "" : "s") (\(frequencyPct)% frequency, \(spenderBehavior.displayLabel)) · medium confidence"
        case .high:
            return "Based on \(trackedCalendarDays) calendar day\(trackedCalendarDays == 1 ? "" : "s") and \(observedExpenseDays) spend day\(observedExpenseDays == 1 ? "" : "s") (\(frequencyPct)% frequency, \(spenderBehavior.displayLabel)) · high confidence"
        }
    }

    static let placeholder = RunwayCardContent(
        currentBalance: 0,
        daysLeft: 0,
        observedExpenseDays: 0,
        trackedCalendarDays: 0,
        weeklySpending: 0,
        projectedZeroDate: Date(),
        dailyBurnRate: 0,
        activeDailySpendRate: 0,
        weightedDailyBurnRate: 0,
        recommendedDailyBudget: 40,
        burnRateConfidence: .insufficient,
        spendingTrend: .stable,
        spendingAnomaly: nil,
        runwayTone: .warning,
        runwayLabel: "Warning",
        runwayMessage: "",
        syncMessage: "",
        sevenDayTrend: [],
        isAIRefreshing: false,
        spendingFrequency: 0,
        spenderBehavior: .mixed
    )
}

private struct MetricItemContent: Equatable {
    var title: String
    var value: String
    var tone: StatusTone
    var symbol: String
    var footnote: String
}

private struct MetricStackContent: Equatable {
    var balanceMetric: MetricItemContent
    var balanceButtonTitle: String
    var applicationsMetric: MetricItemContent
    var weeklySpendingMetric: MetricItemContent

    static let placeholder = MetricStackContent(
        balanceMetric: MetricItemContent(
            title: "Current Balance",
            value: 0.0.currencyString,
            tone: .info,
            symbol: "wallet.pass.fill",
            footnote: "Set the balance first so runway and burn rate are based on your real cash."
        ),
        balanceButtonTitle: "Enter Current Balance",
        applicationsMetric: MetricItemContent(
            title: "Active Applications",
            value: "0",
            tone: .info,
            symbol: "briefcase.fill",
            footnote: "0 interview-stage roles can convert soon."
        ),
        weeklySpendingMetric: MetricItemContent(
            title: "Weekly Spending",
            value: 0.0.currencyString,
            tone: .success,
            symbol: "chart.line.uptrend.xyaxis",
            footnote: "Spending is inside the target range."
        )
    )
}

private struct SmartAlertsContent: Equatable {
    var spendingAlerts: [AISpendingAlert]
    var budgetRecommendations: [BudgetRecommendation]
    var isRefreshing: Bool

    static let empty = SmartAlertsContent(
        spendingAlerts: [],
        budgetRecommendations: [],
        isRefreshing: false
    )
}

private struct DecisionSignalsContent: Equatable {
    var insights: [DashboardInsight]
    var isRefreshing: Bool

    static let empty = DecisionSignalsContent(insights: [], isRefreshing: false)
}

private struct DashboardCloudStatus: Equatable {
    var symbol: String
    var label: String
}

private struct DashboardHeaderFinanceState: Equatable {
    var currentBalance: Double
    var dailyBurnRate: Double
    var burnRateConfidence: BurnRateConfidence
    var monthlyIncome: Double
}

private struct DashboardRunwayStatus: Equatable {
    var tone: StatusTone
    var label: String
    var message: String
}

private struct MetricStackInput: Equatable {
    var snapshot: ExpenseDashboardSnapshot
    var employmentSnapshot: EmploymentFinancialSnapshot
    var decisionSnapshot: JobDecisionSnapshot
    var appMode: AppMode
    var recommendedDailyBudget: Double
}

private struct EmployedOverviewContent: Equatable {
    var employmentTitle: String
    var monthlySavingsCapacity: Double
    var monthlyIncome: Double
    var monthlyExpenseEstimate: Double
    var monthlyProjectionObservedDays: Int
    var monthlyProjectionConfidence: BurnRateConfidence
    var currentBalance: Double
    var savingsRate: Double
    var emergencyFundTarget: Double
    var emergencyFundProgress: Double
    var runwayIfUnemployedAgainDays: Int
    var stabilityTone: StatusTone
    var stabilityLabel: String
    var stabilityMessage: String
    var spendingFrequency: Double
    var spenderBehavior: SpenderBehavior

    var savingsRateLabel: String {
        if monthlyProjectionConfidence == .insufficient {
            return "No data"
        }
        return "\(Int((max(savingsRate, 0) * 100).rounded()))%"
    }

    var monthlyMarginLabel: String {
        if monthlyProjectionConfidence == .insufficient {
            return "No data"
        }
        return monthlySavingsCapacity.currencyString
    }

    var runwayFallbackLabel: String {
        if monthlyProjectionConfidence == .insufficient {
            return "No data"
        }
        return "\(runwayIfUnemployedAgainDays) days"
    }

    var emergencyFundLabel: String {
        if monthlyProjectionConfidence == .insufficient {
            return "Track expenses first"
        }
        return "\(Int((min(emergencyFundProgress, 1.5) * 100).rounded()))% of \(emergencyFundTarget.currencyString)"
    }

    var monthlySummary: String {
        if monthlyProjectionConfidence == .insufficient {
            return "No monthly expense projection yet. Start logging expenses so income can be compared against real spending."
        }

        return "You spend on \(monthlyProjectionObservedDays) out of 30 days (\(Int((spendingFrequency * 100).rounded()))% frequency, \(spenderBehavior.displayLabel)). Income \(monthlyIncome.currencyString) vs estimated expenses \(monthlyExpenseEstimate.currencyString) each month."
    }

    static let placeholder = EmployedOverviewContent(
        employmentTitle: "",
        monthlySavingsCapacity: 0,
        monthlyIncome: 0,
        monthlyExpenseEstimate: 0,
        monthlyProjectionObservedDays: 0,
        monthlyProjectionConfidence: .insufficient,
        currentBalance: 0,
        savingsRate: 0,
        emergencyFundTarget: 1,
        emergencyFundProgress: 0,
        runwayIfUnemployedAgainDays: 0,
        stabilityTone: .warning,
        stabilityLabel: "Income Missing",
        stabilityMessage: "Set your monthly take-home pay to unlock financial stability signals.",
        spendingFrequency: 0,
        spenderBehavior: .mixed
    )
}

@MainActor
private final class DashboardHeaderSectionModel: ObservableObject {
    @Published private(set) var content = DashboardHeaderContent.placeholder

    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    func configureIfNeeded(
        expenseStore: ExpenseStore,
        cloudSyncManager: CloudSyncManager,
        appModeStore: AppModeStore
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        Publishers.CombineLatest3(
            Publishers.CombineLatest(
                expenseStore.$dashboardSnapshot.removeDuplicates(),
                expenseStore.$employmentSnapshot.removeDuplicates()
            )
            .map { dashboardSnapshot, employmentSnapshot in
                DashboardHeaderFinanceState(
                    currentBalance: dashboardSnapshot.currentBalance,
                    dailyBurnRate: dashboardSnapshot.dailyBurnRate,
                    burnRateConfidence: dashboardSnapshot.burnRateConfidence,
                    monthlyIncome: employmentSnapshot.monthlyIncome
                )
            }
            .removeDuplicates(),
            cloudPublisher(cloudSyncManager),
            Publishers.CombineLatest(
                appModeStore.$mode.removeDuplicates(),
                appModeStore.$acceptedEmployment.removeDuplicates()
            )
        )
        .map { financeState, cloudState, modeState in
            let mode = modeState.0
            let acceptedEmployment = modeState.1
            return DashboardHeaderContent(
                dateChipTitle: Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                financeChipTitle: mode == .jobSearch
                    ? (financeState.burnRateConfidence == .insufficient
                        ? "Burn data still building"
                        : "Avg daily spend \(financeState.dailyBurnRate.currencyString)/day")
                    : (financeState.monthlyIncome > 0 ? "Income \(financeState.monthlyIncome.currencyString)/mo" : "Set monthly income"),
                modeChipSymbol: mode.symbol,
                modeChipTitle: mode.title,
                headline: mode == .jobSearch ? "Career runway control panel" : "Employment stability dashboard",
                description: mode == .jobSearch
                    ? "Make faster decisions on cash runway, job momentum, and the next move that buys you time."
                    : self.employedDescription(for: acceptedEmployment),
                cloudStatusSymbol: cloudState.symbol,
                cloudStatusLabel: cloudState.label,
                balanceButtonTitle: financeState.currentBalance > 0 ? "Update Current Balance" : "Set Current Balance"
            )
        }
        .removeDuplicates()
        .sink { [weak self] in
            self?.content = $0
        }
        .store(in: &cancellables)
    }

    private func employedDescription(for acceptedEmployment: AcceptedEmployment?) -> String {
        guard let acceptedEmployment else {
            return "Shift focus from survival runway to stable cash flow, savings discipline, and protecting your next transition."
        }

        return "You accepted \(acceptedEmployment.role) at \(acceptedEmployment.companyName). Shift focus from survival runway to stable cash flow and reserve building."
    }

    private func cloudPublisher(_ cloudSyncManager: CloudSyncManager) -> AnyPublisher<DashboardCloudStatus, Never> {
        Publishers.CombineLatest4(
            cloudSyncManager.$isCloudSyncEnabled,
            cloudSyncManager.$isSyncing,
            cloudSyncManager.$hasPendingChanges,
            cloudSyncManager.$lastSyncAt
        )
        .map { _ in
            DashboardCloudStatus(
                symbol: cloudSyncManager.statusSymbol,
                label: cloudSyncManager.statusLabel
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}

@MainActor
private final class RunwayCardSectionModel: ObservableObject {
    @Published private(set) var content = RunwayCardContent.placeholder

    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    func configureIfNeeded(
        expenseStore: ExpenseStore,
        aiService: AIInsightService,
        cloudSyncManager: CloudSyncManager,
        insightsStore: InsightsStore
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        let runwayStatusPublisher = Publishers.CombineLatest3(
            insightsStore.$runwayTone.removeDuplicates(),
            insightsStore.$runwayLabel.removeDuplicates(),
            insightsStore.$runwayMessage.removeDuplicates()
        )
        .map { DashboardRunwayStatus(tone: $0, label: $1, message: $2) }
        .removeDuplicates()

        Publishers.CombineLatest(
            Publishers.CombineLatest(
                Publishers.CombineLatest3(
                    expenseStore.$dashboardSnapshot.removeDuplicates(),
                    aiService.$recommendedDailyBudget.removeDuplicates(),
                    runwayStatusPublisher
                ),
                aiService.$isRefreshingExpenseInsights.removeDuplicates()
            ),
            cloudSyncManager.$syncMessage.removeDuplicates()
        )
        .map { combined, syncMessage in
            let (runwayCombined, isRefreshingExpenseInsights) = combined
            let (snapshot, recommendedDailyBudget, runwayStatus) = runwayCombined
            return RunwayCardContent(
                currentBalance: snapshot.currentBalance,
                daysLeft: snapshot.daysLeft,
                observedExpenseDays: snapshot.observedExpenseDays,
                trackedCalendarDays: snapshot.trackedCalendarDays,
                weeklySpending: snapshot.weeklySpending,
                projectedZeroDate: snapshot.projectedZeroDate,
                dailyBurnRate: snapshot.dailyBurnRate,
                activeDailySpendRate: snapshot.activeDailySpendRate,
                weightedDailyBurnRate: snapshot.weightedDailyBurnRate,
                recommendedDailyBudget: recommendedDailyBudget,
                burnRateConfidence: snapshot.burnRateConfidence,
                spendingTrend: snapshot.spendingTrend,
                spendingAnomaly: snapshot.spendingAnomaly,
                runwayTone: runwayStatus.tone,
                runwayLabel: runwayStatus.label,
                runwayMessage: runwayStatus.message,
                syncMessage: syncMessage,
                sevenDayTrend: snapshot.sevenDayTrend,
                isAIRefreshing: isRefreshingExpenseInsights,
                spendingFrequency: snapshot.spendingFrequency,
                spenderBehavior: snapshot.spenderBehavior
            )
        }
        .removeDuplicates()
        .sink { [weak self] in
            self?.content = $0
        }
        .store(in: &cancellables)
    }
}

@MainActor
private final class MetricStackSectionModel: ObservableObject {
    @Published private(set) var content = MetricStackContent.placeholder

    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    func configureIfNeeded(
        expenseStore: ExpenseStore,
        jobStore: JobApplicationStore,
        appModeStore: AppModeStore,
        aiService: AIInsightService
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        let inputPublisher = Publishers.CombineLatest(
            Publishers.CombineLatest4(
                expenseStore.$dashboardSnapshot.removeDuplicates(),
                expenseStore.$employmentSnapshot.removeDuplicates(),
                jobStore.$decisionSnapshot.removeDuplicates(),
                appModeStore.$mode.removeDuplicates()
            ),
            aiService.$recommendedDailyBudget.removeDuplicates()
        )
        .map { state, recommendedDailyBudget in
            MetricStackInput(
                snapshot: state.0,
                employmentSnapshot: state.1,
                decisionSnapshot: state.2,
                appMode: state.3,
                recommendedDailyBudget: recommendedDailyBudget
            )
        }
        .removeDuplicates()

        inputPublisher
        .map(makeContent(from:))
        .removeDuplicates()
        .sink { [weak self] in
            self?.content = $0
        }
        .store(in: &cancellables)
    }

    private func makeContent(from input: MetricStackInput) -> MetricStackContent {
        let snapshot = input.snapshot
        let employmentSnapshot = input.employmentSnapshot
        let decisionSnapshot = input.decisionSnapshot
        let recommendedDailyBudget = input.recommendedDailyBudget

        if input.appMode == .employed {
            return MetricStackContent(
                balanceMetric: MetricItemContent(
                    title: "Monthly Income",
                    value: employmentSnapshot.monthlyIncome.currencyString,
                    tone: employmentSnapshot.monthlyIncome > 0 ? .success : .warning,
                    symbol: "banknote.fill",
                    footnote: employmentSnapshot.monthlyIncome > 0
                        ? "Use take-home pay here so stability signals reflect what really lands in your account."
                        : "Set monthly income first so employed mode can compare earnings against spending."
                ),
                balanceButtonTitle: employmentSnapshot.monthlyIncome > 0 ? "Update Monthly Income" : "Set Monthly Income",
                applicationsMetric: MetricItemContent(
                    title: "Monthly Expenses",
                    value: employmentSnapshot.monthlyProjectionConfidence == .insufficient
                        ? "No data"
                        : employmentSnapshot.monthlyExpenseEstimate.currencyString,
                    tone: employmentSnapshot.monthlyProjectionConfidence == .insufficient
                        ? .warning
                        : (employmentSnapshot.monthlySavingsCapacity < 0 ? .danger : .info),
                    symbol: "creditcard.fill",
                    footnote: employmentSnapshot.monthlyProjectionConfidence == .insufficient
                        ? "Log expenses first. Monthly projection appears after real transaction data is available."
                        : employmentSnapshot.monthlyProjectionConfidence == .low
                            ? "Based on \(employmentSnapshot.monthlyProjectionObservedDays) days of data (\(employmentSnapshot.spenderBehavior.displayLabel)). Keep logging to stabilize the estimate."
                            : employmentSnapshot.monthlySavingsCapacity < 0
                                ? "Expenses are above current income. Reset recurring costs before they harden."
                                : "Based on \(employmentSnapshot.monthlyProjectionObservedDays) days of recent expense data (\(employmentSnapshot.spenderBehavior.displayLabel))."
                ),
                weeklySpendingMetric: MetricItemContent(
                    title: "Savings Progress",
                    value: "\(Int((min(employmentSnapshot.emergencyFundProgress, 1.5) * 100).rounded()))%",
                    tone: employmentSnapshot.emergencyFundProgress >= 1 ? .success : (employmentSnapshot.emergencyFundProgress >= 0.5 ? .info : .warning),
                    symbol: "shield.checkered",
                    footnote: "Current balance covers \(snapshot.currentBalance.currencyString) against a \(employmentSnapshot.emergencyFundTarget.currencyString) reserve target."
                )
            )
        }

        return MetricStackContent(
            balanceMetric: MetricItemContent(
                title: "Current Balance",
                value: snapshot.currentBalance.currencyString,
                tone: .info,
                symbol: "wallet.pass.fill",
                footnote: snapshot.currentBalance > 0
                    ? "Use the dashboard balance control whenever your available cash changes outside the app."
                    : "Set the balance first so runway and burn rate are based on your real cash."
            ),
            balanceButtonTitle: snapshot.currentBalance > 0 ? "Adjust Current Balance" : "Enter Current Balance",
            applicationsMetric: MetricItemContent(
                title: "Active Applications",
                value: "\(decisionSnapshot.activeApplicationsCount)",
                tone: .info,
                symbol: "briefcase.fill",
                footnote: "\(decisionSnapshot.interviewCount) interview-stage role\(decisionSnapshot.interviewCount == 1 ? "" : "s") can convert soon."
            ),
            weeklySpendingMetric: MetricItemContent(
                title: "Weekly Spending",
                value: snapshot.weeklySpending.currencyString,
                tone: snapshot.weeklySpending > recommendedDailyBudget * 7 ? .warning : .success,
                symbol: "chart.line.uptrend.xyaxis",
                footnote: weeklySpendingFootnote(
                    snapshot: snapshot,
                    recommendedDailyBudget: recommendedDailyBudget
                )
            )
        )
    }

    private func weeklySpendingFootnote(
        snapshot: ExpenseDashboardSnapshot,
        recommendedDailyBudget: Double
    ) -> String {
        if let anomaly = snapshot.spendingAnomaly {
            return anomaly.message
        }

        if snapshot.spendingTrend == .increasing {
            return "Recent spend is rising on active days, so keep a close eye on large transaction days."
        }

        if snapshot.spendingTrend == .decreasing {
            return "Recent spend is cooling, which helps protect runway if that pattern holds."
        }

        return snapshot.weeklySpending > recommendedDailyBudget * 7
            ? "You’re above the AI-recommended weekly pace."
            : "Spending is inside the target range."
    }
}

@MainActor
private final class EmployedOverviewSectionModel: ObservableObject {
    @Published private(set) var content = EmployedOverviewContent.placeholder

    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    func configureIfNeeded(
        expenseStore: ExpenseStore,
        appModeStore: AppModeStore
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        Publishers.CombineLatest3(
            expenseStore.$dashboardSnapshot.removeDuplicates(),
            expenseStore.$employmentSnapshot.removeDuplicates(),
            appModeStore.$acceptedEmployment.removeDuplicates()
        )
        .map { dashboardSnapshot, employmentSnapshot, acceptedEmployment in
            EmployedOverviewContent(
                employmentTitle: acceptedEmployment.map { "\($0.role) · \($0.companyName)" } ?? "",
                monthlySavingsCapacity: employmentSnapshot.monthlySavingsCapacity,
                monthlyIncome: employmentSnapshot.monthlyIncome,
                monthlyExpenseEstimate: employmentSnapshot.monthlyExpenseEstimate,
                monthlyProjectionObservedDays: employmentSnapshot.monthlyProjectionObservedDays,
                monthlyProjectionConfidence: employmentSnapshot.monthlyProjectionConfidence,
                currentBalance: dashboardSnapshot.currentBalance,
                savingsRate: employmentSnapshot.savingsRate,
                emergencyFundTarget: employmentSnapshot.emergencyFundTarget,
                emergencyFundProgress: employmentSnapshot.emergencyFundProgress,
                runwayIfUnemployedAgainDays: employmentSnapshot.runwayIfUnemployedAgainDays,
                stabilityTone: employmentSnapshot.stabilityTone,
                stabilityLabel: employmentSnapshot.stabilityLabel,
                stabilityMessage: employmentSnapshot.stabilityMessage,
                spendingFrequency: employmentSnapshot.spendingFrequency,
                spenderBehavior: employmentSnapshot.spenderBehavior
            )
        }
        .removeDuplicates()
        .sink { [weak self] in
            self?.content = $0
        }
        .store(in: &cancellables)
    }
}

@MainActor
private final class SmartAlertsSectionModel: ObservableObject {
    @Published private(set) var content = SmartAlertsContent.empty

    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    func configureIfNeeded(aiService: AIInsightService) {
        guard !isConfigured else { return }
        isConfigured = true

        Publishers.CombineLatest(
            Publishers.CombineLatest(
                aiService.$spendingAlerts.removeDuplicates(),
                aiService.$budgetRecommendations.removeDuplicates()
            ),
            aiService.$isRefreshingExpenseInsights.removeDuplicates()
        )
        .map { payload, isRefreshing in
            SmartAlertsContent(
                spendingAlerts: payload.0,
                budgetRecommendations: payload.1,
                isRefreshing: isRefreshing
            )
        }
        .removeDuplicates()
        .sink { [weak self] in
            self?.content = $0
        }
        .store(in: &cancellables)
    }
}

@MainActor
private final class DecisionSignalsSectionModel: ObservableObject {
    @Published private(set) var content = DecisionSignalsContent.empty

    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    func configureIfNeeded(insightsStore: InsightsStore) {
        guard !isConfigured else { return }
        isConfigured = true

        Publishers.CombineLatest(
            insightsStore.$insights.removeDuplicates(),
            insightsStore.$isRefreshing.removeDuplicates()
        )
            .map { insights, isRefreshing in
                DecisionSignalsContent(insights: insights, isRefreshing: isRefreshing)
            }
            .sink { [weak self] in
                self?.content = $0
            }
            .store(in: &cancellables)
    }
}

private struct CurrentBalanceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentBalance: Double
    let onSave: (Double) -> Void

    @State private var amountText: String

    init(currentBalance: Double, onSave: @escaping (Double) -> Void) {
        self.currentBalance = currentBalance
        self.onSave = onSave
        _amountText = State(initialValue: currentBalance > 0 ? String(format: "%.2f", currentBalance) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Available cash") {
                    TextField("Current balance", text: $amountText)
                        .keyboardType(.decimalPad)

                    Text("Enter the cash you have available right now. Career Fuel will keep subtracting logged expenses from this amount.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .navigationTitle("Current Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount = Double(amountText), amount >= 0 else { return }
                        onSave(amount)
                        dismiss()
                    }
                    .disabled((Double(amountText) ?? -1) < 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct MonthlyIncomeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let monthlyIncome: Double
    let onSave: (Double) -> Void

    @State private var amountText: String

    init(monthlyIncome: Double, onSave: @escaping (Double) -> Void) {
        self.monthlyIncome = monthlyIncome
        self.onSave = onSave
        _amountText = State(initialValue: monthlyIncome > 0 ? String(format: "%.2f", monthlyIncome) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Take-home pay") {
                    TextField("Monthly income", text: $amountText)
                        .keyboardType(.decimalPad)

                    Text("Use your monthly take-home pay so employed mode can compare earnings against expenses, savings progress, and recovery runway.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .navigationTitle("Monthly Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount = Double(amountText), amount >= 0 else { return }
                        onSave(amount)
                        dismiss()
                    }
                    .disabled((Double(amountText) ?? -1) < 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct BurnTrendView: View, Equatable {
    let points: [DailyExpensePoint]

    private var maxAmount: Double {
        max(points.map(\.amount).max() ?? 1, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(points) { point in
                VStack(spacing: 8) {
                    Text(point.amount.compactCurrencyString)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppPalette.primary, AppPalette.primary.opacity(0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(24, (point.amount / maxAmount) * 118))

                    Text(point.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
