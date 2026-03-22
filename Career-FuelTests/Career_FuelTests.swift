//
//  Career_FuelTests.swift
//  Career-FuelTests
//
//  Created by Yquan on 3/20/26.
//

import Foundation
import Testing
@testable import Career_Fuel

@MainActor
struct Career_FuelTests {

    @Test func aiInsightServiceDebouncesRapidExpenseChanges() async throws {
        let persistence = PersistenceController(inMemory: true)
        let jobStore = JobApplicationStore(persistence: persistence)
        let expenseStore = ExpenseStore(persistence: persistence)
        let service = AIInsightService(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore,
            insightDebounceInterval: .milliseconds(80)
        )

        let baseline = service.expenseInsightRefreshCount

        expenseStore.updateStartingBalance(2_500)
        expenseStore.add(
            ExpenseDraft(
                category: .food,
                label: "Coffee",
                amount: 140,
                notes: "Interview prep"
            )
        )
        expenseStore.add(
            ExpenseDraft(
                category: .transport,
                label: "Grab",
                amount: 260,
                notes: "Commute"
            )
        )
        expenseStore.add(
            ExpenseDraft(
                category: .software,
                label: "Domain",
                amount: 320,
                notes: "Portfolio"
            )
        )

        #expect(service.expenseInsightRefreshCount == baseline)

        try await Task.sleep(for: .milliseconds(40))
        #expect(service.expenseInsightRefreshCount == baseline)

        try await Task.sleep(for: .milliseconds(140))
        #expect(service.expenseInsightRefreshCount == baseline + 1)
    }

    @Test func aiInsightServiceSkipsNonMeaningfulWorkflowChanges() async throws {
        let persistence = PersistenceController(inMemory: true)
        let jobStore = JobApplicationStore(persistence: persistence)
        let expenseStore = ExpenseStore(persistence: persistence)
        let service = AIInsightService(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore,
            insightDebounceInterval: .milliseconds(80)
        )

        let savedStageID = jobStore.sortedStages.first(where: { $0.title == "Saved" })!.id
        let appliedStageID = jobStore.sortedStages.first(where: { $0.title == "Applied" })!.id

        jobStore.add(
            JobApplicationDraft(
                companyName: "Acme",
                role: "iOS Engineer",
                stageID: savedStageID,
                notes: "SwiftUI performance and app architecture"
            )
        )

        try await Task.sleep(for: .milliseconds(140))
        let baseline = service.jobInsightRefreshCount
        let applicationID = jobStore.applications.first!.id

        jobStore.moveApplication(id: applicationID, to: appliedStageID)

        try await Task.sleep(for: .milliseconds(140))
        #expect(service.jobInsightRefreshCount == baseline)
    }

    @Test func insightsStoreDebouncesRapidBalanceChangesAndSkipsDuplicateRefresh() async throws {
        let persistence = PersistenceController(inMemory: true)
        let jobStore = JobApplicationStore(persistence: persistence)
        let expenseStore = ExpenseStore(persistence: persistence)
        let aiService = AIInsightService(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore,
            insightDebounceInterval: .milliseconds(80)
        )
        let cloudSyncManager = CloudSyncManager(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore
        )
        let insightsStore = InsightsStore(
            jobStore: jobStore,
            expenseStore: expenseStore,
            aiService: aiService,
            cloudSyncManager: cloudSyncManager,
            debounceInterval: .milliseconds(80)
        )

        let baseline = insightsStore.refreshComputationCount

        insightsStore.refresh()
        #expect(insightsStore.refreshComputationCount == baseline)

        expenseStore.updateStartingBalance(1_000)
        expenseStore.updateStartingBalance(1_200)
        expenseStore.updateStartingBalance(1_400)

        #expect(insightsStore.refreshComputationCount == baseline)

        try await Task.sleep(for: .milliseconds(40))
        #expect(insightsStore.refreshComputationCount == baseline)

        try await Task.sleep(for: .milliseconds(140))
        #expect(insightsStore.refreshComputationCount == baseline + 1)

        insightsStore.refresh()
        #expect(insightsStore.refreshComputationCount == baseline + 1)
    }

    @Test func insightsStoreIgnoresJobStageChangesWhenJobsNeededIsUnchanged() async throws {
        let persistence = PersistenceController(inMemory: true)
        let jobStore = JobApplicationStore(persistence: persistence)
        let expenseStore = ExpenseStore(persistence: persistence)
        let aiService = AIInsightService(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore,
            insightDebounceInterval: .milliseconds(80)
        )
        let cloudSyncManager = CloudSyncManager(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore
        )
        let insightsStore = InsightsStore(
            jobStore: jobStore,
            expenseStore: expenseStore,
            aiService: aiService,
            cloudSyncManager: cloudSyncManager,
            debounceInterval: .milliseconds(80)
        )

        let interviewStageID = jobStore.sortedStages.first(where: { $0.title == "Interview" })!.id
        let offerStageID = jobStore.sortedStages.first(where: { $0.title == "Offer" })!.id

        jobStore.add(
            JobApplicationDraft(
                companyName: "Acme",
                role: "iOS Engineer",
                stageID: interviewStageID,
                notes: "Architecture and product systems"
            )
        )

        try await Task.sleep(for: .milliseconds(140))
        let baseline = insightsStore.refreshComputationCount
        let applicationID = jobStore.applications.first!.id

        jobStore.moveApplication(id: applicationID, to: offerStageID)

        try await Task.sleep(for: .milliseconds(140))
        #expect(insightsStore.refreshComputationCount == baseline)
    }

