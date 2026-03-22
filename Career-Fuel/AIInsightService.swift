import Combine
import Foundation
import NaturalLanguage

@MainActor
final class AIInsightService: ObservableObject {
    @Published private(set) var spendingAlerts: [AISpendingAlert] = []
    @Published private(set) var budgetRecommendations: [BudgetRecommendation] = []
    @Published private(set) var jobSuggestions: [UUID: AIJobSuggestion] = [:]
    @Published private(set) var latestSuggestionHeadline: String = ""
    @Published private(set) var recommendedDailyBudget: Double = 40
    @Published private(set) var isRefreshingExpenseInsights = false
    @Published private(set) var isRefreshingJobInsights = false
    @Published var isWebInterviewResearchEnabled: Bool
    @Published private(set) var hasStoredGeminiAPIKey: Bool
    @Published private(set) var interviewResearchStatuses: [UUID: InterviewResearchStatus] = [:]

    private(set) var expenseInsightRefreshCount = 0
    private(set) var jobInsightRefreshCount = 0

    private let persistence: PersistenceController
    private let jobStore: JobApplicationStore
    private let expenseStore: ExpenseStore
    private let apiKeyStore: GeminiAPIKeyStore
    private let interviewResearchClient: GeminiInterviewResearchClient
    private let insightDebounceInterval: RunLoop.SchedulerTimeType.Stride
    private var cancellables = Set<AnyCancellable>()
    private let researchPreferenceStorageKey = "careerfuel.ai.gemini.preferences.v1"
    private var applicationSuggestionSignatures: [UUID: String] = [:]
    private var lastExpenseInsightInput: ExpenseInsightInput?
    private var lastJobInsightInput: JobInsightInput?
    private var expenseInsightCache = ComputationCache<ExpenseInsightInput, ExpenseInsightOutput>(capacity: 10)
    private var jobInsightCache = ComputationCache<JobInsightInput, JobInsightOutput>(capacity: 10)

    private let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

    init(
        persistence: PersistenceController,
        jobStore: JobApplicationStore,
        expenseStore: ExpenseStore,
        insightDebounceInterval: RunLoop.SchedulerTimeType.Stride = .milliseconds(400),
        apiKeyStore: GeminiAPIKeyStore = GeminiAPIKeyStore(),
        interviewResearchClient: GeminiInterviewResearchClient = GeminiInterviewResearchClient()
    ) {
        self.persistence = persistence
        self.jobStore = jobStore
        self.expenseStore = expenseStore
        self.insightDebounceInterval = insightDebounceInterval
        self.apiKeyStore = apiKeyStore
        self.interviewResearchClient = interviewResearchClient

        let preferences = persistence.load(GeminiResearchPreferenceSnapshot.self, forKey: researchPreferenceStorageKey)
        isWebInterviewResearchEnabled = preferences?.isEnabled ?? false
        if let storedKey = try? apiKeyStore.load() {
            hasStoredGeminiAPIKey = !storedKey.isEmpty
        } else {
            hasStoredGeminiAPIKey = false
        }

        Publishers.CombineLatest(
            expenseStore.$dashboardSnapshot,
            expenseStore.$analyticsSummary
        )
        .map { ExpenseInsightInput(dashboardSnapshot: $0, analyticsSummary: $1) }
        .removeDuplicates()
        .handleEvents(receiveOutput: { [weak self] input in
            guard let self, input != self.lastExpenseInsightInput else { return }
            if !self.isRefreshingExpenseInsights {
                self.isRefreshingExpenseInsights = true
            }
        })
        .debounce(for: insightDebounceInterval, scheduler: RunLoop.main)
        .sink { [weak self] input in
            self?.refreshExpenseInsights(using: input)
        }
        .store(in: &cancellables)

        jobStore.$applications
        .map { [weak self] applications in
            self?.jobInsightInput(for: applications) ?? JobInsightInput.empty
        }
        .removeDuplicates()
        .handleEvents(receiveOutput: { [weak self] input in
            guard let self, input != self.lastJobInsightInput else { return }
            if !self.isRefreshingJobInsights {
                self.isRefreshingJobInsights = true
            }
        })
        .debounce(for: insightDebounceInterval, scheduler: RunLoop.main)
        .sink { [weak self] input in
            self?.refreshJobInsights(using: input)
        }
        .store(in: &cancellables)

        refresh(force: true)
    }

