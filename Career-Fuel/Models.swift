import Foundation

enum AppMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case jobSearch = "job_search"
    case employed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobSearch:
            return "Job Search"
        case .employed:
            return "Employed"
        }
    }

    var symbol: String {
        switch self {
        case .jobSearch:
            return "briefcase.fill"
        case .employed:
            return "checkmark.seal.fill"
        }
    }
}

enum StatusTone: String, Codable, CaseIterable, Identifiable {
    case info
    case success
    case warning
    case danger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info:
            return "Info"
        case .success:
            return "Success"
        case .warning:
            return "Warning"
        case .danger:
            return "Danger"
        }
    }
}

enum JobStageKind: String, Codable, CaseIterable, Hashable {
    case saved
    case applied
    case interview
    case offer
    case accepted
    case custom

    var isLivePipelineStage: Bool {
        switch self {
        case .applied, .interview, .offer:
            return true
        case .saved, .accepted, .custom:
            return false
        }
    }

    static func inferred(from title: String) -> JobStageKind {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("offer accepted")
            || normalized.contains("accepted offer")
            || normalized.contains("accepted role")
            || normalized.contains("role accepted")
            || normalized.contains("hired")
            || normalized.contains("joined")
        {
            return .accepted
        }

        if normalized == "saved" || normalized.contains("saved") || normalized.contains("wishlist") {
            return .saved
        }

        if normalized == "applied" || normalized.contains("applied") || normalized.contains("submitted") {
            return .applied
        }

        if normalized.contains("interview")
            || normalized.contains("screen")
            || normalized.contains("recruiter")
            || normalized.contains("onsite")
        {
            return .interview
        }

        if normalized == "offer" || normalized.contains("offer") || normalized.contains("negotiat") {
            return .offer
        }

        return .custom
    }
}

struct JobStage: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var subtitle: String
    var tone: StatusTone
    var kind: JobStageKind
    var order: Int
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case tone
        case kind
        case order
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        tone: StatusTone,
        kind: JobStageKind? = nil,
        order: Int,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.kind = kind ?? JobStageKind.inferred(from: title)
        self.order = order
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        tone = try container.decode(StatusTone.self, forKey: .tone)
        kind = try container.decodeIfPresent(JobStageKind.self, forKey: .kind) ?? JobStageKind.inferred(from: title)
        order = try container.decode(Int.self, forKey: .order)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(tone, forKey: .tone)
        try container.encode(kind, forKey: .kind)
        try container.encode(order, forKey: .order)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

enum JobTimelineEventKind: String, Codable, Hashable, CaseIterable {
    case created
    case stageChange
    case followUp
    case feedback
    case statusUpdate

    var symbol: String {
        switch self {
        case .created:
            return "plus.circle.fill"
        case .stageChange:
            return "arrow.triangle.swap"
        case .followUp:
            return "paperplane.fill"
        case .feedback:
            return "quote.bubble.fill"
        case .statusUpdate:
            return "text.bubble.fill"
        }
    }
}

struct JobTimelineEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: JobTimelineEventKind
    var date: Date
    var title: String
    var detail: String

    init(
        id: UUID = UUID(),
        kind: JobTimelineEventKind,
        date: Date = Date(),
        title: String,
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.detail = detail
    }
}

