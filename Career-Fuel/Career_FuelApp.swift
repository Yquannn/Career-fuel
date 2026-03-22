//
//  Career_FuelApp.swift
//  Career-Fuel
//
//  Created by Yquan on 3/20/26.
//

import SwiftData
import SwiftUI

@main
struct Career_FuelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let persistenceController: PersistenceController

    @StateObject private var jobStore: JobApplicationStore
    @StateObject private var expenseStore: ExpenseStore
    @StateObject private var aiInsightService: AIInsightService
    @StateObject private var cloudSyncManager: CloudSyncManager
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var appModeStore: AppModeStore
    @StateObject private var insightsStore: InsightsStore
    @StateObject private var launchCoordinator: AppLaunchCoordinator

    init() {
        let persistence = PersistenceController()
        persistenceController = persistence

        let jobStore = JobApplicationStore(persistence: persistence)
        let expenseStore = ExpenseStore(persistence: persistence)
        let aiInsightService = AIInsightService(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore
        )
        let appModeStore = AppModeStore(jobStore: jobStore)
        let cloudSyncManager = CloudSyncManager(
            persistence: persistence,
            jobStore: jobStore,
            expenseStore: expenseStore
        )
        let notificationManager = NotificationManager(
            persistence: persistence,
            expenseStore: expenseStore,
            jobStore: jobStore,
            appModeStore: appModeStore,
            aiService: aiInsightService
        )
        let insightsStore = InsightsStore(
            jobStore: jobStore,
            expenseStore: expenseStore,
            appModeStore: appModeStore,
            aiService: aiInsightService,
            cloudSyncManager: cloudSyncManager
        )

        _jobStore = StateObject(wrappedValue: jobStore)
        _expenseStore = StateObject(wrappedValue: expenseStore)
        _aiInsightService = StateObject(wrappedValue: aiInsightService)
        _cloudSyncManager = StateObject(wrappedValue: cloudSyncManager)
        _notificationManager = StateObject(wrappedValue: notificationManager)
        _appModeStore = StateObject(wrappedValue: appModeStore)
        _insightsStore = StateObject(wrappedValue: insightsStore)
        _launchCoordinator = StateObject(wrappedValue: AppLaunchCoordinator())
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(jobStore)
                    .environmentObject(expenseStore)
                    .environmentObject(aiInsightService)
                    .environmentObject(cloudSyncManager)
                    .environmentObject(notificationManager)
                    .environmentObject(appModeStore)
                    .environmentObject(insightsStore)

                if launchCoordinator.isShowingLaunchOverlay {
                    LaunchLoadingView()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .task {
                launchCoordinator.configureIfNeeded(aiService: aiInsightService)
            }
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                guard newPhase == .active else { return }
                expenseStore.syncRecurringExpenses()
                Task {
                    await notificationManager.handleAppDidBecomeActive()
                }
            }
        }
    }
}