    var canUseWebInterviewResearch: Bool {
        isWebInterviewResearchEnabled && hasStoredGeminiAPIKey
    }

    var webInterviewResearchStatusMessage: String {
        if !hasStoredGeminiAPIKey {
            return "Add a Gemini API key to enable public interview research."
        }

        if isWebInterviewResearchEnabled {
            return "Source-backed interview research is enabled. Refresh it from a job card when you want current public signals."
        }

        return "Gemini API key is stored. Turn this on when you want live public interview research."
    }

    func setWebInterviewResearchEnabled(_ isEnabled: Bool) {
        isWebInterviewResearchEnabled = isEnabled
        persistResearchPreferences()
    }

    func saveGeminiAPIKey(_ apiKey: String) -> String? {
        do {
            try apiKeyStore.save(apiKey)
            hasStoredGeminiAPIKey = true
            return nil
        } catch {
            if let storedKey = try? apiKeyStore.load() {
                hasStoredGeminiAPIKey = !storedKey.isEmpty
            } else {
                hasStoredGeminiAPIKey = false
            }
            return error.localizedDescription
        }
    }

    func removeGeminiAPIKey() -> String? {
        do {
            try apiKeyStore.delete()
            hasStoredGeminiAPIKey = false
            isWebInterviewResearchEnabled = false
            persistResearchPreferences()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func resetLocalPreferences() {
        _ = removeGeminiAPIKey()
        persistence.removeValue(forKey: researchPreferenceStorageKey)
        interviewResearchStatuses = [:]
    }

    func interviewResearchStatus(for applicationID: UUID) -> InterviewResearchStatus {
        interviewResearchStatuses[applicationID] ?? .idle
    }

    func refreshWebInterviewResearch(for applicationID: UUID) async {
        guard isWebInterviewResearchEnabled else {
            interviewResearchStatuses[applicationID] = InterviewResearchStatus(
                isLoading: false,
                errorMessage: "Enable Gemini web interview research in Settings first."
            )
            return
        }

        guard let apiKey = try? apiKeyStore.load(), !apiKey.isEmpty else {
            hasStoredGeminiAPIKey = false
            interviewResearchStatuses[applicationID] = InterviewResearchStatus(
                isLoading: false,
                errorMessage: "Add a valid Gemini API key in Settings first."
            )
            return
        }

        guard let application = jobStore.applications.first(where: { $0.id == applicationID }) else {
            return
        }

        interviewResearchStatuses[applicationID] = InterviewResearchStatus(isLoading: true, errorMessage: nil)

        do {
            let research = try await interviewResearchClient.fetchInterviewResearch(
                for: application,
                apiKey: apiKey
            )
            jobStore.updateWebInterviewResearch(id: applicationID, research: research)
            interviewResearchStatuses[applicationID] = .idle
        } catch {
            interviewResearchStatuses[applicationID] = InterviewResearchStatus(
                isLoading: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    func refresh() {
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        refreshExpenseInsights(using: currentExpenseInsightInput(), force: force)
        refreshJobInsights(using: currentJobInsightInput(), force: force)
    }

    private func refreshExpenseInsights(
        using input: ExpenseInsightInput,
        force: Bool = false
    ) {
        guard force || input != lastExpenseInsightInput else { return }
        lastExpenseInsightInput = input
        let output: ExpenseInsightOutput
        if !force, let cached = expenseInsightCache.value(for: input) {
            output = cached
        } else {
            expenseInsightRefreshCount += 1
            let computed = buildExpenseInsightOutput()
            expenseInsightCache.insert(computed, for: input)
            output = computed
        }

        if recommendedDailyBudget != output.recommendedDailyBudget {
            recommendedDailyBudget = output.recommendedDailyBudget
        }

        if budgetRecommendations != output.budgetRecommendations {
            budgetRecommendations = output.budgetRecommendations
        }

        if spendingAlerts != output.spendingAlerts {
            spendingAlerts = output.spendingAlerts
        }

        updateLatestSuggestionHeadline(jobSuggestions: jobSuggestions)
        if isRefreshingExpenseInsights {
            isRefreshingExpenseInsights = false
        }
    }

    private func refreshJobInsights(
        using input: JobInsightInput,
        force: Bool = false
    ) {
        guard force || input != lastJobInsightInput else { return }
        lastJobInsightInput = input
        let output: JobInsightOutput
        if !force, let cached = jobInsightCache.value(for: input) {
            output = cached
        } else {
            jobInsightRefreshCount += 1
            let computed = buildJobInsightOutput(using: input)
            jobInsightCache.insert(computed, for: input)
            output = computed
        }

        applicationSuggestionSignatures = output.signatures
        if jobSuggestions != output.suggestions {
            jobSuggestions = output.suggestions
        }

        let filteredStatuses = interviewResearchStatuses.filter { key, _ in
            input.applications.contains(where: { $0.id == key })
        }
        if interviewResearchStatuses != filteredStatuses {
            interviewResearchStatuses = filteredStatuses
        }

        updateLatestSuggestionHeadline(jobSuggestions: output.suggestions)
        if isRefreshingJobInsights {
            isRefreshingJobInsights = false
        }
    }

    private func updateLatestSuggestionHeadline(jobSuggestions: [UUID: AIJobSuggestion]) {
        let nextHeadline = spendingAlerts.first?.title
            ?? budgetRecommendations.first?.rationale
            ?? jobSuggestions.values.first?.webResearch?.likelyQuestions.first
            ?? jobSuggestions.values.first?.interviewQuestions.first
            ?? ""

        if latestSuggestionHeadline != nextHeadline {
            latestSuggestionHeadline = nextHeadline
        }
    }

    func expenseSuggestion(
        label: String,
        amount: Double,
        notes: String = "",
        currentCategory: ExpenseCategory? = nil
    ) -> AIExpenseSuggestion? {
        let query = normalizedText([label, notes])
        guard !query.isEmpty else { return nil }

        let categoryResult = classifyExpense(text: query, fallback: currentCategory)
        let tags = extractedTags(from: query, fallback: categoryResult.category.title)
        let actions = savingActions(for: categoryResult.category, amount: amount, label: query)

        return AIExpenseSuggestion(
            suggestedCategory: categoryResult.category,
            confidence: categoryResult.confidence,
            tags: Array(tags.prefix(3)),
            savingActions: actions
        )
    }

    func jobSuggestion(for application: JobApplication) -> AIJobSuggestion {
        let relatedCompanies = rankRelatedCompanies(for: application)
        let localQuestions = rankedInterviewQuestions(for: application)
        let webQuestions = application.webInterviewResearch?.likelyQuestions ?? []
        let combinedQuestions = (webQuestions + localQuestions).uniqued()
        let coachingTip = application.webInterviewResearch?.preparationFocus.first
            ?? rankedCoachingTip(for: application)

        return AIJobSuggestion(
            relatedCompanies: relatedCompanies,
            interviewQuestions: Array(combinedQuestions.prefix(6)),
            coachingTip: coachingTip,
            webResearch: application.webInterviewResearch
        )
    }

    func relatedCompanies(for application: JobApplication) -> [String] {
        rankRelatedCompanies(for: application)
    }

    func suggestedJobTags(for application: JobApplication) -> [String] {
        let text = normalizedText([application.role, application.notes, application.feedback, application.companyName])
        return Array(extractedTags(from: text, fallback: application.role).prefix(4))
    }

    func projectedWeeklySpend() -> Double {
        let history = expenseStore.weeklySpendHistory(weeks: 8).map(\.amount)
        return max(blendedForecast(for: history), expenseStore.weeklySpending)
    }

    private func buildBudgetRecommendations() -> [BudgetRecommendation] {
        let daysPressure = max(expenseStore.daysLeft, 1)
        let tighteningMultiplier = daysPressure <= 14 ? 0.78 : (daysPressure <= 21 ? 0.86 : 0.93)

        return ExpenseCategory.allCases.compactMap { category in
            let history = weeklyHistory(for: category, weeks: 8)
            let recentSpend = Array(history.suffix(4))
            guard recentSpend.contains(where: { $0 > 0 }) else { return nil }

            let average = recentSpend.average
            let forecast = blendedForecast(for: history)
            let variability = standardDeviation(recentSpend)
            let target = max(min(max(forecast, average) * tighteningMultiplier, average + (variability * 0.45)), 8)
            let currentWeek = expenseStore.spendByCategory(inLastDays: 7)[category] ?? 0

            let rationale: String
            if currentWeek > target + max(variability, 10) {
                rationale = "\(category.title) is running above the learned weekly pace. Pull back by about \((currentWeek - target).currencyString) over the next 7 days."
            } else {
                rationale = "This target follows your recent pattern while leaving more room for runway."
            }

            return BudgetRecommendation(
                id: category.rawValue,
                category: category,
                weeklyLimit: round(target),
                rationale: rationale
            )
        }
        .sorted { lhs, rhs in
            let lhsSpend = expenseStore.spendByCategory(inLastDays: 28)[lhs.category] ?? 0
            let rhsSpend = expenseStore.spendByCategory(inLastDays: 28)[rhs.category] ?? 0
            return lhsSpend > rhsSpend
        }
        .prefix(4)
        .map { $0 }
    }

    private func buildSpendingAlerts(
        recommendedDailyBudget: Double,
        budgetRecommendations: [BudgetRecommendation]
    ) -> [AISpendingAlert] {
        let currentWeekSpend = expenseStore.spendByCategory(inLastDays: 7)
        let budgetIndex = Dictionary(uniqueKeysWithValues: budgetRecommendations.map { ($0.category, $0.weeklyLimit) })
        var alerts: [AISpendingAlert] = []

        for category in ExpenseCategory.allCases {
            let history = weeklyHistory(for: category, weeks: 8)
            let currentWeek = currentWeekSpend[category] ?? 0
            guard currentWeek > 0 else { continue }

            let predicted = max(blendedForecast(for: history), budgetIndex[category] ?? 0, 8)
            let deviation = max(standardDeviation(Array(history.suffix(4))), 10)
            let anomalyScore = (currentWeek - predicted) / deviation

            if anomalyScore > 1.1 || currentWeek > predicted * 1.18 {
                let tone: StatusTone = anomalyScore > 1.85 || currentWeek > predicted * 1.4 ? .danger : .warning
                let recommendation = savingActions(for: category, amount: currentWeek, label: category.title).first ?? "Pull back this category for the next few days."

                alerts.append(
                    AISpendingAlert(
                        id: "overspend-\(category.rawValue)",
                        title: "\(category.title) is above its learned pace",
                        message: "This week landed at \(currentWeek.currencyString) against a modeled pace of about \(predicted.currencyString). \(recommendation)",
                        tone: tone,
                        symbol: "exclamationmark.triangle.fill",
                        category: category,
                        dedupeKey: "\(category.rawValue)-\(Int(currentWeek.rounded()))"
                    )
                )
            }
        }

        let projectedShortfall = max((projectedWeeklySpend() / 7) - recommendedDailyBudget, 0) * Double(min(max(expenseStore.daysLeft, 7), 30))
        if projectedShortfall > 60 {
            alerts.append(
                AISpendingAlert(
                    id: "runway-shortfall",
                    title: "Projected savings shortage",
                    message: "The current spend trend suggests a shortfall of roughly \(projectedShortfall.currencyString) over the next month unless burn slows.",
                    tone: expenseStore.daysLeft <= 14 ? .danger : .warning,
                    symbol: "flame.fill",
                    category: nil,
                    dedupeKey: "shortfall-\(Int(projectedShortfall.rounded()))"
                )
            )
        }

        return Array(alerts.prefix(4))
    }

    private func buildExpenseInsightOutput() -> ExpenseInsightOutput {
        let nextRecommendedDailyBudget = buildRecommendedDailyBudget()
        let nextBudgetRecommendations = buildBudgetRecommendations()
        let nextSpendingAlerts = buildSpendingAlerts(
            recommendedDailyBudget: nextRecommendedDailyBudget,
            budgetRecommendations: nextBudgetRecommendations
        )

        return ExpenseInsightOutput(
            recommendedDailyBudget: nextRecommendedDailyBudget,
            budgetRecommendations: nextBudgetRecommendations,
            spendingAlerts: nextSpendingAlerts
        )
    }

    private func currentExpenseInsightInput() -> ExpenseInsightInput {
        ExpenseInsightInput(
            dashboardSnapshot: expenseStore.dashboardSnapshot,
            analyticsSummary: expenseStore.analyticsSummary
        )
    }

    private func currentJobInsightInput() -> JobInsightInput {
        jobInsightInput(for: jobStore.applications)
    }

    private func jobInsightInput(for applications: [JobApplication]) -> JobInsightInput {
        let companyUniverseSignature = applications
            .map { $0.companyName.lowercased() }
            .sorted()
            .joined(separator: "|")
        let signature = applications
            .map { application in
                jobSuggestionSignature(
                    for: application,
                    companyUniverseSignature: companyUniverseSignature
                )
            }
            .sorted()
            .joined(separator: "§")

        return JobInsightInput(
            signature: signature,
            companyUniverseSignature: companyUniverseSignature,
            applications: applications
        )
    }

    private func buildRecommendedDailyBudget() -> Double {
        let weeklyHistory = expenseStore.weeklySpendHistory(weeks: 8).map(\.amount)
        let modeledWeeklySpend = blendedForecast(for: weeklyHistory)
        let runwayDays = max(Double(max(expenseStore.daysLeft, 21)), 1)
        let runwayTarget = expenseStore.currentBalance > 0
            ? max(expenseStore.currentBalance / runwayDays, 15)
            : 15
        let modelTarget = modeledWeeklySpend > 0
            ? max((modeledWeeklySpend / 7) * 0.92, 15)
            : runwayTarget

        return round(min(runwayTarget, modelTarget))
    }

    private func buildJobInsightOutput(using input: JobInsightInput) -> JobInsightOutput {
        let companyUniverseSignature = input.companyUniverseSignature
        var nextSuggestions: [UUID: AIJobSuggestion] = [:]
        var nextSignatures: [UUID: String] = [:]

        for application in input.applications {
            let signature = jobSuggestionSignature(
                for: application,
                companyUniverseSignature: companyUniverseSignature
            )
            nextSignatures[application.id] = signature

            if
                applicationSuggestionSignatures[application.id] == signature,
                let cached = jobSuggestions[application.id]
            {
                nextSuggestions[application.id] = cached
            } else {
                nextSuggestions[application.id] = jobSuggestion(for: application)
            }
        }

        return JobInsightOutput(
            suggestions: nextSuggestions,
            signatures: nextSignatures
        )
    }

    private func classifyExpense(
        text: String,
        fallback: ExpenseCategory?
    ) -> (category: ExpenseCategory, confidence: Double) {
        let normalized = normalizedText([text])
        let corpus = adaptiveExpenseTrainingExamples()
        let groupedScores = Dictionary(grouping: corpus, by: \.category)
            .mapValues { samples in
                samples
                    .map { similarityScore(between: normalized, and: $0.text) * $0.weight }
                    .sorted(by: >)
                    .prefix(3)
                    .average
            }

        let sorted = groupedScores.sorted { $0.value > $1.value }
        if let best = sorted.first {
            let second = sorted.dropFirst().first?.value ?? 0
            let margin = max(best.value - second, 0)
            let confidence = min(max(0.52 + margin * 0.55, 0.52), 0.96)
            return (best.key, confidence)
        }

        return (fallback ?? .essentials, 0.45)
    }

    private func rankRelatedCompanies(for application: JobApplication) -> [String] {
        let query = jobQuery(for: application)
        let learnedCompanies = learnedCompanyProfiles(excluding: application.companyName)
            .map { profile in
                RankedValue(value: profile.company, score: similarityScore(between: query, and: profile.profile))
            }
            .sorted { $0.score > $1.score }
            .prefix(4)
            .map(\.value)

        if !learnedCompanies.isEmpty {
            return learnedCompanies
        }

        return fallbackRelatedCompanies(from: application)
    }

    private func rankedInterviewQuestions(for application: JobApplication) -> [String] {
        let role = application.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = jobQuery(for: application)
        let themes = semanticThemes(for: application, limit: 4)
        var questions: [String] = []

        if !role.isEmpty {
            questions.append("What makes you effective in a \(role) role when priorities shift quickly?")
        }

        for theme in themes {
            let phrase = theme.lowercased()
            questions.append("Tell me about a time you improved \(phrase).")
            questions.append("How do you approach \(phrase) when the tradeoffs are unclear?")
            questions.append("What did you measure to know your work on \(phrase) actually worked?")
        }

        if !application.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let feedbackFocus = semanticThemes(from: application.feedback, limit: 1).first ?? application.feedback
            questions.insert("What changed in your process after you received feedback about \(feedbackFocus.lowercased())?", at: 0)
        }

        if let focus = application.webInterviewResearch?.preparationFocus.first {
            questions.insert("How would you demonstrate strength in \(focus.lowercased()) during this interview loop?", at: 0)
        }

        return questions
            .uniqued()
            .map { question in
                RankedValue(
                    value: question,
                    score: similarityScore(between: normalizedText([question]), and: query)
                )
            }
            .sorted { $0.score > $1.score }
            .map(\.value)
    }

    private func rankedCoachingTip(for application: JobApplication) -> String {
        let feedback = application.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !feedback.isEmpty {
            return "Focus on this feedback first and show what changed in your process: \(feedback)"
        }

        if let focus = application.webInterviewResearch?.preparationFocus.first {
            return "Build one concise story around \(focus.lowercased()): context, decision, tradeoff, and measurable outcome."
        }

        if let theme = semanticThemes(for: application, limit: 1).first {
            return "Anchor your strongest example in \(theme.lowercased()) and keep the story tight: context, decision, tradeoff, and measurable outcome."
        }

        return "Keep your stories tight: context, decision, tradeoff, and measurable outcome."
    }

    private func weeklyHistory(for category: ExpenseCategory, weeks: Int) -> [Double] {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        return (0..<weeks).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1 - offset), to: currentWeekStart),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart)
            else {
                return nil
            }

            return expenseStore.expenses
                .filter { $0.category == category && interval.contains($0.date) }
                .reduce(0) { $0 + $1.amount }
        }
    }

