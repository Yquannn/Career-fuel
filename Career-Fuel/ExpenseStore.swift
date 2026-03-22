import Combine
import CryptoKit
import Foundation

@MainActor
final class ExpenseStore: ObservableObject {
    @Published private(set) var expenses: [Expense]
    @Published private(set) var recurringPlans: [RecurringExpensePlan]
    @Published private(set) var dashboardSnapshot: ExpenseDashboardSnapshot
    @Published private(set) var insightSnapshot: ExpenseInsightSnapshot
    @Published private(set) var analyticsSummary: ExpenseAnalyticsSummary
    @Published private(set) var employmentSnapshot: EmploymentFinancialSnapshot

    private(set) var startingBalance: Double
    private(set) var monthlyIncome: Double

    private let persistence: PersistenceController
    private let defaults: UserDefaults
    private let storageKey = "careerfuel.expensestore.snapshot.v3"
    private let legacyStorageKey = "careerfuel.expensestore.snapshot"

    private var deletedExpenseTombstones: [DeletionTombstone]
    private var snapshotUpdatedAt: Date

    init(
        persistence: PersistenceController,
        defaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.defaults = defaults
        expenses = []
        recurringPlans = []
        dashboardSnapshot = .empty
        insightSnapshot = .empty
        analyticsSummary = .empty
        employmentSnapshot = .empty
        startingBalance = 0
        monthlyIncome = 0
        deletedExpenseTombstones = []
        snapshotUpdatedAt = Date()

        if
            let snapshot = persistence.load(ExpenseStoreSnapshot.self, forKey: storageKey),
            !Self.looksLikeLegacySeedData(snapshot)
        {
            startingBalance = snapshot.startingBalance
            monthlyIncome = snapshot.monthlyIncome
            expenses = snapshot.expenses
            recurringPlans = snapshot.recurringPlans
            deletedExpenseTombstones = snapshot.deletedExpenseTombstones
            snapshotUpdatedAt = snapshot.updatedAt
        } else if
            let migrated = Self.migrateLegacySnapshot(from: defaults, storageKey: legacyStorageKey),
            !Self.looksLikeLegacySeedData(migrated)
        {
            startingBalance = migrated.startingBalance
            monthlyIncome = migrated.monthlyIncome
            expenses = migrated.expenses
            recurringPlans = migrated.recurringPlans
            deletedExpenseTombstones = migrated.deletedExpenseTombstones
            snapshotUpdatedAt = migrated.updatedAt
            persist()
        } else {
            startingBalance = 0
            monthlyIncome = 0
            expenses = []
            recurringPlans = []
            deletedExpenseTombstones = []
            snapshotUpdatedAt = Date()
            persist()
        }

        if materializeRecurringExpenses() {
            snapshotUpdatedAt = Date()
            persist()
        }
        rebuildDerivedState()
    }

    var totalSpent: Double {
        dashboardSnapshot.totalSpent
    }

    var currentBalance: Double {
        dashboardSnapshot.currentBalance
    }

    var weeklySpending: Double {
        dashboardSnapshot.weeklySpending
    }

    var dailyBurnRate: Double {
        dashboardSnapshot.dailyBurnRate
    }

    var weightedDailyBurnRate: Double {
        dashboardSnapshot.weightedDailyBurnRate
    }

    var spendingTrend: SpendingTrend {
        dashboardSnapshot.spendingTrend
    }

    var daysLeft: Int {
        dashboardSnapshot.daysLeft
    }

    var projectedZeroDate: Date {
        dashboardSnapshot.projectedZeroDate
    }

    var monthlyExpenseEstimate: Double {
        employmentSnapshot.monthlyExpenseEstimate
    }

    var monthlySavingsCapacity: Double {
        employmentSnapshot.monthlySavingsCapacity
    }

    var runwayIfUnemployedAgainDays: Int {
        employmentSnapshot.runwayIfUnemployedAgainDays
    }

    var sevenDayTrend: [DailyExpensePoint] {
        dashboardSnapshot.sevenDayTrend
    }

