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
        #expect(expenseStore.daysLeft == 36)
        #expect(expenseStore.dashboardSnapshot.burnRateConfidence == .medium)
        #expect(expenseStore.dashboardSnapshot.observedExpenseDays == 3)
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

        #expect(abs(expenseStore.monthlyExpenseEstimate - 30_300) < 0.01)
        #expect(expenseStore.employmentSnapshot.monthlyProjectionObservedDays == 5)
        #expect(expenseStore.employmentSnapshot.monthlyProjectionConfidence == .medium)
    }

}
