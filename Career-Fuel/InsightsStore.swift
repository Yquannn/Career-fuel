import Combine
import Foundation

@MainActor
final class InsightsStore: ObservableObject {
    @Published private(set) var insights: [DashboardInsight] = []
    @Published private(set) var runwayTone: StatusTone = .warning
    @Published private(set) var runwayLabel = "Warning"
    @Published private(set) var runwayMessage = ""
    @Published private(set) var isRefreshing = false

    private(set) var refreshComputationCount = 0

    private let jobStore: JobApplicationStore
    private let expenseStore: ExpenseStore
    private let appModeStore: AppModeStore
    private let aiService: AIInsightService
    private let cloudSyncManager: CloudSyncManager
    private let debounceInterval: RunLoop.SchedulerTimeType.Stride
    private var cancellables = Set<AnyCancellable>()
    private var lastComputedInput: RefreshInput?
    private var refreshCache = ComputationCache<RefreshInput, RefreshOutput>(capacity: 12)

    init(
        jobStore: JobApplicationStore,
        expenseStore: ExpenseStore,
        appModeStore: AppModeStore,
        aiService: AIInsightService,
        cloudSyncManager: CloudSyncManager,
        debounceInterval: RunLoop.SchedulerTimeType.Stride = .milliseconds(400)
    ) {
        self.jobStore = jobStore
        self.expenseStore = expenseStore
        self.appModeStore = appModeStore
        self.aiService = aiService
        self.cloudSyncManager = cloudSyncManager
        self.debounceInterval = debounceInterval

        Publishers.CombineLatest(
            Publishers.CombineLatest4(
                expenseStore.$insightSnapshot.removeDuplicates(),
                jobStore.$insightSnapshot.removeDuplicates(),
                expenseStore.$employmentSnapshot.removeDuplicates(),
                aiPublisher()
            ),
            Publishers.CombineLatest(
                cloudPublisher(),
                Publishers.CombineLatest(
                    appModeStore.$mode.removeDuplicates(),
                    appModeStore.$acceptedEmployment.removeDuplicates()
                )
            )
        )
        .map { primaryState, secondaryState in
            RefreshInput(
                expenseSnapshot: primaryState.0,
                jobSnapshot: primaryState.1,
                employmentSnapshot: primaryState.2,
                aiState: primaryState.3,
                cloudState: secondaryState.0,
                appMode: secondaryState.1.0,
                acceptedEmployment: secondaryState.1.1
            )
        }
        .removeDuplicates()
        .handleEvents(receiveOutput: { [weak self] input in
            guard let self, input != self.lastComputedInput else { return }
            if !self.isRefreshing {
                self.isRefreshing = true
            }
        })
        .debounce(for: debounceInterval, scheduler: RunLoop.main)
        .sink { [weak self] input in
            self?.refresh(using: input)
        }
        .store(in: &cancellables)

        refresh(force: true)
    }

    func refresh() {
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        refresh(using: currentInput(), force: force)
    }

    private func refresh(
        using input: RefreshInput,
        force: Bool = false
    ) {
        guard force || input != lastComputedInput else { return }
        lastComputedInput = input
        let output: RefreshOutput
        if !force, let cached = refreshCache.value(for: input) {
            output = cached
        } else {
            refreshComputationCount += 1
            let computed = buildRefreshOutput(using: input)
            refreshCache.insert(computed, for: input)
            output = computed
        }

        apply(output: output)
    }