struct JobApplication: Identifiable, Codable, Hashable {
    let id: UUID
    var companyName: String
    var role: String
    var stageID: UUID
    var dateApplied: Date
    var notes: String
    var feedback: String
    var priority: String
    var location: String
    var statusNote: String
    var lastContactDate: Date?
    var stageEnteredAt: Date
    var timeline: [JobTimelineEvent]
    var tags: [String]
    var webInterviewResearch: WebInterviewResearch?
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case companyName
        case role
        case stageID
        case dateApplied
        case notes
        case feedback
        case priority
        case location
        case statusNote
        case lastContactDate
        case stageEnteredAt
        case timeline
        case tags
        case webInterviewResearch
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        companyName: String,
        role: String,
        stageID: UUID,
        dateApplied: Date,
        notes: String,
        feedback: String = "",
        priority: String = "Standard",
        location: String = "Remote",
        statusNote: String = "Updated today",
        lastContactDate: Date? = nil,
        stageEnteredAt: Date? = nil,
        timeline: [JobTimelineEvent] = [],
        tags: [String] = [],
        webInterviewResearch: WebInterviewResearch? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyName = companyName
        self.role = role
        self.stageID = stageID
        self.dateApplied = dateApplied
        self.notes = notes
        self.feedback = feedback
        self.priority = priority
        self.location = location
        self.statusNote = statusNote
        self.lastContactDate = lastContactDate
        self.stageEnteredAt = stageEnteredAt ?? dateApplied
        self.timeline = timeline
        self.tags = tags
        self.webInterviewResearch = webInterviewResearch
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        companyName = try container.decode(String.self, forKey: .companyName)
        role = try container.decode(String.self, forKey: .role)
        stageID = try container.decode(UUID.self, forKey: .stageID)
        dateApplied = try container.decode(Date.self, forKey: .dateApplied)
        notes = try container.decode(String.self, forKey: .notes)
        feedback = try container.decode(String.self, forKey: .feedback)
        priority = try container.decode(String.self, forKey: .priority)
        location = try container.decode(String.self, forKey: .location)
        statusNote = try container.decode(String.self, forKey: .statusNote)
        lastContactDate = try container.decodeIfPresent(Date.self, forKey: .lastContactDate)
        stageEnteredAt = try container.decodeIfPresent(Date.self, forKey: .stageEnteredAt) ?? dateApplied
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        webInterviewResearch = try container.decodeIfPresent(WebInterviewResearch.self, forKey: .webInterviewResearch)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? dateApplied
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        timeline = try container.decodeIfPresent([JobTimelineEvent].self, forKey: .timeline)
            ?? [
                JobTimelineEvent(
                    kind: .created,
                    date: createdAt,
                    title: "Application created",
                    detail: "Started tracking \(companyName) for \(role)."
                )
            ]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(companyName, forKey: .companyName)
        try container.encode(role, forKey: .role)
        try container.encode(stageID, forKey: .stageID)
        try container.encode(dateApplied, forKey: .dateApplied)
        try container.encode(notes, forKey: .notes)
        try container.encode(feedback, forKey: .feedback)
        try container.encode(priority, forKey: .priority)
        try container.encode(location, forKey: .location)
        try container.encode(statusNote, forKey: .statusNote)
        try container.encode(lastContactDate, forKey: .lastContactDate)
        try container.encode(stageEnteredAt, forKey: .stageEnteredAt)
        try container.encode(timeline, forKey: .timeline)
        try container.encode(tags, forKey: .tags)
        try container.encode(webInterviewResearch, forKey: .webInterviewResearch)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct JobApplicationDraft {
    var companyName: String
    var role: String
    var stageID: UUID
    var dateApplied: Date
    var notes: String
    var feedback: String
    var priority: String
    var location: String
    var statusNote: String
    var lastContactDate: Date?
    var tags: [String]

    init(
        companyName: String = "",
        role: String = "",
        stageID: UUID,
        dateApplied: Date = Date(),
        notes: String = "",
        feedback: String = "",
        priority: String = "Standard",
        location: String = "Remote",
        statusNote: String = "Updated today",
        lastContactDate: Date? = nil,
        tags: [String] = []
    ) {
        self.companyName = companyName
        self.role = role
        self.stageID = stageID
        self.dateApplied = dateApplied
        self.notes = notes
        self.feedback = feedback
        self.priority = priority
        self.location = location
        self.statusNote = statusNote
        self.lastContactDate = lastContactDate
        self.tags = tags
    }

    init(application: JobApplication) {
        companyName = application.companyName
        role = application.role
        stageID = application.stageID
        dateApplied = application.dateApplied
        notes = application.notes
        feedback = application.feedback
        priority = application.priority
        location = application.location
        statusNote = application.statusNote
        lastContactDate = application.lastContactDate
        tags = application.tags
    }
}

struct Expense: Identifiable, Codable, Hashable {
    let id: UUID
    var category: ExpenseCategory
    var label: String
    var amount: Double
    var date: Date
    var notes: String
    var tags: [String]
    var recurringPlanID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        category: ExpenseCategory,
        label: String,
        amount: Double,
        date: Date,
        notes: String = "",
        tags: [String] = [],
        recurringPlanID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.label = label
        self.amount = amount
        self.date = date
        self.notes = notes
        self.tags = tags
        self.recurringPlanID = recurringPlanID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ExpenseDraft {
    var category: ExpenseCategory
    var label: String
    var amount: Double
    var date: Date
    var notes: String
    var tags: [String]

    init(
        category: ExpenseCategory = .food,
        label: String = "",
        amount: Double = 0,
        date: Date = Date(),
        notes: String = "",
        tags: [String] = []
    ) {
        self.category = category
        self.label = label
        self.amount = amount
        self.date = date
        self.notes = notes
        self.tags = tags
    }

    init(expense: Expense) {
        category = expense.category
        label = expense.label
        amount = expense.amount
        date = expense.date
        notes = expense.notes
        tags = expense.tags
    }
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case essentials
    case food
    case transport
    case networking
    case software
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .essentials:
            return "Essentials"
        case .food:
            return "Food"
        case .transport:
            return "Transport"
        case .networking:
            return "Networking"
        case .software:
            return "Software"
        case .health:
            return "Health"
        }
    }

