import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var isNotificationsEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var statusMessage: String
    @Published private(set) var dailyReminderTime: Date

    private let persistence: PersistenceController
    private let expenseStore: ExpenseStore
    private let jobStore: JobApplicationStore
    private let appModeStore: AppModeStore
    private let aiService: AIInsightService
    private let center = UNUserNotificationCenter.current()
    private let preferencesKey = "careerfuel.notifications.preferences"
    private let dailyReminderIdentifier = "careerfuel.daily-reminder"

    private var cancellables = Set<AnyCancellable>()
    private var lastRunwayThreshold: Int?
    private var lastOverspendingSignature: String
    private var lastSuggestionSignature: String

    init(
        persistence: PersistenceController,
        expenseStore: ExpenseStore,
        jobStore: JobApplicationStore,
        appModeStore: AppModeStore,
        aiService: AIInsightService
    ) {
        self.persistence = persistence
        self.expenseStore = expenseStore
        self.jobStore = jobStore
        self.appModeStore = appModeStore
        self.aiService = aiService

        let preference = persistence.load(NotificationPreferenceSnapshot.self, forKey: preferencesKey)
        isNotificationsEnabled = preference?.isEnabled ?? false
        dailyReminderTime = Self.makeReminderTime(
            hour: preference?.reminderHour ?? 20,
            minute: preference?.reminderMinute ?? 0
        )
        lastRunwayThreshold = preference?.lastRunwayThreshold
        lastOverspendingSignature = preference?.lastOverspendingSignature ?? ""
        lastSuggestionSignature = preference?.lastSuggestionSignature ?? ""
        statusMessage = "Daily reminders are off."

        observeSignals()

        Task {
            await handleAppDidBecomeActive()
        }
    }

    var formattedReminderTime: String {
        dailyReminderTime.formatted(.dateTime.hour().minute())
    }

    func requestPermission() async -> Bool {
        await requestAuthorizationIfNeeded()
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await requestPermission()
            if granted {
                isNotificationsEnabled = true
                await updateSchedule()
            } else {
                isNotificationsEnabled = false
                await cancelAll()
            }
        } else {
            isNotificationsEnabled = false
            await cancelAll()
        }

        persistPreferences()
        updateStatusMessage()
    }

    func setDailyReminderTime(_ time: Date) {
        dailyReminderTime = Self.makeReminderTime(
            hour: Calendar.current.component(.hour, from: time),
            minute: Calendar.current.component(.minute, from: time)
        )
        persistPreferences()

        Task {
            await updateSchedule()
        }
    }

    func scheduleDailyReminder() async {
        guard isNotificationsEnabled else {
            updateStatusMessage()
            return
        }

        await refreshAuthorizationStatus()
        guard isAuthorizedForDelivery else {
            updateStatusMessage()
            return
        }

        let reminder = buildDailyReminder()
        let components = Self.reminderDateComponents(from: dailyReminderTime)

        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await add(request)
        } catch {
            statusMessage = "Could not schedule the daily reminder on this device."
        }
    }

    func updateSchedule() async {
        guard isNotificationsEnabled else {
            updateStatusMessage()
            return
        }

        await refreshAuthorizationStatus()
        guard isAuthorizedForDelivery else {
            updateStatusMessage()
            return
        }

        await scheduleDailyReminder()
        updateStatusMessage()
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        updateStatusMessage()
    }

    func handleAppDidBecomeActive() async {
        await refreshAuthorizationStatus()
        if isNotificationsEnabled {
            await updateSchedule()
        } else {
            updateStatusMessage()
        }
    }

    func resetLocalPreferences() async {
        isNotificationsEnabled = false
        dailyReminderTime = Self.makeReminderTime(hour: 20, minute: 0)
        lastRunwayThreshold = nil
        lastOverspendingSignature = ""
        lastSuggestionSignature = ""
        await cancelAll()
        persistence.removeValue(forKey: preferencesKey)
        await refreshAuthorizationStatus()
        updateStatusMessage()
    }

    private var isAuthorizedForDelivery: Bool {
        authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral
    }

    private func observeSignals() {
        Publishers.CombineLatest3(
            expenseStore.$dashboardSnapshot,
            aiService.$spendingAlerts,
            aiService.$latestSuggestionHeadline
        )
        .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _ in
            guard let self else { return }
            Task {
                await self.evaluateSmartAlerts()
            }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            expenseStore.$expenses
                .map(Self.hasExpenseLoggedToday)
                .removeDuplicates(),
            jobStore.$applications
                .map(Self.hasJobApplicationLoggedToday)
                .removeDuplicates(),
            appModeStore.$mode.removeDuplicates(),
            $dailyReminderTime
                .map(Self.reminderTimeKey)
                .removeDuplicates()
        )
        .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            guard let self else { return }
            Task {
                await self.updateSchedule()
            }
        }
        .store(in: &cancellables)
    }

    private func evaluateSmartAlerts() async {
        guard isNotificationsEnabled else { return }
        await refreshAuthorizationStatus()
        guard isAuthorizedForDelivery else { return }

        if
            expenseStore.dashboardSnapshot.burnRateConfidence != .insufficient,
            let threshold = runwayThreshold(for: expenseStore.daysLeft)
        {
            if lastRunwayThreshold == nil || threshold < (lastRunwayThreshold ?? Int.max) {
                await scheduleImmediateNotification(
                    identifier: "careerfuel.runway.\(threshold)",
                    title: "Runway alert",
                    body: "You have \(expenseStore.daysLeft) days left. Protect essentials and tighten the next few days."
                )
                lastRunwayThreshold = threshold
            }
        } else {
            lastRunwayThreshold = nil
        }

        let overspendingSignature = aiService.spendingAlerts
            .filter { $0.category != nil }
            .map(\.dedupeKey)
            .joined(separator: "|")

        if
            !overspendingSignature.isEmpty,
            overspendingSignature != lastOverspendingSignature,
            let topAlert = aiService.spendingAlerts.first(where: { $0.category != nil })
        {
            await scheduleImmediateNotification(
                identifier: "careerfuel.overspending.\(topAlert.id)",
                title: topAlert.title,
                body: topAlert.message
            )
            lastOverspendingSignature = overspendingSignature
        }

        let suggestionSignature = aiService.latestSuggestionHeadline
        if !suggestionSignature.isEmpty, suggestionSignature != lastSuggestionSignature {
            await scheduleImmediateNotification(
                identifier: "careerfuel.ai.\(stableHash(for: suggestionSignature))",
                title: "New AI suggestion",
                body: suggestionSignature
            )
            lastSuggestionSignature = suggestionSignature
        }

        persistPreferences()
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()
        if isAuthorizedForDelivery {
            return true
        }

        let granted = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        await refreshAuthorizationStatus()
        return granted
    }

    private func refreshAuthorizationStatus() async {
        let status = await withCheckedContinuation {
            (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }

        authorizationStatus = status
    }

    private func scheduleImmediateNotification(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try? await add(request)
    }

    private func buildDailyReminder() -> DailyReminderContent {
        let hasExpenseLoggedToday = Self.hasExpenseLoggedToday(expenses: expenseStore.expenses)
        let hasJobApplicationToday = Self.hasJobApplicationLoggedToday(applications: jobStore.applications)
        let variationSeed = dailyVariationSeed(
            mode: appModeStore.mode,
            hasExpenseLoggedToday: hasExpenseLoggedToday,
            hasJobApplicationToday: hasJobApplicationToday
        )

        switch appModeStore.mode {
        case .jobSearch:
            if !hasExpenseLoggedToday && !hasJobApplicationToday {
                return reminderContent(
                    title: "Stay on track today",
                    bodies: [
                        "Log your expenses and apply to at least 1 job today.",
                        "Track your spending and keep your job search active tonight.",
                        "Your runway depends on today’s actions. Update your expenses and applications.",
                        "Close the day by logging spending and pushing at least one job application forward.",
                    ],
                    variationSeed: variationSeed
                )
            }

            if !hasExpenseLoggedToday {
                return reminderContent(
                    title: "Log your expenses today",
                    bodies: [
                        "Update today’s spending so your runway stays accurate.",
                        "Record today’s expenses before the day closes so your cash picture stays clear.",
                        "Keep your spending under control by logging today’s expenses now.",
                    ],
                    variationSeed: variationSeed
                )
            }

            if !hasJobApplicationToday {
                return reminderContent(
                    title: "Keep the job search active",
                    bodies: [
                        "Apply to at least 1 job today to keep momentum alive.",
                        "Your pipeline needs another step today. Add one application before you stop.",
                        "Keep the search moving. Submit one application or advance one opportunity tonight.",
                    ],
                    variationSeed: variationSeed
                )
            }

            return reminderContent(
                title: "Nice work today",
                bodies: [
                    "You logged your progress today. Review tomorrow’s spending and pipeline when you’re ready.",
                    "Today’s essentials are covered. Keep the momentum going again tomorrow.",
                    "You’re up to date for today. Rest, then come back ready to protect runway and progress.",
                ],
                variationSeed: variationSeed
            )

        case .employed:
            if !hasExpenseLoggedToday {
                return reminderContent(
                    title: "Track your spending",
                    bodies: [
                        "Log today’s expenses to stay financially stable.",
                        "Keep your spending under control. Update your expenses today.",
                        "Close the day by recording your spending so your budget stays honest.",
                        "Protect your progress by logging today’s expenses before the day ends.",
                    ],
                    variationSeed: variationSeed
                )
            }

            return reminderContent(
                title: "Nice work today",
                bodies: [
                    "Your spending is already logged today. Keep checking in daily to stay financially stable.",
                    "You’re current on today’s expenses. Small check-ins like this protect your savings plan.",
                    "Today’s spending is already tracked. Keep the habit going tomorrow.",
                ],
                variationSeed: variationSeed
            )
        }
    }

    private func reminderContent(
        title: String,
        bodies: [String],
        variationSeed: String
    ) -> DailyReminderContent {
        let index = stableHash(for: variationSeed) % max(bodies.count, 1)
        return DailyReminderContent(title: title, body: bodies[index])
    }

    private func dailyVariationSeed(
        mode: AppMode,
        hasExpenseLoggedToday: Bool,
        hasJobApplicationToday: Bool
    ) -> String {
        let ordinal = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return "\(mode.rawValue)|expense:\(hasExpenseLoggedToday)|job:\(hasJobApplicationToday)|day:\(ordinal)"
    }

    private func updateStatusMessage() {
        if !isNotificationsEnabled {
            statusMessage = "Daily reminders are off."
            return
        }

        switch authorizationStatus {
        case .denied:
            statusMessage = "Notification permission is denied. Enable it in iOS Settings to receive reminders."
        case .authorized, .provisional, .ephemeral:
            statusMessage = "Daily reminders are scheduled for \(formattedReminderTime)."
        case .notDetermined:
            statusMessage = "Turn reminders on to request notification permission."
        @unknown default:
            statusMessage = "Notification status is unavailable on this device."
        }
    }

    private func runwayThreshold(for daysLeft: Int) -> Int? {
        if daysLeft <= 7 {
            return 7
        }
        if daysLeft <= 14 {
            return 14
        }
        if daysLeft <= 21 {
            return 21
        }
        return nil
    }

    private func persistPreferences() {
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: dailyReminderTime)
        let snapshot = NotificationPreferenceSnapshot(
            isEnabled: isNotificationsEnabled,
            reminderHour: timeComponents.hour ?? 20,
            reminderMinute: timeComponents.minute ?? 0,
            lastRunwayThreshold: lastRunwayThreshold,
            lastOverspendingSignature: lastOverspendingSignature,
            lastSuggestionSignature: lastSuggestionSignature
        )

        persistence.save(snapshot, forKey: preferencesKey, updatedAt: Date())
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func makeReminderTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func reminderDateComponents(from date: Date) -> DateComponents {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return DateComponents(hour: components.hour, minute: components.minute)
    }

    private static func reminderTimeKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return "\(components.hour ?? 20):\(components.minute ?? 0)"
    }

    private static func hasExpenseLoggedToday(expenses: [Expense]) -> Bool {
        let calendar = Calendar.current
        return expenses.contains { expense in
            calendar.isDateInToday(expense.createdAt)
        }
    }

    private static func hasJobApplicationLoggedToday(applications: [JobApplication]) -> Bool {
        let calendar = Calendar.current
        return applications.contains { application in
            calendar.isDateInToday(application.createdAt)
        }
    }

    private func stableHash(for text: String) -> Int {
        abs(text.unicodeScalars.reduce(0) { partialResult, scalar in
            ((partialResult * 31) + Int(scalar.value)) % 104_729
        })
    }
}

private struct DailyReminderContent {
    let title: String
    let body: String
}