    private func currentInput() -> RefreshInput {
        RefreshInput(
            expenseSnapshot: expenseStore.insightSnapshot,
            jobSnapshot: jobStore.insightSnapshot,
            employmentSnapshot: expenseStore.employmentSnapshot,
            aiState: AIRefreshState(
                topAlert: aiService.spendingAlerts.first.map {
                    DashboardAlertSummary(
                        id: $0.id,
                        title: $0.title,
                        message: $0.message,
                        tone: $0.tone,
                        symbol: $0.symbol
                    )
                },
                topBudget: aiService.budgetRecommendations.first.map {
                    DashboardBudgetSummary(
                        category: $0.category,
                        weeklyLimit: $0.weeklyLimit,
                        rationale: $0.rationale
                    )
                }
            ),
            cloudState: CloudRefreshState(
                isCloudSyncEnabled: cloudSyncManager.isCloudSyncEnabled,
                hasPendingChanges: cloudSyncManager.hasPendingChanges,
                syncMessage: cloudSyncManager.syncMessage,
                statusLabel: cloudSyncManager.statusLabel,
                statusSymbol: cloudSyncManager.statusSymbol
            ),
            appMode: appModeStore.mode,
            acceptedEmployment: appModeStore.acceptedEmployment
        )
    }

    private func aiPublisher() -> AnyPublisher<AIRefreshState, Never> {
        Publishers.CombineLatest(
            aiService.$spendingAlerts.map(\.first),
            aiService.$budgetRecommendations.map(\.first)
        )
        .map { topAlert, topBudget in
            AIRefreshState(
                topAlert: topAlert.map {
                    DashboardAlertSummary(
                        id: $0.id,
                        title: $0.title,
                        message: $0.message,
                        tone: $0.tone,
                        symbol: $0.symbol
                    )
                },
                topBudget: topBudget.map {
                    DashboardBudgetSummary(
                        category: $0.category,
                        weeklyLimit: $0.weeklyLimit,
                        rationale: $0.rationale
                    )
                }
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    private func cloudPublisher() -> AnyPublisher<CloudRefreshState, Never> {
        Publishers.CombineLatest4(
            cloudSyncManager.$isCloudSyncEnabled,
            cloudSyncManager.$isSyncing,
            cloudSyncManager.$hasPendingChanges,
            Publishers.CombineLatest(
                cloudSyncManager.$lastSyncAt,
                cloudSyncManager.$syncMessage
            )
        )
        .map { [self] isCloudSyncEnabled, isSyncing, hasPendingChanges, trailingState in
            CloudRefreshState(
                isCloudSyncEnabled: isCloudSyncEnabled,
                hasPendingChanges: hasPendingChanges,
                syncMessage: trailingState.1,
                statusLabel: self.statusLabel(
                    isCloudSyncEnabled: isCloudSyncEnabled,
                    isSyncing: isSyncing,
                    hasPendingChanges: hasPendingChanges,
                    lastSyncAt: trailingState.0,
                    isCloudSyncAvailable: self.cloudSyncManager.isCloudSyncAvailable
                ),
                statusSymbol: self.statusSymbol(
                    isCloudSyncEnabled: isCloudSyncEnabled,
                    isSyncing: isSyncing,
                    hasPendingChanges: hasPendingChanges,
                    isCloudSyncAvailable: self.cloudSyncManager.isCloudSyncAvailable
                )
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    private func statusLabel(
        isCloudSyncEnabled: Bool,
        isSyncing: Bool,
        hasPendingChanges: Bool,
        lastSyncAt: Date?,
        isCloudSyncAvailable: Bool
    ) -> String {
        if !isCloudSyncAvailable {
            return "Unavailable"
        }
        if !isCloudSyncEnabled {
            return "Cloud Off"
        }
        if isSyncing {
            return "Syncing"
        }
        if hasPendingChanges {
            return "Pending"
        }
        if lastSyncAt != nil {
            return "Synced"
        }
        return "Ready"
    }

    private func statusSymbol(
        isCloudSyncEnabled: Bool,
        isSyncing: Bool,
        hasPendingChanges: Bool,
        isCloudSyncAvailable: Bool
    ) -> String {
        if !isCloudSyncAvailable {
            return "icloud.slash"
        }
        if !isCloudSyncEnabled {
            return "icloud.slash"
        }
        if isSyncing {
            return "arrow.triangle.2.circlepath.icloud"
        }
        if hasPendingChanges {
            return "icloud.and.arrow.up"
        }
        return "icloud"
    }

    private func buildRefreshOutput(using input: RefreshInput) -> RefreshOutput {
        switch input.appMode {
        case .jobSearch:
            return buildJobSearchOutput(using: input)
        case .employed:
            return buildEmployedOutput(using: input)
        }
    }

    private func buildJobSearchOutput(using input: RefreshInput) -> RefreshOutput {
        let expenseSnapshot = input.expenseSnapshot
        let jobSnapshot = input.jobSnapshot
        let topAlert = input.aiState.topAlert
        let topBudget = input.aiState.topBudget

        let runwayState: RunwayPresentation
        switch expenseSnapshot.runwayState {
        case .setup:
            runwayState = RunwayPresentation(
                tone: .warning,
                label: "Setup",
                message: "Set your current balance first, then log expenses so the runway forecast reflects real cash pressure."
            )
        case .critical:
            runwayState = RunwayPresentation(
                tone: .danger,
                label: "Critical",
                message: trendAwareRunwayMessage(
                    base: "You’re in the critical zone. Protect essentials and focus on the roles most likely to convert soon.",
                    trend: expenseSnapshot.spendingTrend
                )
            )
        case .warning:
            runwayState = RunwayPresentation(
                tone: .warning,
                label: "Warning",
                message: trendAwareRunwayMessage(
                    base: "You’re spending faster than expected. A tighter week can buy back useful runway.",
                    trend: expenseSnapshot.spendingTrend
                )
            )
        case .safe:
            runwayState = RunwayPresentation(
                tone: .success,
                label: "Safe",
                message: trendAwareRunwayMessage(
                    base: "Your runway is controlled. Stay selective, but keep the pipeline moving.",
                    trend: expenseSnapshot.spendingTrend
                )
            )
        }

        var nextInsights: [DashboardInsight] = []

        switch expenseSnapshot.runwayState {
        case .setup:
            nextInsights.append(
                DashboardInsight(
                    id: "runway-setup",
                    title: "Set your current balance",
                    message: "Runway accuracy depends on your real available cash. Add that first, then log expenses normally.",
                    tone: .warning,
                    symbol: "wallet.pass.fill",
                    priority: "Setup"
                )
            )
        case .critical:
            nextInsights.append(
                DashboardInsight(
                    id: "runway-critical",
                    title: "Protect the next 72 hours",
                    message: "Freeze non-essential spending now. Small leaks matter when runway is this tight.",
                    tone: .danger,
                    symbol: "exclamationmark.triangle.fill",
                    priority: "Critical"
                )
            )
        case .warning:
            nextInsights.append(
                DashboardInsight(
                    id: "runway-warning",
                    title: "Trim spend before it gets critical",
                    message: "You’re spending faster than expected. One disciplined week can buy back useful time.",
                    tone: .warning,
                    symbol: "flame.fill",
                    priority: "Urgent"
                )
            )
        case .safe:
            nextInsights.append(
                DashboardInsight(
                    id: "runway-safe",
                    title: "Runway is steady",
                    message: "Cash pressure is manageable. Keep applications and interview prep consistent.",
                    tone: .success,
                    symbol: "checkmark.seal.fill",
                    priority: "Stable"
                )
            )
        }

        if let anomaly = expenseSnapshot.spendingAnomaly {
            nextInsights.append(
                DashboardInsight(
                    id: "spending-anomaly-\(anomaly.date.timeIntervalSince1970)",
                    title: anomaly.title,
                    message: anomaly.message,
                    tone: anomaly.tone,
                    symbol: "bolt.trianglebadge.exclamationmark.fill",
                    priority: "Alert"
                )
            )
        }

        if let trendInsight = trendInsight(for: expenseSnapshot.spendingTrend, mode: .jobSearch) {
            nextInsights.append(trendInsight)
        }

        if jobSnapshot.jobsNeeded > 0 {
            nextInsights.append(
                DashboardInsight(
                    id: "pipeline",
                    title: "Apply to \(jobSnapshot.jobsNeeded) more jobs this week",
                    message: "You need more live opportunities to offset slow recruiter response times.",
                    tone: .info,
                    symbol: "briefcase.fill",
                    priority: "Pipeline"
                )
            )
        }

        if let topAlert {
            nextInsights.append(
                DashboardInsight(
                    id: "ai-\(topAlert.id)",
                    title: topAlert.title,
                    message: topAlert.message,
                    tone: topAlert.tone,
                    symbol: topAlert.symbol,
                    priority: "AI"
                )
            )
        }

        if let topBudget {
            nextInsights.append(
                DashboardInsight(
                    id: "budget-\(topBudget.category.rawValue)",
                    title: "\(topBudget.category.title) budget target",
                    message: "Keep this category near \(topBudget.weeklyLimit.currencyString)/week. \(topBudget.rationale)",
                    tone: .info,
                    symbol: "target",
                    priority: "Budget"
                )
            )
        }

        if input.cloudState.isCloudSyncEnabled {
            nextInsights.append(
                DashboardInsight(
                    id: "cloud-sync",
                    title: input.cloudState.statusLabel,
                    message: input.cloudState.syncMessage,
                    tone: input.cloudState.hasPendingChanges ? .warning : .info,
                    symbol: input.cloudState.statusSymbol,
                    priority: "Cloud"
                )
            )
        }

        return RefreshOutput(
            runwayState: runwayState,
            insights: Array(nextInsights.prefix(5))
        )
    }

    private func buildEmployedOutput(using input: RefreshInput) -> RefreshOutput {
        let employmentSnapshot = input.employmentSnapshot
        let acceptedEmployment = input.acceptedEmployment

        let stabilityState = RunwayPresentation(
            tone: employmentSnapshot.stabilityTone,
            label: employmentSnapshot.stabilityLabel,
            message: employmentSnapshot.stabilityMessage
        )

        var nextInsights: [DashboardInsight] = []

        if employmentSnapshot.monthlyIncome <= 0 {
            nextInsights.append(
                DashboardInsight(
                    id: "employment-income",
                    title: "Set your monthly income",
                    message: "Employment mode works best when it can compare real take-home pay against spending and savings progress.",
                    tone: .warning,
                    symbol: "banknote.fill",
                    priority: "Setup"
                )
            )
        } else if employmentSnapshot.monthlyProjectionConfidence == .insufficient {
            nextInsights.append(
                DashboardInsight(
                    id: "employment-expense-data",
                    title: "Track more expenses first",
                    message: "Monthly stability planning needs real expense history. Log a few days of transactions before trusting the monthly projection.",
                    tone: .warning,
                    symbol: "creditcard.fill",
                    priority: "Setup"
                )
            )
        } else {
            if employmentSnapshot.monthlySavingsCapacity < 0 {
                nextInsights.append(
                    DashboardInsight(
                        id: "employment-income-vs-expenses",
                        title: "Income is below monthly expenses",
                        message: "You’re short by about \((-employmentSnapshot.monthlySavingsCapacity).currencyString) each month. Reset spending before the new salary disappears into recurring costs.",
                        tone: .danger,
                        symbol: "arrow.down.circle.fill",
                        priority: "Critical"
                    )
                )
            } else {
                nextInsights.append(
                    DashboardInsight(
                        id: "employment-save-rate",
                        title: "Save at least 20% of income",
                        message: employedSavingsMessage(
                            savingsRate: employmentSnapshot.savingsRate,
                            monthlySavingsCapacity: employmentSnapshot.monthlySavingsCapacity
                        ),
                        tone: employmentSnapshot.savingsRate >= 0.2 ? .success : .info,
                        symbol: "percent",
                        priority: "Savings"
                    )
                )
            }

            if employmentSnapshot.emergencyFundProgress < 1 {
                nextInsights.append(
                    DashboardInsight(
                        id: "employment-emergency-fund",
                        title: "Rebuild your emergency fund",
                        message: "You’ve rebuilt \(Int((min(employmentSnapshot.emergencyFundProgress, 1.5) * 100).rounded()))% of a three-month reserve. Keep current balance moving toward \(employmentSnapshot.emergencyFundTarget.currencyString).",
                        tone: employmentSnapshot.emergencyFundProgress < 0.5 ? .warning : .info,
                        symbol: "shield.checkered",
                        priority: "Reserve"
                    )
                )
            }

            if employmentSnapshot.runwayIfUnemployedAgainDays < 90 {
                nextInsights.append(
                    DashboardInsight(
                        id: "employment-runway",
                        title: "Recreate unemployment runway",
                        message: "At your current spending pace, today’s cash would cover about \(employmentSnapshot.runwayIfUnemployedAgainDays) days. Push that toward 90 days so the next transition is not urgent.",
                        tone: employmentSnapshot.runwayIfUnemployedAgainDays < 60 ? .warning : .info,
                        symbol: "calendar.badge.exclamationmark",
                        priority: "Stability"
                    )
                )
            }
        }

        if let acceptedEmployment {
            nextInsights.append(
                DashboardInsight(
                    id: "employment-confirmed-\(acceptedEmployment.applicationID)",
                    title: "Protect the transition into \(acceptedEmployment.companyName)",
                    message: "You accepted \(acceptedEmployment.role). Hold the line on spending until your first few pay cycles feel predictable.",
                    tone: .success,
                    symbol: "checkmark.seal.fill",
                    priority: "Transition"
                )
            )
        }

        if let anomaly = input.expenseSnapshot.spendingAnomaly {
            nextInsights.append(
                DashboardInsight(
                    id: "employment-spending-anomaly-\(anomaly.date.timeIntervalSince1970)",
                    title: anomaly.title,
                    message: anomaly.message,
                    tone: anomaly.tone,
                    symbol: "bolt.trianglebadge.exclamationmark.fill",
                    priority: "Alert"
                )
            )
        }

        if let trendInsight = trendInsight(for: input.expenseSnapshot.spendingTrend, mode: .employed) {
            nextInsights.append(trendInsight)
        }

        if let topAlert = input.aiState.topAlert {
            nextInsights.append(
                DashboardInsight(
                    id: "employment-overspending-\(topAlert.id)",
                    title: "Avoid overspending",
                    message: topAlert.message,
                    tone: topAlert.tone,
                    symbol: topAlert.symbol,
                    priority: "Spend"
                )
            )
        } else if let topBudget = input.aiState.topBudget {
            nextInsights.append(
                DashboardInsight(
                    id: "employment-budget-\(topBudget.category.rawValue)",
                    title: "Keep \(topBudget.category.title.lowercased()) disciplined",
                    message: "Aim to keep this category near \(topBudget.weeklyLimit.currencyString)/week while your new income stabilizes. \(topBudget.rationale)",
                    tone: .info,
                    symbol: "target",
                    priority: "Budget"
                )
            )
        }

        if input.cloudState.isCloudSyncEnabled {
            nextInsights.append(
                DashboardInsight(
                    id: "cloud-sync",
                    title: input.cloudState.statusLabel,
                    message: input.cloudState.syncMessage,
                    tone: input.cloudState.hasPendingChanges ? .warning : .info,
                    symbol: input.cloudState.statusSymbol,
                    priority: "Cloud"
                )
            )
        }

        return RefreshOutput(
            runwayState: stabilityState,
            insights: Array(nextInsights.prefix(5))
        )
    }

    private func employedSavingsMessage(
        savingsRate: Double,
        monthlySavingsCapacity: Double
    ) -> String {
        if savingsRate >= 0.2 {
            return "You’re currently preserving about \(Int((savingsRate * 100).rounded()))% of income, or \(monthlySavingsCapacity.currencyString) per month. Keep that habit while the job is still new."
        }

        return "You’re only holding onto about \(Int((max(savingsRate, 0) * 100).rounded()))% of income right now. Push monthly savings closer to 20% while your salary is still fresh."
    }

    private func trendAwareRunwayMessage(
        base: String,
        trend: SpendingTrend
    ) -> String {
        switch trend {
        case .increasing:
            return "\(base) Recent spend is trending up, so the predicted burn rate is carrying a safety premium."
        case .decreasing:
            return "\(base) Recent spend is cooling, so the forecast is giving some runway back."
        case .stable:
            return base
        }
    }

    private func trendInsight(
        for trend: SpendingTrend,
        mode: AppMode
    ) -> DashboardInsight? {
        switch (mode, trend) {
        case (.jobSearch, .increasing):
            return DashboardInsight(
                id: "trend-job-search-increasing",
                title: "Spending trend is rising",
                message: "The last 3 days are running hotter than your 7- and 30-day pace. The app is predicting burn upward to avoid overstating runway.",
                tone: .warning,
                symbol: trend.symbol,
                priority: "Trend"
            )
        case (.jobSearch, .decreasing):
            return DashboardInsight(
                id: "trend-job-search-decreasing",
                title: "Spending trend is cooling",
                message: "Recent spending has eased versus the last week and month. Preserve that discipline and let the recovered runway compound.",
                tone: .success,
                symbol: trend.symbol,
                priority: "Trend"
            )
        case (.employed, .increasing):
            return DashboardInsight(
                id: "trend-employed-increasing",
                title: "Avoid lifestyle creep",
                message: "Recent spending is rising faster than your recent baseline. Protect your new income margin before higher costs become the default.",
                tone: .warning,
                symbol: trend.symbol,
                priority: "Trend"
            )
        case (.employed, .decreasing):
            return DashboardInsight(
                id: "trend-employed-decreasing",
                title: "Your spend trend is improving",
                message: "Recent spending is easing against the last week and month. Use that margin to rebuild savings instead of absorbing it elsewhere.",
                tone: .success,
                symbol: trend.symbol,
                priority: "Trend"
            )
        case (_, .stable):
            return nil
        }
    }

    private func apply(output: RefreshOutput) {
        if runwayTone != output.runwayState.tone {
            runwayTone = output.runwayState.tone
        }

        if runwayLabel != output.runwayState.label {
            runwayLabel = output.runwayState.label
        }

        if runwayMessage != output.runwayState.message {
            runwayMessage = output.runwayState.message
        }

        if insights != output.insights {
            insights = output.insights
        }

        if isRefreshing {
            isRefreshing = false
        }
    }
}

private extension InsightsStore {
    struct DashboardAlertSummary: Hashable {
        let id: String
        let title: String
        let message: String
        let tone: StatusTone
        let symbol: String
    }

    struct DashboardBudgetSummary: Hashable {
        let category: ExpenseCategory
        let weeklyLimit: Double
        let rationale: String
    }

    struct AIRefreshState: Hashable {
        let topAlert: DashboardAlertSummary?
        let topBudget: DashboardBudgetSummary?
    }

    struct CloudRefreshState: Hashable {
        let isCloudSyncEnabled: Bool
        let hasPendingChanges: Bool
        let syncMessage: String
        let statusLabel: String
        let statusSymbol: String
    }

    struct RefreshInput: Hashable {
        let expenseSnapshot: ExpenseInsightSnapshot
        let jobSnapshot: JobInsightSnapshot
        let employmentSnapshot: EmploymentFinancialSnapshot
        let aiState: AIRefreshState
        let cloudState: CloudRefreshState
        let appMode: AppMode
        let acceptedEmployment: AcceptedEmployment?
    }

    struct RunwayPresentation {
        let tone: StatusTone
        let label: String
        let message: String
    }

    struct RefreshOutput {
        let runwayState: RunwayPresentation
        let insights: [DashboardInsight]
    }
}