    var symbol: String {
        switch self {
        case .essentials:
            return "house.fill"
        case .food:
            return "fork.knife"
        case .transport:
            return "car.fill"
        case .networking:
            return "person.2.fill"
        case .software:
            return "laptopcomputer"
        case .health:
            return "cross.case.fill"
        }
    }
}

enum RecurringExpenseFrequency: String, Codable, CaseIterable, Identifiable, Hashable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }

    var scheduleLabel: String {
        switch self {
        case .daily:
            return "Repeats daily"
        case .weekly:
            return "Repeats weekly"
        case .monthly:
            return "Repeats monthly"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .daily:
            return .day
        case .weekly:
            return .weekOfYear
        case .monthly:
            return .month
        }
    }
}

struct RecurringExpensePlan: Identifiable, Codable, Hashable {
    let id: UUID
    var category: ExpenseCategory
    var label: String
    var amount: Double
    var startDate: Date
    var notes: String
    var tags: [String]
    var frequency: RecurringExpenseFrequency
    var isActive: Bool
    var lastGeneratedDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        category: ExpenseCategory,
        label: String,
        amount: Double,
        startDate: Date,
        notes: String = "",
        tags: [String] = [],
        frequency: RecurringExpenseFrequency,
        isActive: Bool = true,
        lastGeneratedDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.label = label
        self.amount = amount
        self.startDate = startDate
        self.notes = notes
        self.tags = tags
        self.frequency = frequency
        self.isActive = isActive
        self.lastGeneratedDate = lastGeneratedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ExpenseInputIntegrityIssue: String, Hashable {
    case aggregatedSummary

    var message: String {
        switch self {
        case .aggregatedSummary:
            return "Enter each expense as a single transaction. Weekly or monthly totals will distort burn rate and runway."
        }
    }
}

struct DashboardInsight: Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
    let tone: StatusTone
    let symbol: String
    let priority: String

    init(
        id: String = UUID().uuidString,
        title: String,
        message: String,
        tone: StatusTone,
        symbol: String,
        priority: String
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.tone = tone
        self.symbol = symbol
        self.priority = priority
    }
}

struct DailyExpensePoint: Identifiable, Hashable {
    let date: Date
    let amount: Double

    var id: Date { date }
}

struct WeeklySpendPoint: Identifiable, Hashable {
    let weekStart: Date
    let amount: Double

    var id: Date { weekStart }
}

struct MonthlySpendPoint: Identifiable, Hashable {
    let monthStart: Date
    let amount: Double

    var id: Date { monthStart }
}

struct ApplicationStagePoint: Identifiable, Hashable {
    let stageID: UUID
    let stageTitle: String
    let tone: StatusTone
    let count: Int

    var id: UUID { stageID }
}

struct DeletionTombstone: Identifiable, Codable, Hashable {
    let id: UUID
    var deletedAt: Date
}