    private func blendedForecast(for series: [Double]) -> Double {
        let cleaned = series.filter { !$0.isNaN && !$0.isInfinite }
        guard !cleaned.isEmpty else { return 0 }

        let regression = linearRegressionForecast(for: cleaned)
        let trailingAverage = cleaned.suffix(min(4, cleaned.count)).average
        let lastObserved = cleaned.last ?? trailingAverage

        return max((regression * 0.5) + (trailingAverage * 0.35) + (lastObserved * 0.15), 0)
    }

    private func linearRegressionForecast(for series: [Double]) -> Double {
        guard series.count > 1 else { return series.first ?? 0 }

        let xValues = series.indices.map(Double.init)
        let yValues = series
        let xMean = xValues.average
        let yMean = yValues.average

        let numerator = zip(xValues, yValues).reduce(0.0) { partialResult, pair in
            partialResult + ((pair.0 - xMean) * (pair.1 - yMean))
        }
        let denominator = xValues.reduce(0.0) { partialResult, value in
            partialResult + pow(value - xMean, 2)
        }

        guard denominator != 0 else { return yMean }

        let slope = numerator / denominator
        let intercept = yMean - (slope * xMean)
        let nextX = Double(series.count)
        return max((slope * nextX) + intercept, 0)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.average
        let variance = values.reduce(0.0) { partialResult, value in
            partialResult + pow(value - mean, 2)
        } / Double(values.count)
        return sqrt(variance)
    }