    var activeRecurringPlans: [RecurringExpensePlan] {
        recurringPlans
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.frequency == rhs.frequency {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    @discardableResult
    func add(_ draft: ExpenseDraft, recurringFrequency: RecurringExpenseFrequency? = nil) -> Bool {
        guard validationIssue(for: draft) == nil else { return false }

        let normalizedLabel = normalized(draft.label, fallback: draft.category.title)
        let normalizedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTags = normalizedTags(draft.tags)

        if let recurringFrequency {
            let plan = RecurringExpensePlan(
                category: draft.category,
                label: normalizedLabel,
                amount: draft.amount,
                startDate: Calendar.current.startOfDay(for: draft.date),
                notes: normalizedNotes,
                tags: normalizedTags,
                frequency: recurringFrequency
            )

            recurringPlans.append(plan)
            recurringPlans.sort { $0.updatedAt > $1.updatedAt }
            materializeRecurringExpenses()
            touchAndPersist()
            return true
        }

        let expense = Expense(
            category: draft.category,
            label: normalizedLabel,
            amount: draft.amount,
            date: draft.date,
            notes: normalizedNotes,
            tags: normalizedTags
        )

        expenses.insert(expense, at: 0)
        deletedExpenseTombstones.removeAll { $0.id == expense.id }
        touchAndPersist()
        return true
    }

    @discardableResult
    func edit(id: UUID, with draft: ExpenseDraft) -> Bool {
        guard validationIssue(for: draft) == nil else { return false }
        guard let index = expenses.firstIndex(where: { $0.id == id }) else { return false }

        expenses[index].category = draft.category
        expenses[index].label = normalized(draft.label, fallback: draft.category.title)
        expenses[index].amount = draft.amount
        expenses[index].date = draft.date
        expenses[index].notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        expenses[index].tags = normalizedTags(draft.tags)
        expenses[index].updatedAt = Date()
        touchAndPersist()
        return true
    }

    func delete(id: UUID) {
        expenses.removeAll { $0.id == id }
        upsertTombstone(id: id)
        touchAndPersist()
    }

    func updateStartingBalance(_ amount: Double) {
        startingBalance = amount
        touchAndPersist()
    }

    func setCurrentBalance(_ amount: Double) {
        startingBalance = max(amount, 0) + totalSpent
        touchAndPersist()
    }

    func updateMonthlyIncome(_ amount: Double) {
        monthlyIncome = max(amount, 0)
        touchAndPersist()
    }

    func deactivateRecurringPlan(id: UUID) {
        guard let index = recurringPlans.firstIndex(where: { $0.id == id }) else { return }
        recurringPlans[index].isActive = false
        recurringPlans[index].updatedAt = Date()
        touchAndPersist()
    }

    func nextOccurrenceDate(for plan: RecurringExpensePlan, relativeTo referenceDate: Date = Date()) -> Date? {
        guard plan.isActive else { return nil }

        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: referenceDate)

        if let lastGeneratedDate = plan.lastGeneratedDate {
            if let generated = nextDate(after: lastGeneratedDate, frequency: plan.frequency) {
                return generated
            }
        }

        let startDate = calendar.startOfDay(for: plan.startDate)
        if startDate > referenceDay {
            return startDate
        }

        if let mostRecent = mostRecentOccurrence(onOrBefore: referenceDay, for: plan) {
            return nextDate(after: mostRecent, frequency: plan.frequency)
        }

        return startDate
    }

    func syncRecurringExpenses(referenceDate: Date = Date()) {
        let didGenerate = materializeRecurringExpenses(referenceDate: referenceDate)
        if didGenerate {
            touchAndPersist()
        } else {
            rebuildDerivedState(referenceDate: referenceDate)
        }
    }

    func resetLocalData() {
        startingBalance = 0
        monthlyIncome = 0
        expenses = []
        recurringPlans = []
        deletedExpenseTombstones = []
        snapshotUpdatedAt = Date()
        rebuildDerivedState()
        persistence.removeValue(forKey: storageKey)
        defaults.removeObject(forKey: legacyStorageKey)
    }

    func spendTotal(inLastDays days: Int, relativeTo date: Date = Date()) -> Double {
        if days == 7, Calendar.current.isDate(date, inSameDayAs: Date()) {
            return dashboardSnapshot.weeklySpending
        }

        return computeSpendTotal(inLastDays: days, relativeTo: date)
    }

    func weeklySpendHistory(weeks: Int = 8, relativeTo date: Date = Date()) -> [WeeklySpendPoint] {
        if weeks == 8, Calendar.current.isDate(date, inSameDayAs: Date()) {
            return analyticsSummary.weeklySpendHistory
        }

        return computeWeeklySpendHistory(weeks: weeks, relativeTo: date)
    }

    func monthlySpendHistory(months: Int = 6, relativeTo date: Date = Date()) -> [MonthlySpendPoint] {
        if months == 6, Calendar.current.isDate(date, inSameDayAs: Date()) {
            return analyticsSummary.monthlySpendHistory
        }

        return computeMonthlySpendHistory(months: months, relativeTo: date)
    }

    func spendByCategory(inLastDays days: Int) -> [ExpenseCategory: Double] {
        switch days {
        case 7:
            return analyticsSummary.spendByCategory7Days
        case 28:
            return analyticsSummary.spendByCategory28Days
        default:
            return computeSpendByCategory(inLastDays: days, relativeTo: Date())
        }
    }

    func snapshot() -> ExpenseStoreSnapshot {
        ExpenseStoreSnapshot(
            startingBalance: startingBalance,
            monthlyIncome: monthlyIncome,
            expenses: expenses,
            recurringPlans: recurringPlans,
            deletedExpenseTombstones: deletedExpenseTombstones,
            updatedAt: snapshotUpdatedAt
        )
    }

    func merge(snapshot remote: ExpenseStoreSnapshot) {
        let merged = mergedSnapshot(with: remote)
        apply(snapshot: merged)
        persist()
    }

    func mergedSnapshot(with remote: ExpenseStoreSnapshot) -> ExpenseStoreSnapshot {
        let local = snapshot()
        let mergedTombstones = mergedTombstones(local.deletedExpenseTombstones, remote.deletedExpenseTombstones)
        let tombstoneIndex = Dictionary(uniqueKeysWithValues: mergedTombstones.map { ($0.id, $0.deletedAt) })
        let mergedByID = Dictionary(grouping: local.expenses + remote.expenses, by: \.id)
            .compactMapValues { candidates in
                candidates.max { lhs, rhs in
                    if lhs.updatedAt == rhs.updatedAt {
                        return lhs.amount < rhs.amount
                    }
                    return lhs.updatedAt < rhs.updatedAt
                }
            }

        let mergedExpenses = mergedByID.values
            .filter { expense in
                guard let deletedAt = tombstoneIndex[expense.id] else { return true }
                return expense.updatedAt > deletedAt
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.date > rhs.date
            }

        let mergedRecurringPlans = Dictionary(grouping: local.recurringPlans + remote.recurringPlans, by: \.id)
            .compactMapValues { candidates in
                candidates.max { lhs, rhs in
                    lhs.updatedAt < rhs.updatedAt
                }
            }
            .values
            .sorted { lhs, rhs in
                if lhs.isActive == rhs.isActive {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.isActive && !rhs.isActive
            }

        let mergedStartingBalance = local.updatedAt >= remote.updatedAt
            ? local.startingBalance
            : remote.startingBalance

        return ExpenseStoreSnapshot(
            startingBalance: mergedStartingBalance,
            monthlyIncome: local.updatedAt >= remote.updatedAt ? local.monthlyIncome : remote.monthlyIncome,
            expenses: mergedExpenses,
            recurringPlans: mergedRecurringPlans,
            deletedExpenseTombstones: mergedTombstones,
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private func apply(snapshot: ExpenseStoreSnapshot) {
        startingBalance = snapshot.startingBalance
        monthlyIncome = snapshot.monthlyIncome
        expenses = snapshot.expenses
        recurringPlans = snapshot.recurringPlans
        deletedExpenseTombstones = snapshot.deletedExpenseTombstones
        snapshotUpdatedAt = snapshot.updatedAt
        materializeRecurringExpenses()
        rebuildDerivedState()
    }

    private func rebuildDerivedState(referenceDate: Date = Date()) {
        let calendar = Calendar.current
        let normalizedReferenceDate = calendar.startOfDay(for: referenceDate)
        let dailySpendLookup = buildDailySpendLookup()
        let adaptiveBurn = computeAdaptiveBurn(
            relativeTo: normalizedReferenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let totalSpent = expenses.reduce(0) { $0 + $1.amount }
        let currentBalance = max(startingBalance - totalSpent, 0)
        let weeklySpending = totalSpend(
            inLastDays: 7,
            relativeTo: normalizedReferenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let dailyBurnRate = adaptiveBurn.predictedDailyBurnRate
        let daysLeft = dailyBurnRate > 0
            ? max(Int((currentBalance / dailyBurnRate).rounded(.down)), 0)
            : 0
        let projectedZeroDate = calendar.date(byAdding: .day, value: daysLeft, to: normalizedReferenceDate) ?? normalizedReferenceDate
        let monthlyProjection = computeMonthlyProjection(
            relativeTo: normalizedReferenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let monthlyExpenseEstimate = monthlyProjection.monthlyExpenseEstimate
        let monthlySavingsCapacity = monthlyIncome - monthlyExpenseEstimate
        let savingsRate = monthlyIncome > 0 ? monthlySavingsCapacity / monthlyIncome : 0
        let emergencyFundTarget = max(monthlyExpenseEstimate * 3, 1)
        let emergencyFundProgress = currentBalance / emergencyFundTarget
        let runwayIfUnemployedAgainDays = monthlyProjection.dailyProjection > 0
            ? max(Int(currentBalance / monthlyProjection.dailyProjection), 0)
            : 0

        let nextDashboardSnapshot = ExpenseDashboardSnapshot(
            totalSpent: totalSpent,
            currentBalance: currentBalance,
            observedExpenseDays: adaptiveBurn.observedExpenseDays,
            threeDayAverage: adaptiveBurn.threeDayAverage,
            sevenDayAverage: adaptiveBurn.sevenDayAverage,
            thirtyDayAverage: adaptiveBurn.thirtyDayAverage,
            weightedDailyBurnRate: adaptiveBurn.weightedDailyBurnRate,
            weeklySpending: weeklySpending,
            dailyBurnRate: dailyBurnRate,
            burnRateConfidence: adaptiveBurn.confidence,
            spendingTrend: adaptiveBurn.trend,
            spendingAnomaly: adaptiveBurn.anomaly,
            daysLeft: daysLeft,
            projectedZeroDate: projectedZeroDate,
            sevenDayTrend: computeSevenDayTrend(
                relativeTo: normalizedReferenceDate,
                dailySpendLookup: dailySpendLookup
            )
        )

        let nextAnalyticsSummary = ExpenseAnalyticsSummary(
            weeklySpendHistory: computeWeeklySpendHistory(weeks: 8, relativeTo: normalizedReferenceDate),
            monthlySpendHistory: computeMonthlySpendHistory(months: 6, relativeTo: normalizedReferenceDate),
            spendByCategory7Days: computeSpendByCategory(inLastDays: 7, relativeTo: normalizedReferenceDate),
            spendByCategory28Days: computeSpendByCategory(inLastDays: 28, relativeTo: normalizedReferenceDate)
        )
        let nextInsightSnapshot = buildInsightSnapshot(from: nextDashboardSnapshot)
        let nextEmploymentSnapshot = buildEmploymentSnapshot(
            currentBalance: currentBalance,
            monthlyExpenseEstimate: monthlyExpenseEstimate,
            monthlyProjectionObservedDays: monthlyProjection.observedDays,
            monthlyProjectionConfidence: monthlyProjection.confidence,
            monthlySavingsCapacity: monthlySavingsCapacity,
            savingsRate: savingsRate,
            emergencyFundTarget: emergencyFundTarget,
            emergencyFundProgress: emergencyFundProgress,
            runwayIfUnemployedAgainDays: runwayIfUnemployedAgainDays
        )

        if dashboardSnapshot != nextDashboardSnapshot {
            dashboardSnapshot = nextDashboardSnapshot
        }

        if insightSnapshot != nextInsightSnapshot {
            insightSnapshot = nextInsightSnapshot
        }

        if analyticsSummary != nextAnalyticsSummary {
            analyticsSummary = nextAnalyticsSummary
        }

        if employmentSnapshot != nextEmploymentSnapshot {
            employmentSnapshot = nextEmploymentSnapshot
        }
    }

    private func buildInsightSnapshot(from dashboardSnapshot: ExpenseDashboardSnapshot) -> ExpenseInsightSnapshot {
        let runwayState: RunwayInsightState

        if dashboardSnapshot.currentBalance <= 0 || dashboardSnapshot.burnRateConfidence == .insufficient {
            runwayState = .setup
        } else if dashboardSnapshot.daysLeft <= 14 {
            runwayState = .critical
        } else if dashboardSnapshot.daysLeft <= 21 {
            runwayState = .warning
        } else {
            runwayState = .safe
        }

        return ExpenseInsightSnapshot(
            runwayState: runwayState,
            spendingTrend: dashboardSnapshot.spendingTrend,
            spendingAnomaly: dashboardSnapshot.spendingAnomaly
        )
    }

    private func buildEmploymentSnapshot(
        currentBalance: Double,
        monthlyExpenseEstimate: Double,
        monthlyProjectionObservedDays: Int,
        monthlyProjectionConfidence: BurnRateConfidence,
        monthlySavingsCapacity: Double,
        savingsRate: Double,
        emergencyFundTarget: Double,
        emergencyFundProgress: Double,
        runwayIfUnemployedAgainDays: Int
    ) -> EmploymentFinancialSnapshot {
        let stabilityTone: StatusTone
        let stabilityLabel: String
        let stabilityMessage: String
        let normalizedMonthlySavingsCapacity: Double
        let normalizedSavingsRate: Double
        let normalizedEmergencyFundTarget: Double
        let normalizedEmergencyFundProgress: Double
        let normalizedRunwayIfUnemployedAgainDays: Int

        if monthlyIncome <= 0 {
            stabilityTone = .warning
            stabilityLabel = "Income Missing"
            stabilityMessage = "Set your monthly take-home pay so the dashboard can switch from survival runway into stability planning."
            normalizedMonthlySavingsCapacity = 0
            normalizedSavingsRate = 0
            normalizedEmergencyFundTarget = 0
            normalizedEmergencyFundProgress = 0
            normalizedRunwayIfUnemployedAgainDays = 0
        } else if monthlyProjectionConfidence == .insufficient {
            stabilityTone = .warning
            stabilityLabel = "Track Spending"
            stabilityMessage = "Log at least one expense day to start projecting monthly expenses. Five days of data will make the estimate more trustworthy."
            normalizedMonthlySavingsCapacity = 0
            normalizedSavingsRate = 0
            normalizedEmergencyFundTarget = 0
            normalizedEmergencyFundProgress = 0
            normalizedRunwayIfUnemployedAgainDays = 0
        } else if monthlyProjectionConfidence == .low {
            stabilityTone = .warning
            stabilityLabel = "Early Estimate"
            stabilityMessage = "This monthly expense projection is still based on only \(monthlyProjectionObservedDays) expense day\(monthlyProjectionObservedDays == 1 ? "" : "s"). Keep logging to stabilize it."
            normalizedMonthlySavingsCapacity = monthlySavingsCapacity
            normalizedSavingsRate = savingsRate
            normalizedEmergencyFundTarget = emergencyFundTarget
            normalizedEmergencyFundProgress = emergencyFundProgress
            normalizedRunwayIfUnemployedAgainDays = runwayIfUnemployedAgainDays
        } else if monthlySavingsCapacity < 0 {
            stabilityTone = .danger
            stabilityLabel = "Unstable"
            stabilityMessage = "Your current monthly expenses are above income. Tighten spending before lifestyle creep locks in."
            normalizedMonthlySavingsCapacity = monthlySavingsCapacity
            normalizedSavingsRate = savingsRate
            normalizedEmergencyFundTarget = emergencyFundTarget
            normalizedEmergencyFundProgress = emergencyFundProgress
            normalizedRunwayIfUnemployedAgainDays = runwayIfUnemployedAgainDays
        } else if emergencyFundProgress < 0.5 {
            stabilityTone = .warning
            stabilityLabel = "Rebuilding"
            stabilityMessage = "Income covers expenses, but your reserve is still thin. Rebuild the emergency fund before raising spending."
            normalizedMonthlySavingsCapacity = monthlySavingsCapacity
            normalizedSavingsRate = savingsRate
            normalizedEmergencyFundTarget = emergencyFundTarget
            normalizedEmergencyFundProgress = emergencyFundProgress
            normalizedRunwayIfUnemployedAgainDays = runwayIfUnemployedAgainDays
        } else if emergencyFundProgress < 1 {
            stabilityTone = .info
            stabilityLabel = "Improving"
            stabilityMessage = "Income is ahead of spending. Keep saving until your reserve reaches three months of expenses."
            normalizedMonthlySavingsCapacity = monthlySavingsCapacity
            normalizedSavingsRate = savingsRate
            normalizedEmergencyFundTarget = emergencyFundTarget
            normalizedEmergencyFundProgress = emergencyFundProgress
            normalizedRunwayIfUnemployedAgainDays = runwayIfUnemployedAgainDays
        } else {
            stabilityTone = .success
            stabilityLabel = "Stable"
            stabilityMessage = "Income covers spending and your cash buffer can absorb disruption. Stay disciplined and keep the margin."
            normalizedMonthlySavingsCapacity = monthlySavingsCapacity
            normalizedSavingsRate = savingsRate
            normalizedEmergencyFundTarget = emergencyFundTarget
            normalizedEmergencyFundProgress = emergencyFundProgress
            normalizedRunwayIfUnemployedAgainDays = runwayIfUnemployedAgainDays
        }

        return EmploymentFinancialSnapshot(
            monthlyIncome: monthlyIncome,
            monthlyExpenseEstimate: monthlyExpenseEstimate,
            monthlyProjectionObservedDays: monthlyProjectionObservedDays,
            monthlyProjectionConfidence: monthlyProjectionConfidence,
            monthlySavingsCapacity: normalizedMonthlySavingsCapacity,
            savingsRate: normalizedSavingsRate,
            emergencyFundTarget: normalizedEmergencyFundTarget,
            emergencyFundProgress: normalizedEmergencyFundProgress,
            runwayIfUnemployedAgainDays: normalizedRunwayIfUnemployedAgainDays,
            stabilityTone: stabilityTone,
            stabilityLabel: stabilityLabel,
            stabilityMessage: stabilityMessage
        )
    }

    private func computeSpendTotal(inLastDays days: Int, relativeTo date: Date) -> Double {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        return totalSpend(inLastDays: days, relativeTo: normalizedDate, dailySpendLookup: buildDailySpendLookup())
    }

    private func computeSevenDayTrend(
        relativeTo date: Date,
        dailySpendLookup: [Date: Double]? = nil
    ) -> [DailyExpensePoint] {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        let dailySpendLookup = dailySpendLookup ?? buildDailySpendLookup()

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -(6 - offset), to: normalizedDate) else {
                return nil
            }

            return DailyExpensePoint(date: day, amount: dailySpendLookup[day, default: 0])
        }
    }

    private func computeWeeklySpendHistory(weeks: Int, relativeTo date: Date) -> [WeeklySpendPoint] {
        let calendar = Calendar.current
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date

        return (0..<weeks).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1 - offset), to: currentWeekStart) else {
                return nil
            }

            guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else {
                return nil
            }

            let total = expenses
                .filter { interval.contains($0.date) }
                .reduce(0) { $0 + $1.amount }

            return WeeklySpendPoint(weekStart: interval.start, amount: total)
        }
    }

    private func computeMonthlySpendHistory(months: Int, relativeTo date: Date) -> [MonthlySpendPoint] {
        let calendar = Calendar.current
        let currentMonthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date

        return (0..<months).compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: -(months - 1 - offset), to: currentMonthStart) else {
                return nil
            }

            guard let interval = calendar.dateInterval(of: .month, for: monthStart) else {
                return nil
            }

            let total = expenses
                .filter { interval.contains($0.date) }
                .reduce(0) { $0 + $1.amount }

            return MonthlySpendPoint(monthStart: interval.start, amount: total)
        }
    }