struct JobStoreSnapshot: Codable {
    var stages: [JobStage]
    var applications: [JobApplication]
    var weeklyApplicationTarget: Int
    var deletedStageTombstones: [DeletionTombstone]
    var deletedApplicationTombstones: [DeletionTombstone]
    var selectedApplicationID: UUID?
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case stages
        case applications
        case weeklyApplicationTarget
        case deletedStageTombstones
        case deletedApplicationTombstones
        case selectedApplicationID
        case updatedAt
    }

    init(
        stages: [JobStage],
        applications: [JobApplication],
        weeklyApplicationTarget: Int,
        deletedStageTombstones: [DeletionTombstone],
        deletedApplicationTombstones: [DeletionTombstone],
        selectedApplicationID: UUID?,
        updatedAt: Date
    ) {
        self.stages = stages
        self.applications = applications
        self.weeklyApplicationTarget = weeklyApplicationTarget
        self.deletedStageTombstones = deletedStageTombstones
        self.deletedApplicationTombstones = deletedApplicationTombstones
        self.selectedApplicationID = selectedApplicationID
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stages = try container.decode([JobStage].self, forKey: .stages)
        applications = try container.decode([JobApplication].self, forKey: .applications)
        weeklyApplicationTarget = max(try container.decodeIfPresent(Int.self, forKey: .weeklyApplicationTarget) ?? 5, 1)
        deletedStageTombstones = try container.decode([DeletionTombstone].self, forKey: .deletedStageTombstones)
        deletedApplicationTombstones = try container.decode([DeletionTombstone].self, forKey: .deletedApplicationTombstones)
        selectedApplicationID = try container.decodeIfPresent(UUID.self, forKey: .selectedApplicationID)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stages, forKey: .stages)
        try container.encode(applications, forKey: .applications)
        try container.encode(weeklyApplicationTarget, forKey: .weeklyApplicationTarget)
        try container.encode(deletedStageTombstones, forKey: .deletedStageTombstones)
        try container.encode(deletedApplicationTombstones, forKey: .deletedApplicationTombstones)
        try container.encode(selectedApplicationID, forKey: .selectedApplicationID)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct ExpenseStoreSnapshot: Codable {
    var startingBalance: Double
    var monthlyIncome: Double
    var expenses: [Expense]
    var recurringPlans: [RecurringExpensePlan]
    var deletedExpenseTombstones: [DeletionTombstone]
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case startingBalance
        case monthlyIncome
        case expenses
        case recurringPlans
        case deletedExpenseTombstones
        case updatedAt
    }

    init(
        startingBalance: Double,
        monthlyIncome: Double,
        expenses: [Expense],
        recurringPlans: [RecurringExpensePlan],
        deletedExpenseTombstones: [DeletionTombstone],
        updatedAt: Date
    ) {
        self.startingBalance = startingBalance
        self.monthlyIncome = monthlyIncome
        self.expenses = expenses
        self.recurringPlans = recurringPlans
        self.deletedExpenseTombstones = deletedExpenseTombstones
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startingBalance = try container.decode(Double.self, forKey: .startingBalance)
        monthlyIncome = try container.decodeIfPresent(Double.self, forKey: .monthlyIncome) ?? 0
        expenses = try container.decode([Expense].self, forKey: .expenses)
        recurringPlans = try container.decodeIfPresent([RecurringExpensePlan].self, forKey: .recurringPlans) ?? []
        deletedExpenseTombstones = try container.decode([DeletionTombstone].self, forKey: .deletedExpenseTombstones)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startingBalance, forKey: .startingBalance)
        try container.encode(monthlyIncome, forKey: .monthlyIncome)
        try container.encode(expenses, forKey: .expenses)
        try container.encode(recurringPlans, forKey: .recurringPlans)
        try container.encode(deletedExpenseTombstones, forKey: .deletedExpenseTombstones)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct ExpenseDashboardSnapshot: Hashable {
    var totalSpent: Double
    var currentBalance: Double
    var observedExpenseDays: Int
    var trackedCalendarDays: Int
    var threeDayAverage: Double
    var sevenDayAverage: Double
    var thirtyDayAverage: Double
    var weightedDailyBurnRate: Double
    var weeklySpending: Double
    var dailyBurnRate: Double
    var activeDailySpendRate: Double
    var burnRateConfidence: BurnRateConfidence
    var spendingTrend: SpendingTrend
    var spendingAnomaly: SpendingAnomaly?
    var daysLeft: Int
    var projectedZeroDate: Date
    var sevenDayTrend: [DailyExpensePoint]
    var spendingFrequency: Double
    var spenderBehavior: SpenderBehavior

    static let empty = ExpenseDashboardSnapshot(
        totalSpent: 0,
        currentBalance: 0,
        observedExpenseDays: 0,
        trackedCalendarDays: 0,
        threeDayAverage: 0,
        sevenDayAverage: 0,
        thirtyDayAverage: 0,
        weightedDailyBurnRate: 0,
        weeklySpending: 0,
        dailyBurnRate: 0,
        activeDailySpendRate: 0,
        burnRateConfidence: .insufficient,
        spendingTrend: .stable,
        spendingAnomaly: nil,
        daysLeft: 0,
        projectedZeroDate: Date(),
        sevenDayTrend: [],
        spendingFrequency: 0,
        spenderBehavior: .mixed
    )
}