    private func extractedTags(from text: String, fallback: String) -> [String] {
        let normalized = normalizedText([text])
        guard !normalized.isEmpty else { return [fallback] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = normalized

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        var tags: [String] = []

        tagger.enumerateTags(
            in: normalized.startIndex..<normalized.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, range in
            guard let tag else { return true }

            if tag == .noun || tag == .adjective {
                let token = String(normalized[range]).capitalized
                if token.count > 2, !Self.tagStopwords.contains(token.lowercased()) {
                    tags.append(token)
                }
            }

            return true
        }

        if tags.isEmpty {
            tags.append(fallback)
        }

        return tags.uniqued()
    }

    private func savingActions(for category: ExpenseCategory, amount: Double, label: String) -> [String] {
        switch category {
        case .food:
            return [
                "Batch meals around interview-heavy days so convenience spends drop.",
                "Replace one cafe spend with groceries this week to protect runway.",
            ]
        case .transport:
            return [
                "Bundle travel into fewer days and avoid fragmented commute costs.",
                "Review whether remote calls can replace one trip this week.",
            ]
        case .networking:
            return [
                "Prioritize one high-signal conversation over several low-signal meetups.",
                "Use async follow-ups when live meetings are not essential.",
            ]
        case .software:
            return [
                "Pause tools that are not directly supporting applications or interviews.",
                "Consolidate overlapping subscriptions before the next billing cycle.",
            ]
        case .health:
            return [
                "Protect health essentials first, then look for savings in lower-priority categories.",
                "Keep this category stable and trim elsewhere if runway tightens.",
            ]
        case .essentials:
            return [
                "Treat essentials as the floor and absorb savings from discretionary categories instead.",
                "Use this as the fixed baseline when planning the next week.",
            ]
        }
    }

    private func adaptiveExpenseTrainingExamples() -> [ExpenseTrainingExample] {
        let calendar = Calendar.current
        let now = Date()
        let recentExpenses = expenseStore.expenses
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(160)

        var examples = recentExpenses.compactMap { expense -> ExpenseTrainingExample? in
            let text = normalizedText([
                expense.label,
                expense.notes,
                expense.tags.joined(separator: " "),
                expense.category.title,
            ])
            guard !text.isEmpty else { return nil }

            let daysAgo = Double(max(calendar.dateComponents([.day], from: expense.updatedAt, to: now).day ?? 0, 0))
            let weight = max(0.45, 1.45 - min(daysAgo / 45, 0.95))
            return ExpenseTrainingExample(category: expense.category, text: text, weight: weight)
        }

        let groupedByCategory = Dictionary(grouping: recentExpenses, by: \.category)
        for category in ExpenseCategory.allCases {
            let learnedTerms = (groupedByCategory[category] ?? []).flatMap { expense in
                [expense.label, expense.notes, expense.tags.joined(separator: " ")]
            }
            let anchor = normalizedText([category.title] + learnedTerms)
            let anchorText = anchor.isEmpty ? category.title : anchor
            let anchorWeight = learnedTerms.isEmpty ? 0.25 : 0.7
            examples.append(ExpenseTrainingExample(category: category, text: anchorText, weight: anchorWeight))
        }

        return examples
    }

    private func learnedCompanyProfiles(excluding currentCompany: String) -> [AdaptiveCompanyProfile] {
        Dictionary(grouping: jobStore.applications, by: { $0.companyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            .compactMap { _, applications in
                guard let canonical = applications.max(by: { $0.updatedAt < $1.updatedAt })?.companyName else {
                    return nil
                }
                guard canonical.caseInsensitiveCompare(currentCompany) != .orderedSame else {
                    return nil
                }

                let profile = normalizedText(applications.flatMap { application in
                    [
                        application.companyName,
                        application.role,
                        application.notes,
                        application.feedback,
                        application.priority,
                        application.location,
                        application.tags.joined(separator: " "),
                        application.webInterviewResearch?.summary ?? "",
                        application.webInterviewResearch?.hiringSignals.joined(separator: " ") ?? "",
                        application.webInterviewResearch?.preparationFocus.joined(separator: " ") ?? "",
                        application.webInterviewResearch?.likelyQuestions.joined(separator: " ") ?? "",
                    ]
                })

                guard !profile.isEmpty else { return nil }
                return AdaptiveCompanyProfile(company: canonical, profile: profile)
            }
    }

    private func fallbackRelatedCompanies(from application: JobApplication) -> [String] {
        guard let research = application.webInterviewResearch else { return [] }

        return research.sources
            .compactMap { source -> String? in
                guard
                    let host = URL(string: source.url)?.host?.lowercased()
                        .replacingOccurrences(of: "www.", with: ""),
                    let firstLabel = host.split(separator: ".").first
                else {
                    return nil
                }

                let candidate = String(firstLabel)
                guard
                    candidate.count > 2,
                    candidate.caseInsensitiveCompare(application.companyName) != .orderedSame
                else {
                    return nil
                }

                return candidate.capitalized
            }
            .uniqued()
    }

    private func jobQuery(for application: JobApplication) -> String {
        normalizedText([
            application.companyName,
            application.role,
            application.notes,
            application.feedback,
            application.priority,
            application.location,
            application.tags.joined(separator: " ")
        ])
    }

    private func semanticThemes(for application: JobApplication, limit: Int) -> [String] {
        semanticThemes(
            from: [
                application.role,
                application.notes,
                application.feedback,
                application.tags.joined(separator: " "),
                application.webInterviewResearch?.summary ?? "",
                application.webInterviewResearch?.hiringSignals.joined(separator: " ") ?? "",
                application.webInterviewResearch?.preparationFocus.joined(separator: " ") ?? "",
            ]
            .joined(separator: " "),
            limit: limit
        )
    }

    private func semanticThemes(from text: String, limit: Int) -> [String] {
        let normalized = normalizedText([text])
        guard !normalized.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = normalized

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        var tokenWeights: [String: Double] = [:]

        tagger.enumerateTags(
            in: normalized.startIndex..<normalized.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, range in
            guard let tag else { return true }
            guard tag == .noun || tag == .adjective else { return true }

            let token = String(normalized[range])
            guard token.count > 2, !Self.tagStopwords.contains(token) else { return true }
            tokenWeights[token, default: 0] += tag == .noun ? 1.35 : 0.95
            return true
        }

        if tokenWeights.isEmpty {
            return normalized
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 && !Self.tagStopwords.contains($0) }
                .prefix(limit)
                .map { $0.capitalized }
        }

        return tokenWeights
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { $0.key.capitalized }
    }

    private func jobSuggestionSignature(
        for application: JobApplication,
        companyUniverseSignature: String
    ) -> String {
        let researchSignature = application.webInterviewResearch.map {
            [
                $0.generatedAt.formatted(.iso8601),
                $0.summary,
                $0.likelyQuestions.joined(separator: "|"),
                $0.preparationFocus.joined(separator: "|"),
            ].joined(separator: "::")
        } ?? "none"

        return [
            companyUniverseSignature,
            application.companyName.lowercased(),
            application.role.lowercased(),
            application.notes.lowercased(),
            application.feedback.lowercased(),
            application.priority.lowercased(),
            application.location.lowercased(),
            application.tags.sorted().joined(separator: "|").lowercased(),
            researchSignature,
        ].joined(separator: "||")
    }

    private func similarityScore(between lhs: String, and rhs: String) -> Double {
        let left = normalizedText([lhs])
        let right = normalizedText([rhs])

        guard !left.isEmpty, !right.isEmpty else { return 0 }

        if let sentenceEmbedding {
            let distance = sentenceEmbedding.distance(between: left, and: right)
            if distance.isFinite {
                return 1 / (1 + distance)
            }
        }

        return lexicalSimilarity(between: left, and: right)
    }

    private func lexicalSimilarity(between lhs: String, and rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        let intersection = lhsTokens.intersection(rhsTokens)
        let union = lhsTokens.union(rhsTokens)

        guard !union.isEmpty else { return 0 }
        return Double(intersection.count) / Double(union.count)
    }

    private func normalizedText(_ components: [String]) -> String {
        components
            .joined(separator: " ")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func persistResearchPreferences() {
        persistence.save(
            GeminiResearchPreferenceSnapshot(isEnabled: isWebInterviewResearchEnabled),
            forKey: researchPreferenceStorageKey
        )
    }
}

private extension AIInsightService {
    struct ExpenseInsightInput: Hashable {
        let dashboardSnapshot: ExpenseDashboardSnapshot
        let analyticsSummary: ExpenseAnalyticsSummary
    }

    struct JobInsightInput: Hashable {
        let signature: String
        let companyUniverseSignature: String
        let applications: [JobApplication]

        static func == (lhs: JobInsightInput, rhs: JobInsightInput) -> Bool {
            lhs.signature == rhs.signature
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(signature)
        }

        static let empty = JobInsightInput(
            signature: "",
            companyUniverseSignature: "",
            applications: []
        )
    }

    struct ExpenseInsightOutput {
        let recommendedDailyBudget: Double
        let budgetRecommendations: [BudgetRecommendation]
        let spendingAlerts: [AISpendingAlert]
    }

    struct JobInsightOutput {
        let suggestions: [UUID: AIJobSuggestion]
        let signatures: [UUID: String]
    }

    struct ExpenseTrainingExample {
        let category: ExpenseCategory
        let text: String
        let weight: Double

        init(category: ExpenseCategory, text: String, weight: Double = 1.0) {
            self.category = category
            self.text = text
            self.weight = weight
        }
    }

    struct AdaptiveCompanyProfile {
        let company: String
        let profile: String
    }

    struct RankedValue<Value> {
        let value: Value
        let score: Double
    }

    static let tagStopwords: Set<String> = [
        "with", "from", "that", "this", "your", "about", "into", "over", "under",
        "role", "company", "today", "week", "more", "high", "soon", "team", "work",
        "show", "used", "using", "need", "needs", "good", "best", "strong", "still",
        "then", "than", "after", "before", "where", "when", "while", "make", "made",
        "have", "just", "very", "most", "some", "only", "also", "their", "there"
    ]
}

private extension Collection where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