    @Test func aiInsightServiceReusesCachedExpenseInsightsWhenInputReturns() async throws {
        let persistence = PersistenceController(inMemory: true)
        let jobStore = JobApplicationStore(persistence: persistence)
        let expenseStore = ExpenseStore(persistence: persistence)
        let service = AIInsightService(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore,
            insightDebounceInterval: .milliseconds(80)
        )

        let baseline = service.expenseInsightRefreshCount

        expenseStore.updateStartingBalance(500)
        try await Task.sleep(for: .milliseconds(140))
        #expect(service.expenseInsightRefreshCount == baseline + 1)

        expenseStore.updateStartingBalance(0)
        try await Task.sleep(for: .milliseconds(140))
        #expect(service.expenseInsightRefreshCount == baseline + 1)
    }

    @Test func insightsStoreReusesCachedSignalsWhenRunwayStateReturns() async throws {
        let persistence = PersistenceController(inMemory: true)
        let jobStore = JobApplicationStore(persistence: persistence)
        let expenseStore = ExpenseStore(persistence: persistence)
        let aiService = AIInsightService(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore,
            insightDebounceInterval: .milliseconds(80)
        )
        let cloudSyncManager = CloudSyncManager(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore
        )
        let insightsStore = InsightsStore(
            jobStore: jobStore,
            expenseStore: expenseStore,
            aiService: aiService,
            cloudSyncManager: cloudSyncManager,
            debounceInterval: .milliseconds(80)
        )

        let baseline = insightsStore.refreshComputationCount

        expenseStore.updateStartingBalance(500)
        try await Task.sleep(for: .milliseconds(140))
        #expect(insightsStore.refreshComputationCount == baseline + 1)

        expenseStore.updateStartingBalance(0)
        try await Task.sleep(for: .milliseconds(140))
        #expect(insightsStore.refreshComputationCount == baseline + 1)
    }

    @Test func expenseStoreUsesActualExpenseDaysForBurnRateAndDaysLeft() async throws {
        let persistence = PersistenceController(inMemory: true)
        let expenseStore = ExpenseStore(persistence: persistence)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        expenseStore.updateStartingBalance(20_000)

        expenseStore.add(
            ExpenseDraft(
                category: .essentials,
                label: "Rent share",
                amount: 500,
                date: calendar.date(byAdding: .day, value: -2, to: today) ?? today
            )
        )
        expenseStore.add(
            ExpenseDraft(
                category: .food,
                label: "Groceries",
                amount: 600,
                date: calendar.date(byAdding: .day, value: -1, to: today) ?? today
            )
        )
        expenseStore.add(
            ExpenseDraft(
                category: .transport,
                label: "Commute",
                amount: 550,
                date: today
            )
        )

        #expect(abs(expenseStore.dailyBurnRate - 550) < 0.01)
        #expect(abs(expenseStore.activeDailySpendRate - 550) < 0.01)
        #expect(expenseStore.daysLeft == 36)
        #expect(expenseStore.dashboardSnapshot.burnRateConfidence == .medium)
        #expect(expenseStore.dashboardSnapshot.observedExpenseDays == 3)
        #expect(expenseStore.dashboardSnapshot.trackedCalendarDays == 3)
    }

    @Test func expenseStoreSeparatesSurvivalBurnFromActiveSpendRateWhenThereAreZeroSpendDays() async throws {
        let persistence = PersistenceController(inMemory: true)
        let expenseStore = ExpenseStore(persistence: persistence)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        expenseStore.updateStartingBalance(5_000)

        expenseStore.add(
            ExpenseDraft(
                category: .essentials,
                label: "Bills",
                amount: 600,
                date: calendar.date(byAdding: .day, value: -4, to: today) ?? today
            )
        )
        expenseStore.add(
            ExpenseDraft(
                category: .food,
                label: "Groceries",
                amount: 400,
                date: today
            )
        )

        #expect(abs(expenseStore.dailyBurnRate - 200) < 0.01)
        #expect(abs(expenseStore.activeDailySpendRate - 500) < 0.01)
        #expect(expenseStore.daysLeft == 25)
        #expect(expenseStore.dashboardSnapshot.observedExpenseDays == 2)
        #expect(expenseStore.dashboardSnapshot.trackedCalendarDays == 5)
    }