struct ExpenseAnalyticsSummary: Hashable {
    var weeklySpendHistory: [WeeklySpendPoint]
    var monthlySpendHistory: [MonthlySpendPoint]
    var spendByCategory7Days: [ExpenseCategory: Double]
    var spendByCategory28Days: [ExpenseCategory: Double]

    static let empty = ExpenseAnalyticsSummary(
        weeklySpendHistory: [],
        monthlySpendHistory: [],
        spendByCategory7Days: [:],
        spendByCategory28Days: [:]
    )
}

enum RunwayInsightState: String, Codable, Hashable {
    case setup
    case safe
    case warning
    case critical
}

enum SpendingTrend: String, Codable, Hashable {
    case increasing
    case decreasing
    case stable

    var title: String {
        switch self {
        case .increasing:
            return "Increasing"
        case .decreasing:
            return "Decreasing"
        case .stable:
            return "Stable"
        }
    }

    var symbol: String {
        switch self {
        case .increasing:
            return "chart.line.uptrend.xyaxis"
        case .decreasing:
            return "chart.line.downtrend.xyaxis"
        case .stable:
            return "waveform.path.ecg"
        }
    }

    var tone: StatusTone {
        switch self {
        case .increasing:
            return .warning
        case .decreasing:
            return .success
        case .stable:
            return .info
        }
    }

    var predictiveAdjustmentMultiplier: Double {
        switch self {
        case .increasing:
            return 1.1
        case .decreasing:
            return 0.9
        case .stable:
            return 1
        }
    }
}

enum BurnRateConfidence: String, Codable, Hashable {
    case insufficient
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .insufficient:
            return "Not enough data"
        case .low:
            return "Low confidence"
        case .medium:
            return "Medium confidence"
        case .high:
            return "High confidence"
        }
    }

    var tone: StatusTone {
        switch self {
        case .insufficient:
            return .warning
        case .low:
            return .warning
        case .medium:
            return .info
        case .high:
            return .success
        }
    }
}

enum SpenderBehavior: String, Codable, Hashable {
    case daily      // frequency > 0.7
    case irregular  // frequency < 0.3
    case mixed      // 0.3 ... 0.7

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .irregular:
            return "Irregular"
        case .mixed:
            return "Mixed"
        }
    }

    var displayLabel: String {
        switch self {
        case .daily:
            return "daily pattern"
        case .irregular:
            return "irregular pattern"
        case .mixed:
            return "mixed pattern"
        }
    }
}

struct SpendingAnomaly: Hashable {
    var date: Date
    var amount: Double
    var title: String
    var message: String
    var tone: StatusTone
}

struct ExpenseInsightSnapshot: Hashable {
    var runwayState: RunwayInsightState
    var observedExpenseDays: Int
    var trackedCalendarDays: Int
    var burnRateConfidence: BurnRateConfidence
    var survivalDailyBurnRate: Double
    var activeDailySpendRate: Double
    var spendingTrend: SpendingTrend
    var spendingAnomaly: SpendingAnomaly?

    static let empty = ExpenseInsightSnapshot(
        runwayState: .setup,
        observedExpenseDays: 0,
        trackedCalendarDays: 0,
        burnRateConfidence: .insufficient,
        survivalDailyBurnRate: 0,
        activeDailySpendRate: 0,
        spendingTrend: .stable,
        spendingAnomaly: nil
    )
}

struct PipelineHealthSnapshot: Hashable {
    var score: Int
    var tone: StatusTone
    var label: String
    var message: String

    static let empty = PipelineHealthSnapshot(
        score: 0,
        tone: .warning,
        label: "Needs Build",
        message: "Add more live applications and recent activity to strengthen the pipeline."
    )
}

struct JobConversionSnapshot: Hashable {
    var submittedApplicationsCount: Int
    var interviewsReachedCount: Int
    var offersReachedCount: Int
    var applicationToInterviewRate: Int
    var interviewToOfferRate: Int