    private func computeSpendByCategory(inLastDays days: Int, relativeTo date: Date) -> [ExpenseCategory: Double] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: date) ?? date)

        return Dictionary(grouping: expenses.filter { calendar.startOfDay(for: $0.date) >= start }, by: \.category)
            .mapValues { entries in
                entries.reduce(0) { $0 + $1.amount }
            }
    }

    private func computeAdaptiveBurn(
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> AdaptiveBurnComputation {
        let observedExpenseDays = dailySpendLookup.keys
            .filter { $0 <= referenceDate }
            .count
        let confidence = burnRateConfidence(for: observedExpenseDays)

        guard observedExpenseDays > 0 else {
            return AdaptiveBurnComputation(
                observedExpenseDays: 0,
                confidence: .insufficient,
                threeDayAverage: 0,
                sevenDayAverage: 0,
                thirtyDayAverage: 0,
                weightedDailyBurnRate: 0,
                predictedDailyBurnRate: 0,
                trend: .stable,
                anomaly: nil
            )
        }

        let threeDayAverage = recentSpendingDayAverage(
            spendingDayLimit: 3,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let sevenDayAverage = recentSpendingDayAverage(
            spendingDayLimit: 7,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let thirtyDayAverage = recentSpendingDayAverage(
            spendingDayLimit: 30,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )

        let weightedDailyBurnRate = max(
            (threeDayAverage * 0.5) +
            (sevenDayAverage * 0.3) +
            (thirtyDayAverage * 0.2),
            0
        )
        let trend = observedExpenseDays >= 3
            ? detectSpendingTrend(
                threeDayAverage: threeDayAverage,
                sevenDayAverage: sevenDayAverage,
                thirtyDayAverage: thirtyDayAverage
            )
            : .stable
        let predictedDailyBurnRate = max(weightedDailyBurnRate * trend.predictiveAdjustmentMultiplier, 0)
        let anomaly = detectSpendingAnomaly(
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup,
            sevenDayAverage: sevenDayAverage,
            thirtyDayAverage: thirtyDayAverage,
            predictedDailyBurnRate: predictedDailyBurnRate
        )

        return AdaptiveBurnComputation(
            observedExpenseDays: observedExpenseDays,
            confidence: confidence,
            threeDayAverage: threeDayAverage,
            sevenDayAverage: sevenDayAverage,
            thirtyDayAverage: thirtyDayAverage,
            weightedDailyBurnRate: weightedDailyBurnRate,
            predictedDailyBurnRate: predictedDailyBurnRate,
            trend: trend,
            anomaly: anomaly
        )
    }

    private func detectSpendingTrend(
        threeDayAverage: Double,
        sevenDayAverage: Double,
        thirtyDayAverage: Double
    ) -> SpendingTrend {
        let shortVsMid = relativeChange(current: threeDayAverage, baseline: sevenDayAverage)
        let shortVsLong = relativeChange(current: threeDayAverage, baseline: thirtyDayAverage)

        if shortVsMid >= 0.12 || shortVsLong >= 0.18 {
            return .increasing
        }

        if shortVsMid <= -0.12 && shortVsLong <= -0.08 {
            return .decreasing
        }

        return .stable
    }

    private func detectSpendingAnomaly(
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double],
        sevenDayAverage: Double,
        thirtyDayAverage: Double,
        predictedDailyBurnRate: Double
    ) -> SpendingAnomaly? {
        let recentPoints = dailySpendPoints(
            inLastDays: 3,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let monthlySeries = dailySpendPoints(
            inLastDays: 30,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let dailySeries = monthlySeries.map(\.amount)

        guard dailySpendLookup.count >= 3 else {
            return nil
        }

        guard
            let spike = recentPoints.max(by: { lhs, rhs in
                if lhs.amount == rhs.amount {
                    return lhs.date < rhs.date
                }
                return lhs.amount < rhs.amount
            }),
            spike.amount > 0
        else {
            return nil
        }

        let deviation = standardDeviation(dailySeries)
        let baseline = max(thirtyDayAverage, 1)
        let threshold = max(
            baseline * 2.4,
            max(sevenDayAverage * 1.9, predictedDailyBurnRate * 1.75),
            baseline + max(deviation * 1.8, 250)
        )

        guard spike.amount >= threshold else { return nil }

        let tone: StatusTone = spike.amount >= threshold * 1.3 ? .danger : .warning
        return SpendingAnomaly(
            date: spike.date,
            amount: spike.amount,
            title: "Unusual spending spike",
            message: "A \(spike.amount.currencyString) spend on \(spike.date.formatted(.dateTime.month(.abbreviated).day())) is materially above your recent pace and is compressing runway.",
            tone: tone
        )
    }

    private func buildDailySpendLookup() -> [Date: Double] {
        let calendar = Calendar.current
        return expenses.reduce(into: [Date: Double]()) { partialResult, expense in
            let day = calendar.startOfDay(for: expense.date)
            partialResult[day, default: 0] += expense.amount
        }
    }

    private func totalSpend(
        inLastDays days: Int,
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> Double {
        dailySpendPoints(
            inLastDays: days,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )
        .reduce(0) { $0 + $1.amount }
    }

    private func averageDailySpend(
        inLastDays days: Int,
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> Double {
        totalSpend(
            inLastDays: days,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        ) / Double(max(days, 1))
    }

    private func recentSpendingDayAverage(
        spendingDayLimit: Int,
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> Double {
        let recentPoints = recentSpendingDayPoints(
            limit: spendingDayLimit,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )

        guard !recentPoints.isEmpty else { return 0 }

        let divisor = Double(max(recentPoints.count, 3))
        let total = recentPoints.reduce(0) { $0 + $1.amount }
        return total / divisor
    }

    private func recentSpendingDayPoints(
        limit: Int,
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> [DailyExpensePoint] {
        Array(
            dailySpendLookup
                .filter { $0.key <= referenceDate && $0.value > 0 }
                .map { DailyExpensePoint(date: $0.key, amount: $0.value) }
                .sorted { lhs, rhs in lhs.date > rhs.date }
                .prefix(limit)
        )
    }

    private func computeMonthlyProjection(
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> MonthlyProjectionComputation {
        let recentPoints = calendarDaySpendPoints(
            inLastDays: 30,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )
        let observedPoints = recentPoints.filter { $0.amount > 0 }
        let observedDays = observedPoints.count

        guard observedDays > 0 else {
            return MonthlyProjectionComputation(
                observedDays: 0,
                confidence: .insufficient,
                dailyProjection: 0,
                monthlyExpenseEstimate: 0
            )
        }

        let total = observedPoints.reduce(0) { $0 + $1.amount }
        let dailyProjection = total / Double(observedDays)

        return MonthlyProjectionComputation(
            observedDays: observedDays,
            confidence: monthlyProjectionConfidence(for: observedDays),
            dailyProjection: dailyProjection,
            monthlyExpenseEstimate: dailyProjection * 30
        )
    }

    private func monthlyProjectionConfidence(for observedDays: Int) -> BurnRateConfidence {
        switch observedDays {
        case ..<1:
            return .insufficient
        case 1...4:
            return .low
        case 5...9:
            return .medium
        default:
            return .high
        }
    }

    private func calendarDaySpendPoints(
        inLastDays days: Int,
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> [DailyExpensePoint] {
        dailySpendPoints(
            inLastDays: days,
            relativeTo: referenceDate,
            dailySpendLookup: dailySpendLookup
        )
    }

    private func burnRateConfidence(for observedExpenseDays: Int) -> BurnRateConfidence {
        switch observedExpenseDays {
        case ..<1:
            return .insufficient
        case 1...2:
            return .low
        case 3...6:
            return .medium
        default:
            return .high
        }
    }

    private func dailySpendPoints(
        inLastDays days: Int,
        relativeTo referenceDate: Date,
        dailySpendLookup: [Date: Double]
    ) -> [DailyExpensePoint] {
        let calendar = Calendar.current
        let normalizedReferenceDate = calendar.startOfDay(for: referenceDate)

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: normalizedReferenceDate) else {
                return nil
            }

            return DailyExpensePoint(date: day, amount: dailySpendLookup[day, default: 0])
        }
    }

    private func relativeChange(current: Double, baseline: Double) -> Double {
        let normalizedBaseline = max(baseline, 1)
        return (current - normalizedBaseline) / normalizedBaseline
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { partialResult, value in
            partialResult + pow(value - mean, 2)
        } / Double(values.count)
        return sqrt(variance)
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedTags(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    func validationIssue(for draft: ExpenseDraft) -> ExpenseInputIntegrityIssue? {
        let normalizedText = "\(draft.label) \(draft.notes)"
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        let aggregatedMarkers = [
            "weekly total",
            "week total",
            "monthly total",
            "month total",
            "weekly spending",
            "monthly spending",
            "combined expenses",
            "all expenses",
            "entire week",
            "entire month",
            "whole week",
            "whole month",
            "aggregate"
        ]

        if aggregatedMarkers.contains(where: normalizedText.contains) {
            return .aggregatedSummary
        }

        return nil
    }

    private func upsertTombstone(id: UUID) {
        let deletionDate = Date()

        if let index = deletedExpenseTombstones.firstIndex(where: { $0.id == id }) {
            deletedExpenseTombstones[index].deletedAt = deletionDate
        } else {
            deletedExpenseTombstones.append(DeletionTombstone(id: id, deletedAt: deletionDate))
        }
    }

    private func mergedTombstones(
        _ local: [DeletionTombstone],
        _ remote: [DeletionTombstone]
    ) -> [DeletionTombstone] {
        Dictionary(grouping: local + remote, by: \.id)
            .compactMap { id, values in
                guard let latest = values.max(by: { $0.deletedAt < $1.deletedAt }) else { return nil }
                return DeletionTombstone(id: id, deletedAt: latest.deletedAt)
            }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    private func touchAndPersist() {
        snapshotUpdatedAt = Date()
        rebuildDerivedState()
        persist()
    }

    private func persist() {
        persistence.save(snapshot(), forKey: storageKey, updatedAt: snapshotUpdatedAt)
    }

    @discardableResult
    private func materializeRecurringExpenses(referenceDate: Date = Date()) -> Bool {
        guard !recurringPlans.isEmpty else { return false }

        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: referenceDate)
        var didChange = false

        for index in recurringPlans.indices {
            guard recurringPlans[index].isActive else { continue }

            var plan = recurringPlans[index]
            let firstCandidateDate: Date

            if let lastGeneratedDate = plan.lastGeneratedDate,
               let nextDate = nextDate(after: lastGeneratedDate, frequency: plan.frequency) {
                firstCandidateDate = nextDate
            } else {
                firstCandidateDate = calendar.startOfDay(for: plan.startDate)
            }

            var candidateDate = firstCandidateDate
            guard candidateDate <= referenceDay else { continue }

            while candidateDate <= referenceDay {
                let expenseID = recurringExpenseID(planID: plan.id, occurrenceDate: candidateDate)
                let isDeleted = deletedExpenseTombstones.contains(where: { $0.id == expenseID })

                if !isDeleted && !expenses.contains(where: { $0.id == expenseID }) {
                    let entry = Expense(
                        id: expenseID,
                        category: plan.category,
                        label: plan.label,
                        amount: plan.amount,
                        date: candidateDate,
                        notes: plan.notes,
                        tags: plan.tags,
                        recurringPlanID: plan.id,
                        createdAt: candidateDate,
                        updatedAt: candidateDate
                    )
                    expenses.append(entry)
                    didChange = true
                }

                plan.lastGeneratedDate = candidateDate
                plan.updatedAt = max(plan.updatedAt, candidateDate)

                guard let nextDate = nextDate(after: candidateDate, frequency: plan.frequency) else {
                    break
                }
                candidateDate = nextDate
            }

            if recurringPlans[index] != plan {
                recurringPlans[index] = plan
                didChange = true
            }
        }

        if didChange {
            expenses.sort {
                if $0.date == $1.date {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.date > $1.date
            }

            recurringPlans.sort { lhs, rhs in
                if lhs.isActive == rhs.isActive {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.isActive && !rhs.isActive
            }
        }

        return didChange
    }

    private func nextDate(after date: Date, frequency: RecurringExpenseFrequency) -> Date? {
        Calendar.current.date(byAdding: frequency.calendarComponent, value: 1, to: date)
            .map { Calendar.current.startOfDay(for: $0) }
    }

    private func mostRecentOccurrence(onOrBefore referenceDate: Date, for plan: RecurringExpensePlan) -> Date? {
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: plan.startDate)
        let referenceDay = calendar.startOfDay(for: referenceDate)

        guard current <= referenceDay else { return nil }

        while let next = nextDate(after: current, frequency: plan.frequency), next <= referenceDay {
            current = next
        }

        return current
    }

    private func recurringExpenseID(planID: UUID, occurrenceDate: Date) -> UUID {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let payload = "\(planID.uuidString)|\(formatter.string(from: occurrenceDate))"
        let digest = SHA256.hash(data: Data(payload.utf8))
        let bytes = Array(digest.prefix(16))
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}

private extension ExpenseStore {
    struct AdaptiveBurnComputation {
        let observedExpenseDays: Int
        let confidence: BurnRateConfidence
        let threeDayAverage: Double
        let sevenDayAverage: Double
        let thirtyDayAverage: Double
        let weightedDailyBurnRate: Double
        let predictedDailyBurnRate: Double
        let trend: SpendingTrend
        let anomaly: SpendingAnomaly?
    }

    struct MonthlyProjectionComputation {
        let observedDays: Int
        let confidence: BurnRateConfidence
        let dailyProjection: Double
        let monthlyExpenseEstimate: Double
    }

    struct LegacySnapshot: Codable {
        let startingBalance: Double
        let expenses: [LegacyExpense]
    }

    struct LegacyExpense: Codable {
        let id: UUID
        let category: ExpenseCategory
        let label: String
        let amount: Double
        let date: Date
    }

    static func migrateLegacySnapshot(
        from defaults: UserDefaults,
        storageKey: String
    ) -> ExpenseStoreSnapshot? {
        guard
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(LegacySnapshot.self, from: data)
        else {
            return nil
        }

        let expenses = snapshot.expenses.map { expense in
            Expense(
                id: expense.id,
                category: expense.category,
                label: expense.label,
                amount: expense.amount,
                date: expense.date,
                notes: "",
                tags: [],
                createdAt: expense.date,
                updatedAt: expense.date
            )
        }

        return ExpenseStoreSnapshot(
            startingBalance: snapshot.startingBalance,
            monthlyIncome: 0,
            expenses: expenses,
            recurringPlans: [],
            deletedExpenseTombstones: [],
            updatedAt: Date()
        )
    }

    static func looksLikeLegacySeedData(_ snapshot: ExpenseStoreSnapshot) -> Bool {
        // These fingerprints are only used to clear old demo content from earlier builds.
        // They do not seed new installs.
        let expenseSignatures = Set(
            snapshot.expenses.map { expense in
                "\(expense.label.lowercased())|\(expense.category.rawValue)|\(Int(expense.amount.rounded()))"
            }
        )

        let seedSignatures: Set<String> = [
            "coffee meetings|food|18",
            "commute|transport|12",
            "groceries|food|54",
            "portfolio coffee chat|networking|42",
            "lunch|food|16",
            "rent share|essentials|420",
            "utilities|essentials|68",
            "groceries|food|76",
            "prescription refill|health|58",
            "portfolio tool|software|28",
            "train card|transport|24",
        ]

        return snapshot.startingBalance == 2_100 &&
            snapshot.expenses.count == seedSignatures.count &&
            expenseSignatures == seedSignatures
    }
}