    @Test func expenseStoreProjectsMonthlyExpensesFromObservedExpenseDays() async throws {
        let persistence = PersistenceController(inMemory: true)
        let expenseStore = ExpenseStore(persistence: persistence)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        expenseStore.updateMonthlyIncome(50_000)

        let amounts: [Double] = [600, 150, 300, 3_000, 1_000]
        for (offset, amount) in amounts.enumerated() {
            _ = expenseStore.add(
                ExpenseDraft(
                    category: .essentials,
                    label: "Expense \(offset)",
                    amount: amount,
                    date: calendar.date(byAdding: .day, value: -offset, to: today) ?? today
                )
            )
        }

        // 5 expense days out of 30 calendar days → irregular spender → monthly = total
        #expect(abs(expenseStore.monthlyExpenseEstimate - 5_050) < 0.01)
        #expect(expenseStore.employmentSnapshot.monthlyProjectionObservedDays == 5)
        #expect(expenseStore.employmentSnapshot.monthlyProjectionConfidence == .medium)
        #expect(expenseStore.dashboardSnapshot.spenderBehavior == .irregular)
    }

    @Test func expenseStoreClassifiesDailySpenderAndProjectsCorrectly() async throws {
        let persistence = PersistenceController(inMemory: true)
        let expenseStore = ExpenseStore(persistence: persistence)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        expenseStore.updateStartingBalance(100_000)
        expenseStore.updateMonthlyIncome(50_000)

        // Add expenses on 25 out of the last 30 days → frequency ~0.83 → daily spender
        for offset in 0..<25 {
            _ = expenseStore.add(
                ExpenseDraft(
                    category: .food,
                    label: "Daily expense \(offset)",
                    amount: 100,
                    date: calendar.date(byAdding: .day, value: -offset, to: today) ?? today
                )
            )
        }

        let totalSpent = 25.0 * 100  // 2500
        let dailyProjection = totalSpent / 30.0
        let expectedMonthly = dailyProjection * 30  // ≈ 2500

        #expect(expenseStore.dashboardSnapshot.spenderBehavior == .daily)
        #expect(expenseStore.dashboardSnapshot.spendingFrequency > 0.7)
        #expect(abs(expenseStore.monthlyExpenseEstimate - expectedMonthly) < 1)
        #expect(expenseStore.employmentSnapshot.monthlyProjectionConfidence == .high)
    }

    @Test func expenseStoreClassifiesIrregularSpenderAndUsesTotalExpenses() async throws {
        let persistence = PersistenceController(inMemory: true)
        let expenseStore = ExpenseStore(persistence: persistence)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        expenseStore.updateStartingBalance(50_000)
        expenseStore.updateMonthlyIncome(40_000)

        // Add 3 large expenses spread across 30 days → frequency = 3/30 = 0.1 → irregular
        let dates = [-2, -12, -25]
        let amounts: [Double] = [5_000, 3_000, 2_000]
        for (i, dayOffset) in dates.enumerated() {
            _ = expenseStore.add(
                ExpenseDraft(
                    category: .essentials,
                    label: "Big expense \(i)",
                    amount: amounts[i],
                    date: calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
                )
            )
        }

        let totalSpent = 10_000.0

        #expect(expenseStore.dashboardSnapshot.spenderBehavior == .irregular)
        #expect(expenseStore.dashboardSnapshot.spendingFrequency < 0.3)
        // Irregular: monthly = total spent in the 30-day window
        #expect(abs(expenseStore.monthlyExpenseEstimate - totalSpent) < 1)
    }

    @Test func expenseStoreClassifiesMixedSpenderAndUsesBlendedProjection() async throws {
        let persistence = PersistenceController(inMemory: true)
        let expenseStore = ExpenseStore(persistence: persistence)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        expenseStore.updateStartingBalance(80_000)
        expenseStore.updateMonthlyIncome(60_000)

        // Add expenses on 12 out of 30 days → frequency = 12/30 = 0.4 → mixed
        for offset in 0..<12 {
            _ = expenseStore.add(
                ExpenseDraft(
                    category: .food,
                    label: "Mixed expense \(offset)",
                    amount: 200,
                    date: calendar.date(byAdding: .day, value: -(offset * 2), to: today) ?? today
                )
            )
        }

        #expect(expenseStore.dashboardSnapshot.spenderBehavior == .mixed)
        let frequency = expenseStore.dashboardSnapshot.spendingFrequency
        #expect(frequency >= 0.3 && frequency <= 0.7)
        #expect(expenseStore.employmentSnapshot.monthlyProjectionConfidence == .high)
    }

    @Test func expenseStoreShowsPlaceholderWithNoData() async throws {
        let persistence = PersistenceController(inMemory: true)
        let expenseStore = ExpenseStore(persistence: persistence)

        #expect(expenseStore.monthlyExpenseEstimate == 0)
        #expect(expenseStore.employmentSnapshot.monthlyProjectionConfidence == .insufficient)
        #expect(expenseStore.dashboardSnapshot.spenderBehavior == .mixed)
        #expect(expenseStore.dashboardSnapshot.spendingFrequency == 0)
    }

}