    static let empty = JobConversionSnapshot(
        submittedApplicationsCount: 0,
        interviewsReachedCount: 0,
        offersReachedCount: 0,
        applicationToInterviewRate: 0,
        interviewToOfferRate: 0
    )
}

struct JobDecisionSnapshot: Hashable {
    var totalApplicationsCount: Int
    var activeApplicationsCount: Int
    var interviewCount: Int
    var offerCount: Int
    var acceptedCount: Int
    var weeklyApplicationTarget: Int
    var weeklyApplicationsProgress: Int
    var followUpDueCount: Int
    var staleApplicationsCount: Int
    var highPriorityStaleCount: Int
    var pipelineHealth: PipelineHealthSnapshot
    var conversions: JobConversionSnapshot

    static let empty = JobDecisionSnapshot(
        totalApplicationsCount: 0,
        activeApplicationsCount: 0,
        interviewCount: 0,
        offerCount: 0,
        acceptedCount: 0,
        weeklyApplicationTarget: 5,
        weeklyApplicationsProgress: 0,
        followUpDueCount: 0,
        staleApplicationsCount: 0,
        highPriorityStaleCount: 0,
        pipelineHealth: .empty,
        conversions: .empty
    )
}

struct AcceptedEmployment: Hashable {
    var applicationID: UUID
    var companyName: String
    var role: String
    var stageTitle: String
    var startDate: Date
    var updatedAt: Date
}

struct EmploymentStatusSnapshot: Hashable {
    var acceptedEmployment: AcceptedEmployment?

    static let empty = EmploymentStatusSnapshot(acceptedEmployment: nil)
}

struct JobInsightSnapshot: Hashable {
    var jobsNeeded: Int
    var weeklyApplicationTarget: Int
    var weeklyApplicationsProgress: Int
    var followUpDueCount: Int
    var staleApplicationsCount: Int
    var highPriorityStaleCount: Int
    var pipelineHealthScore: Int

    static let empty = JobInsightSnapshot(
        jobsNeeded: 10,
        weeklyApplicationTarget: 5,
        weeklyApplicationsProgress: 0,
        followUpDueCount: 0,
        staleApplicationsCount: 0,
        highPriorityStaleCount: 0,
        pipelineHealthScore: 0
    )
}

struct EmploymentFinancialSnapshot: Hashable {
    var monthlyIncome: Double
    var monthlyExpenseEstimate: Double
    var monthlyProjectionObservedDays: Int
    var monthlyProjectionConfidence: BurnRateConfidence
    var monthlySavingsCapacity: Double
    var savingsRate: Double
    var emergencyFundTarget: Double
    var emergencyFundProgress: Double
    var runwayIfUnemployedAgainDays: Int
    var stabilityTone: StatusTone
    var stabilityLabel: String
    var stabilityMessage: String
    var spendingFrequency: Double
    var spenderBehavior: SpenderBehavior

    static let empty = EmploymentFinancialSnapshot(
        monthlyIncome: 0,
        monthlyExpenseEstimate: 0,
        monthlyProjectionObservedDays: 0,
        monthlyProjectionConfidence: .insufficient,
        monthlySavingsCapacity: 0,
        savingsRate: 0,
        emergencyFundTarget: 1,
        emergencyFundProgress: 0,
        runwayIfUnemployedAgainDays: 0,
        stabilityTone: .warning,
        stabilityLabel: "Income Missing",
        stabilityMessage: "Set your monthly take-home pay to switch from survival tracking into stability planning.",
        spendingFrequency: 0,
        spenderBehavior: .mixed
    )
}

struct JobAnalyticsSummary: Hashable {
    var pipelinePoints: [ApplicationStagePoint]
    var timeToHireEstimate: Int
    var hiringLikelihood: Int
    var weeklyTargetProgress: Int
    var weeklyTarget: Int
    var staleApplicationsCount: Int
    var followUpDueCount: Int
    var conversions: JobConversionSnapshot

    static let empty = JobAnalyticsSummary(
        pipelinePoints: [],
        timeToHireEstimate: 12,
        hiringLikelihood: 0,
        weeklyTargetProgress: 0,
        weeklyTarget: 5,
        staleApplicationsCount: 0,
        followUpDueCount: 0,
        conversions: .empty
    )
}

struct CloudSyncEnvelope: Codable {
    var jobSnapshot: JobStoreSnapshot
    var expenseSnapshot: ExpenseStoreSnapshot
    var updatedAt: Date
    var deviceID: String
}

struct CloudSyncPreferenceSnapshot: Codable {
    var isEnabled: Bool
    var lastSyncAt: Date?
    var hasPendingChanges: Bool
}

struct NotificationPreferenceSnapshot: Codable {
    var isEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var lastRunwayThreshold: Int?
    var lastOverspendingSignature: String
    var lastSuggestionSignature: String

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case reminderHour
        case reminderMinute
        case lastRunwayThreshold
        case lastOverspendingSignature
        case lastSuggestionSignature
    }

    init(
        isEnabled: Bool,
        reminderHour: Int = 20,
        reminderMinute: Int = 0,
        lastRunwayThreshold: Int?,
        lastOverspendingSignature: String,
        lastSuggestionSignature: String
    ) {
        self.isEnabled = isEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.lastRunwayThreshold = lastRunwayThreshold
        self.lastOverspendingSignature = lastOverspendingSignature
        self.lastSuggestionSignature = lastSuggestionSignature
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 20
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        lastRunwayThreshold = try container.decodeIfPresent(Int.self, forKey: .lastRunwayThreshold)
        lastOverspendingSignature = try container.decodeIfPresent(String.self, forKey: .lastOverspendingSignature) ?? ""
        lastSuggestionSignature = try container.decodeIfPresent(String.self, forKey: .lastSuggestionSignature) ?? ""
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(reminderHour, forKey: .reminderHour)
        try container.encode(reminderMinute, forKey: .reminderMinute)
        try container.encodeIfPresent(lastRunwayThreshold, forKey: .lastRunwayThreshold)
        try container.encode(lastOverspendingSignature, forKey: .lastOverspendingSignature)
        try container.encode(lastSuggestionSignature, forKey: .lastSuggestionSignature)
    }
}

struct AIExpenseSuggestion: Hashable {
    let suggestedCategory: ExpenseCategory
    let confidence: Double
    let tags: [String]
    let savingActions: [String]
}

struct InterviewResearchSource: Identifiable, Codable, Hashable {
    var id: String { url }
    let title: String
    let url: String
}

struct WebInterviewResearch: Codable, Hashable {
    let summary: String
    let hiringSignals: [String]
    let likelyQuestions: [String]
    let preparationFocus: [String]
    let sources: [InterviewResearchSource]
    let generatedAt: Date
    let model: String
}

struct AISpendingAlert: Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
    let tone: StatusTone
    let symbol: String
    let category: ExpenseCategory?
    let dedupeKey: String
}

struct BudgetRecommendation: Identifiable, Hashable {
    let id: String
    let category: ExpenseCategory
    let weeklyLimit: Double
    let rationale: String
}

struct AIJobSuggestion: Hashable {
    let relatedCompanies: [String]
    let interviewQuestions: [String]
    let coachingTip: String
    let webResearch: WebInterviewResearch?
}

struct GeminiResearchPreferenceSnapshot: Codable {
    var isEnabled: Bool
}

struct InterviewResearchStatus: Hashable {
    var isLoading: Bool
    var errorMessage: String?
    var fallbackResearch: WebInterviewResearch?

    static let idle = InterviewResearchStatus(
        isLoading: false,
        errorMessage: nil,
        fallbackResearch: nil
    )
}

enum AppDefaults {
    // Keep only the empty workflow structure. No sample applications or expenses are seeded.
    static let defaultStages: [JobStage] = [
        JobStage(title: "Saved", subtitle: "Shortlist roles that fit your profile.", tone: .info, kind: .saved, order: 0),
        JobStage(title: "Applied", subtitle: "Applications submitted and awaiting signal.", tone: .info, kind: .applied, order: 1),
        JobStage(title: "Interview", subtitle: "Live conversations most likely to convert soon.", tone: .warning, kind: .interview, order: 2),
        JobStage(title: "Offer", subtitle: "Roles close to decision or negotiation.", tone: .success, kind: .offer, order: 3),
        JobStage(title: "Offer Accepted", subtitle: "Accepted roles you converted and can track as your current job.", tone: .success, kind: .accepted, order: 4),
    ]

    /*
     Legacy sample applications and expenses were intentionally removed so the app launches
     against user-entered data only. Default workflow columns remain to keep the board usable.
     */
}
