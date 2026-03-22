import Combine
import Foundation

@MainActor
final class JobApplicationStore: ObservableObject {
    @Published private(set) var stages: [JobStage]
    @Published private(set) var applications: [JobApplication]
    @Published private(set) var selectedApplicationID: UUID?
    @Published private(set) var decisionSnapshot: JobDecisionSnapshot
    @Published private(set) var employmentSnapshot: EmploymentStatusSnapshot
    @Published private(set) var insightSnapshot: JobInsightSnapshot
    @Published private(set) var analyticsSummary: JobAnalyticsSummary

    private let persistence: PersistenceController
    private let defaults: UserDefaults
    private let storageKey = "careerfuel.jobstore.snapshot.v3"
    private let legacyStorageKey = "careerfuel.jobstore.snapshot"
    private var weeklyApplicationTargetValue: Int

    private var deletedStageTombstones: [DeletionTombstone]
    private var deletedApplicationTombstones: [DeletionTombstone]
    private var snapshotUpdatedAt: Date
    private var sortedStagesCache: [JobStage]
    private var stageLookup: [UUID: JobStage]
    private var applicationLookup: [UUID: JobApplication]
    private var applicationsByStageCache: [UUID: [JobApplication]]
    private var selectedApplicationCache: JobApplication?

    init(
        persistence: PersistenceController,
        defaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.defaults = defaults
        stages = []
        applications = []
        selectedApplicationID = nil
        decisionSnapshot = .empty
        employmentSnapshot = .empty
        insightSnapshot = .empty
        analyticsSummary = .empty
        weeklyApplicationTargetValue = 5
        deletedStageTombstones = []
        deletedApplicationTombstones = []
        snapshotUpdatedAt = Date()
        sortedStagesCache = []
        stageLookup = [:]
        applicationLookup = [:]
        applicationsByStageCache = [:]
        selectedApplicationCache = nil

        if
            let snapshot = persistence.load(JobStoreSnapshot.self, forKey: storageKey),
            !snapshot.stages.isEmpty,
            !Self.looksLikeLegacySeedData(snapshot)
        {
            stages = normalizedStages(snapshot.stages)
            applications = snapshot.applications
            weeklyApplicationTargetValue = max(snapshot.weeklyApplicationTarget, 1)
            deletedStageTombstones = snapshot.deletedStageTombstones
            deletedApplicationTombstones = snapshot.deletedApplicationTombstones
            selectedApplicationID = snapshot.selectedApplicationID
            snapshotUpdatedAt = snapshot.updatedAt
        } else if
            let migrated = Self.migrateLegacySnapshot(from: defaults, storageKey: legacyStorageKey),
            !Self.looksLikeLegacySeedData(migrated)
        {
            stages = normalizedStages(migrated.stages)
            applications = migrated.applications
            weeklyApplicationTargetValue = max(migrated.weeklyApplicationTarget, 1)
            deletedStageTombstones = migrated.deletedStageTombstones
            deletedApplicationTombstones = migrated.deletedApplicationTombstones
            selectedApplicationID = migrated.selectedApplicationID
            snapshotUpdatedAt = migrated.updatedAt
            persist()
        } else {
            stages = AppDefaults.defaultStages
            applications = []
            weeklyApplicationTargetValue = 5
            deletedStageTombstones = []
            deletedApplicationTombstones = []
            selectedApplicationID = nil
            snapshotUpdatedAt = Date()
            persist()
        }

        rebuildDerivedState()
        selectDefaultApplication()
    }

    var sortedStages: [JobStage] {
        sortedStagesCache
    }

    var selectedApplication: JobApplication? {
        selectedApplicationCache
    }

    var activeApplicationsCount: Int {
        decisionSnapshot.activeApplicationsCount
    }

    var interviewCount: Int {
        decisionSnapshot.interviewCount
    }

    var offerCount: Int {
        decisionSnapshot.offerCount
    }

    var weeklyApplicationTarget: Int {
        decisionSnapshot.weeklyApplicationTarget
    }

    func stage(for id: UUID) -> JobStage? {
        stageLookup[id]
    }

    func applications(in stage: JobStage) -> [JobApplication] {
        applicationsByStageCache[stage.id] ?? []
    }

    func application(for id: UUID) -> JobApplication? {
        applicationLookup[id]
    }

    func daysInStage(for application: JobApplication, referenceDate: Date = Date()) -> Int {
        max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: application.stageEnteredAt), to: Calendar.current.startOfDay(for: referenceDate)).day ?? 0, 0)
    }

    func daysSinceLastContact(for application: JobApplication, referenceDate: Date = Date()) -> Int? {
        guard let lastContactDate = application.lastContactDate else { return nil }
        return max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastContactDate), to: Calendar.current.startOfDay(for: referenceDate)).day ?? 0, 0)
    }

    func recommendedFollowUpDate(for application: JobApplication, referenceDate: Date = Date()) -> Date? {
        recommendedFollowUpDate(for: application, stageLookup: stageLookup, referenceDate: referenceDate)
    }

    func isStale(_ application: JobApplication, referenceDate: Date = Date()) -> Bool {
        isApplicationStale(application, stageLookup: stageLookup, referenceDate: referenceDate)
    }

    func isFollowUpDue(_ application: JobApplication, referenceDate: Date = Date()) -> Bool {
        isFollowUpDue(application, stageLookup: stageLookup, referenceDate: referenceDate)
    }

    func selectApplication(_ id: UUID?) {
        guard selectedApplicationID != id else { return }
        selectedApplicationID = id
        syncSelectedApplicationCache()
    }

    func add(_ draft: JobApplicationDraft) {
        let normalizedCompany = normalized(draft.companyName, fallback: "New Company")
        let normalizedRole = normalized(draft.role, fallback: "New Role")
        let normalizedPriority = normalized(draft.priority, fallback: "Standard")
        let normalizedLocation = normalized(draft.location, fallback: "Remote")
        let normalizedStatusNote = normalized(draft.statusNote, fallback: "Updated today")
        let stageTitle = stage(for: draft.stageID)?.title ?? "Pipeline"
        let createdAt = Date()
        let application = JobApplication(
            companyName: normalizedCompany,
            role: normalizedRole,
            stageID: draft.stageID,
            dateApplied: draft.dateApplied,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            feedback: draft.feedback.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: normalizedPriority,
            location: normalizedLocation,
            statusNote: normalizedStatusNote,
            lastContactDate: draft.lastContactDate,
            stageEnteredAt: draft.dateApplied,
            timeline: buildInitialTimeline(
                companyName: normalizedCompany,
                role: normalizedRole,
                stageTitle: stageTitle,
                dateApplied: draft.dateApplied,
                lastContactDate: draft.lastContactDate
            ),
            tags: normalizedTags(draft.tags),
            webInterviewResearch: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        applications.append(application)
        selectedApplicationID = application.id
        deletedApplicationTombstones.removeAll { $0.id == application.id }
        touchAndPersist()
    }

    func resetLocalData() {
        stages = AppDefaults.defaultStages
        applications = []
        weeklyApplicationTargetValue = 5
        deletedStageTombstones = []
        deletedApplicationTombstones = []
        selectedApplicationID = nil
        snapshotUpdatedAt = Date()
        rebuildDerivedState()
        persistence.removeValue(forKey: storageKey)
        defaults.removeObject(forKey: legacyStorageKey)
    }

    func edit(id: UUID, with draft: JobApplicationDraft) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }

        let previousApplication = applications[index]
        let normalizedCompany = normalized(draft.companyName, fallback: applications[index].companyName)
        let normalizedRole = normalized(draft.role, fallback: applications[index].role)
        let trimmedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFeedback = draft.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPriority = normalized(draft.priority, fallback: "Standard")
        let normalizedLocation = normalized(draft.location, fallback: "Remote")
        let normalizedStatusNote = normalized(draft.statusNote, fallback: "Updated today")
        let previousStageTitle = stage(for: previousApplication.stageID)?.title ?? "Previous stage"
        let nextStageTitle = stage(for: draft.stageID)?.title ?? "Pipeline"
        let now = Date()
        let shouldInvalidateResearch =
            normalizedCompany != applications[index].companyName ||
            normalizedRole != applications[index].role ||
            trimmedNotes != applications[index].notes ||
            trimmedFeedback != applications[index].feedback
        let didStageChange = draft.stageID != previousApplication.stageID
        let didContactChange = draft.lastContactDate != previousApplication.lastContactDate
        let didFeedbackChange = trimmedFeedback != previousApplication.feedback
        let didStatusChange = normalizedStatusNote != previousApplication.statusNote

        applications[index].companyName = normalizedCompany
        applications[index].role = normalizedRole
        applications[index].stageID = draft.stageID
        applications[index].dateApplied = draft.dateApplied
        applications[index].notes = trimmedNotes
        applications[index].feedback = trimmedFeedback
        applications[index].priority = normalizedPriority
        applications[index].location = normalizedLocation
        applications[index].statusNote = normalizedStatusNote
        applications[index].lastContactDate = draft.lastContactDate
        applications[index].tags = normalizedTags(draft.tags)
        if didStageChange {
            applications[index].stageEnteredAt = now
        }
        if shouldInvalidateResearch {
            applications[index].webInterviewResearch = nil
        }
        applications[index].updatedAt = now
        appendTimelineEvents(
            to: &applications[index],
            previousApplication: previousApplication,
            previousStageTitle: previousStageTitle,
            nextStageTitle: nextStageTitle,
            didStageChange: didStageChange,
            didContactChange: didContactChange,
            didFeedbackChange: didFeedbackChange,
            didStatusChange: didStatusChange,
            at: now
        )
        selectedApplicationID = id
        touchAndPersist()
    }

    func delete(id: UUID) {
        applications.removeAll { $0.id == id }
        upsertTombstone(id: id, in: &deletedApplicationTombstones)

        if selectedApplicationID == id {
            selectedApplicationID = applications.first?.id
        }

        touchAndPersist()
    }

    func moveApplication(id: UUID, to stageID: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        guard applications[index].stageID != stageID else { return }

        let previousStageTitle = stage(for: applications[index].stageID)?.title ?? "Previous stage"
        let nextStageTitle = stage(for: stageID)?.title ?? "Pipeline"
        let now = Date()
        applications[index].stageID = stageID
        applications[index].statusNote = "Moved today"
        applications[index].stageEnteredAt = now
        applications[index].updatedAt = now
        applications[index].timeline.insert(
            JobTimelineEvent(
                kind: .stageChange,
                date: now,
                title: "Moved to \(nextStageTitle)",
                detail: "Moved from \(previousStageTitle) into \(nextStageTitle)."
            ),
            at: 0
        )
        selectedApplicationID = id
        touchAndPersist()
    }

    func updateWeeklyApplicationTarget(_ target: Int) {
        let normalizedTarget = max(target, 1)
        guard weeklyApplicationTargetValue != normalizedTarget else { return }
        weeklyApplicationTargetValue = normalizedTarget
        touchAndPersist()
    }

    func logFollowUp(id: UUID, on date: Date = Date()) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        let normalizedDate = Calendar.current.startOfDay(for: date)
        applications[index].lastContactDate = normalizedDate
        applications[index].updatedAt = Date()
        applications[index].timeline.insert(
            JobTimelineEvent(
                kind: .followUp,
                date: normalizedDate,
                title: "Follow-up logged",
                detail: "Recorded a recruiter or company touchpoint."
            ),
            at: 0
        )
        selectedApplicationID = id
        touchAndPersist()
    }

    func updateWebInterviewResearch(id: UUID, research: WebInterviewResearch) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }

        applications[index].webInterviewResearch = research
        selectedApplicationID = id
        touchAndPersist()
    }

    func clearWebInterviewResearch(id: UUID) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }

        applications[index].webInterviewResearch = nil
        touchAndPersist()
    }

    func addStage(title: String, subtitle: String, tone: StatusTone) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let nextOrder = (stages.map(\.order).max() ?? -1) + 1
        let stage = JobStage(
            title: trimmedTitle,
            subtitle: normalized(subtitle, fallback: "Custom workflow stage."),
            tone: tone,
            order: nextOrder
        )

        stages.append(stage)
        deletedStageTombstones.removeAll { $0.id == stage.id }
        touchAndPersist()
    }

    func editStage(id: UUID, title: String, subtitle: String, tone: StatusTone) {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        stages[index].title = trimmedTitle
        stages[index].subtitle = normalized(subtitle, fallback: "Custom workflow stage.")
        stages[index].tone = tone
        stages[index].updatedAt = Date()
        touchAndPersist()
    }

    func deleteStage(id: UUID) {
        guard stages.count > 1 else { return }
        guard let fallbackStage = sortedStages.first(where: { $0.id != id }) else { return }

        for index in applications.indices where applications[index].stageID == id {
            applications[index].stageID = fallbackStage.id
            applications[index].updatedAt = Date()
        }

        stages.removeAll { $0.id == id }
        upsertTombstone(id: id, in: &deletedStageTombstones)
        reindexStages()
        touchAndPersist()
    }

    func snapshot() -> JobStoreSnapshot {
        let persistedStages = sortedStagesCache.isEmpty ? sortStages(stages) : sortedStagesCache

        return JobStoreSnapshot(
            stages: persistedStages,
            applications: applications,
            weeklyApplicationTarget: weeklyApplicationTargetValue,
            deletedStageTombstones: deletedStageTombstones,
            deletedApplicationTombstones: deletedApplicationTombstones,
            selectedApplicationID: selectedApplicationID,
            updatedAt: snapshotUpdatedAt
        )
    }

    func merge(snapshot remote: JobStoreSnapshot) {
        let merged = mergedSnapshot(with: remote)
        apply(snapshot: merged)
        persist()
    }

    func mergedSnapshot(with remote: JobStoreSnapshot) -> JobStoreSnapshot {
        let local = snapshot()
        let stageTombstones = mergedTombstones(local.deletedStageTombstones, remote.deletedStageTombstones)
        let applicationTombstones = mergedTombstones(local.deletedApplicationTombstones, remote.deletedApplicationTombstones)

        let mergedStages = mergedStages(
            local.stages,
            remote.stages,
            tombstones: stageTombstones
        )
        let fallbackStage = mergedStages.first ?? JobStage(
            title: "Inbox",
            subtitle: "Recovered fallback stage.",
            tone: .info,
            kind: .custom,
            order: 0
        )

        let mergedApplications = mergedApplications(
            local.applications,
            remote.applications,
            tombstones: applicationTombstones,
            validStageIDs: Set(mergedStages.map(\.id)),
            fallbackStageID: fallbackStage.id
        )
        let mergedStageIndex = Dictionary(uniqueKeysWithValues: mergedStages.map { ($0.id, $0) })

        let mergedSelection = [remote.selectedApplicationID, local.selectedApplicationID]
            .compactMap { $0 }
            .first(where: { selection in
                mergedApplications.contains(where: { $0.id == selection })
            })
            ?? mergedApplications.first(where: { application in
                mergedStageIndex[application.stageID]?.kind == .interview
            })?.id
            ?? mergedApplications.first?.id

        return JobStoreSnapshot(
            stages: mergedStages.isEmpty ? [fallbackStage] : mergedStages,
            applications: mergedApplications,
            weeklyApplicationTarget: local.updatedAt >= remote.updatedAt ? local.weeklyApplicationTarget : remote.weeklyApplicationTarget,
            deletedStageTombstones: stageTombstones,
            deletedApplicationTombstones: applicationTombstones,
            selectedApplicationID: mergedSelection,
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private func apply(snapshot: JobStoreSnapshot) {
        stages = normalizedStages(snapshot.stages.isEmpty ? AppDefaults.defaultStages : snapshot.stages)
        applications = snapshot.applications
        weeklyApplicationTargetValue = max(snapshot.weeklyApplicationTarget, 1)
        deletedStageTombstones = snapshot.deletedStageTombstones
        deletedApplicationTombstones = snapshot.deletedApplicationTombstones
        selectedApplicationID = snapshot.selectedApplicationID
        snapshotUpdatedAt = snapshot.updatedAt
        rebuildDerivedState()
        selectDefaultApplication()
    }

    private func rebuildDerivedState(referenceDate: Date = Date()) {
        let nextSortedStages = sortStages(stages)
        let nextStageLookup = Dictionary(uniqueKeysWithValues: nextSortedStages.map { ($0.id, $0) })
        let nextApplicationLookup = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        let nextApplicationsByStage = Dictionary(grouping: applications, by: \.stageID)
            .mapValues(sortApplications)

        let nextDecisionSnapshot = buildDecisionSnapshot(
            applications: applications,
            stageLookup: nextStageLookup,
            referenceDate: referenceDate
        )
        let nextEmploymentSnapshot = buildEmploymentSnapshot(
            applications: applications,
            stageLookup: nextStageLookup
        )
        let nextInsightSnapshot = buildInsightSnapshot(
            decisionSnapshot: nextDecisionSnapshot,
            employmentSnapshot: nextEmploymentSnapshot
        )
        let nextAnalyticsSummary = buildAnalyticsSummary(
            sortedStages: nextSortedStages,
            stageLookup: nextStageLookup,
            applicationsByStage: nextApplicationsByStage,
            applications: applications,
            decisionSnapshot: nextDecisionSnapshot,
            employmentSnapshot: nextEmploymentSnapshot,
            referenceDate: referenceDate
        )

        sortedStagesCache = nextSortedStages
        stageLookup = nextStageLookup
        applicationLookup = nextApplicationLookup
        applicationsByStageCache = nextApplicationsByStage

        if decisionSnapshot != nextDecisionSnapshot {
            decisionSnapshot = nextDecisionSnapshot
        }

        if employmentSnapshot != nextEmploymentSnapshot {
            employmentSnapshot = nextEmploymentSnapshot
        }

        if insightSnapshot != nextInsightSnapshot {
            insightSnapshot = nextInsightSnapshot
        }

        if analyticsSummary != nextAnalyticsSummary {
            analyticsSummary = nextAnalyticsSummary
        }

        syncSelectedApplicationCache()
    }

    private func buildDecisionSnapshot(
        applications: [JobApplication],
        stageLookup: [UUID: JobStage],
        referenceDate: Date
    ) -> JobDecisionSnapshot {
        let activePipelineApplications = applications.filter {
            (stageLookup[$0.stageID]?.kind ?? .custom).isLivePipelineStage
        }
        let interviewCount = applications.filter {
            let kind = stageLookup[$0.stageID]?.kind ?? .custom
            return kind == .interview || kind == .offer || kind == .accepted
        }.count
        let offerCount = applications.filter {
            let kind = stageLookup[$0.stageID]?.kind ?? .custom
            return kind == .offer || kind == .accepted
        }.count
        let acceptedCount = applications.filter {
            (stageLookup[$0.stageID]?.kind ?? .custom) == .accepted
        }.count
        let submittedApplicationsCount = applications.filter {
            let kind = stageLookup[$0.stageID]?.kind ?? .custom
            return kind != .saved
        }.count
        let weeklyApplicationsProgress = applicationsSubmittedThisWeek(
            applications: applications,
            stageLookup: stageLookup,
            referenceDate: referenceDate
        )
        let followUpDueCount = activePipelineApplications.filter {
            isFollowUpDue($0, stageLookup: stageLookup, referenceDate: referenceDate)
        }.count
        let staleApplications = activePipelineApplications.filter {
            isApplicationStale($0, stageLookup: stageLookup, referenceDate: referenceDate)
        }
        let highPriorityStaleCount = staleApplications.filter(isHighPriority).count
        let recentActivityCount = activePipelineApplications.filter {
            daysSinceMeaningfulActivity(for: $0, referenceDate: referenceDate) <= 7
        }.count

        let conversions = JobConversionSnapshot(
            submittedApplicationsCount: submittedApplicationsCount,
            interviewsReachedCount: interviewCount,
            offersReachedCount: offerCount,
            applicationToInterviewRate: conversionRate(numerator: interviewCount, denominator: submittedApplicationsCount),
            interviewToOfferRate: conversionRate(numerator: offerCount, denominator: max(interviewCount, 0))
        )

        return JobDecisionSnapshot(
            totalApplicationsCount: applications.count,
            activeApplicationsCount: activePipelineApplications.count,
            interviewCount: interviewCount,
            offerCount: offerCount,
            acceptedCount: acceptedCount,
            weeklyApplicationTarget: weeklyApplicationTargetValue,
            weeklyApplicationsProgress: weeklyApplicationsProgress,
            followUpDueCount: followUpDueCount,
            staleApplicationsCount: staleApplications.count,
            highPriorityStaleCount: highPriorityStaleCount,
            pipelineHealth: buildPipelineHealthSnapshot(
                activeApplicationsCount: activePipelineApplications.count,
                interviewCount: interviewCount,
                offerCount: offerCount,
                weeklyApplicationsProgress: weeklyApplicationsProgress,
                weeklyApplicationTarget: weeklyApplicationTargetValue,
                staleApplicationsCount: staleApplications.count,
                followUpDueCount: followUpDueCount,
                recentActivityCount: recentActivityCount
            ),
            conversions: conversions
        )
    }

    private func buildPipelineHealthSnapshot(
        activeApplicationsCount: Int,
        interviewCount: Int,
        offerCount: Int,
        weeklyApplicationsProgress: Int,
        weeklyApplicationTarget: Int,
        staleApplicationsCount: Int,
        followUpDueCount: Int,
        recentActivityCount: Int
    ) -> PipelineHealthSnapshot {
        let desiredPipelineCount = max(weeklyApplicationTarget * 2, 6)
        let volumeScore = min(Double(activeApplicationsCount) / Double(desiredPipelineCount), 1) * 35
        let distributionScore = min((Double(interviewCount) * 7) + (Double(offerCount) * 11), 35)
        let activityBase = activeApplicationsCount > 0
            ? (Double(recentActivityCount) / Double(activeApplicationsCount)) * 30
            : (weeklyApplicationsProgress > 0 ? 8 : 0)
        let activityPenalty = min(Double(staleApplicationsCount) * 4 + Double(followUpDueCount) * 2, 20)
        let score = clamped(Int((volumeScore + distributionScore + max(activityBase - activityPenalty, 0)).rounded()), minimum: 0, maximum: 100)

        let tone: StatusTone
        let label: String
        let message: String

        switch score {
        case ..<35:
            tone = .warning
            label = "Needs Build"
            message = "The pipeline is thin or stale. Add more active roles and refresh the quiet ones."
        case 35..<65:
            tone = .info
            label = "Building"
            message = "You have movement, but you still need more live roles or fresher activity to stabilize conversion odds."
        case 65..<85:
            tone = .success
            label = "Healthy"
            message = "Volume and stage mix are in a good range. Keep follow-ups moving so it stays healthy."
        default:
            tone = .success
            label = "Strong"
            message = "The pipeline has good volume, stage depth, and recent activity. Protect that momentum."
        }

        return PipelineHealthSnapshot(
            score: score,
            tone: tone,
            label: label,
            message: message
        )
    }

    private func buildEmploymentSnapshot(
        applications: [JobApplication],
        stageLookup: [UUID: JobStage]
    ) -> EmploymentStatusSnapshot {
        let acceptedCandidates: [AcceptedEmployment] = applications.compactMap {
            acceptedEmployment(for: $0, stageLookup: stageLookup)
        }
        let latestAcceptedEmployment = acceptedCandidates.max { lhs, rhs in
            lhs.updatedAt < rhs.updatedAt
        }

        return EmploymentStatusSnapshot(acceptedEmployment: latestAcceptedEmployment)
    }

    private func buildInsightSnapshot(
        decisionSnapshot: JobDecisionSnapshot,
        employmentSnapshot: EmploymentStatusSnapshot
    ) -> JobInsightSnapshot {
        JobInsightSnapshot(
            jobsNeeded: employmentSnapshot.acceptedEmployment == nil
                ? max(10 - decisionSnapshot.activeApplicationsCount, 0)
                : 0,
            weeklyApplicationTarget: decisionSnapshot.weeklyApplicationTarget,
            weeklyApplicationsProgress: decisionSnapshot.weeklyApplicationsProgress,
            followUpDueCount: decisionSnapshot.followUpDueCount,
            staleApplicationsCount: decisionSnapshot.staleApplicationsCount,
            highPriorityStaleCount: decisionSnapshot.highPriorityStaleCount,
            pipelineHealthScore: decisionSnapshot.pipelineHealth.score
        )
    }

    private func acceptedEmployment(
        for application: JobApplication,
        stageLookup: [UUID: JobStage]
    ) -> AcceptedEmployment? {
        let stage = stageLookup[application.stageID]
        let stageTitle = stage?.title ?? ""
        guard signalsAcceptedEmployment(
            stageKind: stage?.kind ?? .custom,
            statusNote: application.statusNote,
            feedback: application.feedback
        ) else {
            return nil
        }

        return AcceptedEmployment(
            applicationID: application.id,
            companyName: application.companyName,
            role: application.role,
            stageTitle: stageTitle,
            startDate: application.stageEnteredAt,
            updatedAt: application.updatedAt
        )
    }

    private func signalsAcceptedEmployment(
        stageKind: JobStageKind,
        statusNote: String,
        feedback: String
    ) -> Bool {
        if stageKind == .accepted {
            return true
        }

        let normalizedNotes = [statusNote, feedback]
            .joined(separator: " ")
            .lowercased()

        let acceptedNoteSignals = [
            "offer accepted",
            "accepted offer",
            "signed offer",
            "signed the offer",
            "joined the team",
            "started the role",
            "hired",
            "accepted the job",
        ]

        return acceptedNoteSignals.contains(where: normalizedNotes.contains)
    }

    private func buildAnalyticsSummary(
        sortedStages: [JobStage],
        stageLookup: [UUID: JobStage],
        applicationsByStage: [UUID: [JobApplication]],
        applications: [JobApplication],
        decisionSnapshot: JobDecisionSnapshot,
        employmentSnapshot: EmploymentStatusSnapshot,
        referenceDate: Date
    ) -> JobAnalyticsSummary {
        let pipelinePoints = sortedStages.map { stage in
            ApplicationStagePoint(
                stageID: stage.id,
                stageTitle: stage.title,
                tone: stage.tone,
                count: applicationsByStage[stage.id]?.count ?? 0
            )
        }

        let livePipelineApplications = applications.filter {
            (stageLookup[$0.stageID]?.kind ?? .custom).isLivePipelineStage
        }
        let appliedApplications = livePipelineApplications.filter {
            stageLookup[$0.stageID]?.kind == .applied
        }
        let interviewApplications = livePipelineApplications.filter {
            stageLookup[$0.stageID]?.kind == .interview
        }
        let offerApplications = livePipelineApplications.filter {
            stageLookup[$0.stageID]?.kind == .offer
        }
        let recentLiveApplications = livePipelineApplications.filter {
            ageInDays(for: $0, referenceDate: referenceDate) <= 14
        }.count

        let timeToHireEstimate: Int
        if employmentSnapshot.acceptedEmployment != nil {
            timeToHireEstimate = 0
        } else if !offerApplications.isEmpty {
            let averageOfferAge = averageAgeInDays(for: offerApplications, referenceDate: referenceDate)
            let averageInterviewAge = averageAgeInDays(for: interviewApplications, referenceDate: referenceDate)
            let blendedAge = (averageOfferAge * 0.75) + (averageInterviewAge * 0.25)
            timeToHireEstimate = clamped(Int(blendedAge.rounded()), minimum: 3, maximum: 21)
        } else if !interviewApplications.isEmpty {
            let averageInterviewAge = averageAgeInDays(for: interviewApplications, referenceDate: referenceDate)
            timeToHireEstimate = clamped(Int((averageInterviewAge * 0.8).rounded()) + 7, minimum: 7, maximum: 45)
        } else if !appliedApplications.isEmpty {
            let averageAppliedAge = averageAgeInDays(for: appliedApplications, referenceDate: referenceDate)
            timeToHireEstimate = clamped(Int((averageAppliedAge * 0.7).rounded()) + 14, minimum: 14, maximum: 60)
        } else {
            timeToHireEstimate = applications.isEmpty ? 0 : 30
        }

        let likelihoodScore = employmentSnapshot.acceptedEmployment != nil ? 1 : max(
            min(
                (Double(decisionSnapshot.offerCount) * 0.28) +
                (Double(decisionSnapshot.interviewCount) * 0.12) +
                (Double(appliedApplications.count) * 0.04) +
                (Double(recentLiveApplications) * 0.02),
                0.95
            ),
            livePipelineApplications.isEmpty ? 0 : 0.08
        )

        return JobAnalyticsSummary(
            pipelinePoints: pipelinePoints,
            timeToHireEstimate: timeToHireEstimate,
            hiringLikelihood: Int((likelihoodScore * 100).rounded()),
            weeklyTargetProgress: decisionSnapshot.weeklyApplicationsProgress,
            weeklyTarget: decisionSnapshot.weeklyApplicationTarget,
            staleApplicationsCount: decisionSnapshot.staleApplicationsCount,
            followUpDueCount: decisionSnapshot.followUpDueCount,
            conversions: decisionSnapshot.conversions
        )
    }

    private func buildInitialTimeline(
        companyName: String,
        role: String,
        stageTitle: String,
        dateApplied: Date,
        lastContactDate: Date?
    ) -> [JobTimelineEvent] {
        var events = [
            JobTimelineEvent(
                kind: .created,
                date: dateApplied,
                title: "Added to \(stageTitle)",
                detail: "Started tracking \(companyName) for \(role)."
            )
        ]

        if let lastContactDate {
            events.insert(
                JobTimelineEvent(
                    kind: .followUp,
                    date: lastContactDate,
                    title: "Last contact recorded",
                    detail: "Saved an existing recruiter or company touchpoint."
                ),
                at: 0
            )
        }

        return events.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.title < rhs.title
            }
            return lhs.date > rhs.date
        }
    }

    private func appendTimelineEvents(
        to application: inout JobApplication,
        previousApplication: JobApplication,
        previousStageTitle: String,
        nextStageTitle: String,
        didStageChange: Bool,
        didContactChange: Bool,
        didFeedbackChange: Bool,
        didStatusChange: Bool,
        at date: Date
    ) {
        if didStageChange {
            application.timeline.insert(
                JobTimelineEvent(
                    kind: .stageChange,
                    date: date,
                    title: "Moved to \(nextStageTitle)",
                    detail: "Moved from \(previousStageTitle) into \(nextStageTitle)."
                ),
                at: 0
            )
        }

        if didContactChange, let lastContactDate = application.lastContactDate {
            application.timeline.insert(
                JobTimelineEvent(
                    kind: .followUp,
                    date: lastContactDate,
                    title: "Contact updated",
                    detail: "Recorded a new recruiter or company touchpoint."
                ),
                at: 0
            )
        }

        if didFeedbackChange, !application.feedback.isEmpty {
            application.timeline.insert(
                JobTimelineEvent(
                    kind: .feedback,
                    date: date,
                    title: "Feedback added",
                    detail: application.feedback
                ),
                at: 0
            )
        }

        if didStatusChange, application.statusNote != previousApplication.statusNote {
            application.timeline.insert(
                JobTimelineEvent(
                    kind: .statusUpdate,
                    date: date,
                    title: "Status updated",
                    detail: application.statusNote
                ),
                at: 0
            )
        }
    }

    private func applicationsSubmittedThisWeek(
        applications: [JobApplication],
        stageLookup: [UUID: JobStage],
        referenceDate: Date
    ) -> Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
            return 0
        }

        return applications.filter {
            interval.contains($0.dateApplied) &&
            (stageLookup[$0.stageID]?.kind ?? .custom) != .saved
        }.count
    }

    private func recommendedFollowUpDate(
        for application: JobApplication,
        stageLookup: [UUID: JobStage],
        referenceDate: Date
    ) -> Date? {
        let stageKind = stageLookup[application.stageID]?.kind ?? .custom
        let cadenceDays: Int?

        switch stageKind {
        case .saved:
            cadenceDays = 7
        case .applied:
            cadenceDays = 5
        case .interview:
            cadenceDays = 3
        case .offer:
            cadenceDays = 2
        case .accepted:
            cadenceDays = nil
        case .custom:
            cadenceDays = 6
        }

        guard let cadenceDays else { return nil }
        let baseline = application.lastContactDate ?? application.stageEnteredAt
        let normalizedBaseline = Calendar.current.startOfDay(for: baseline)
        return Calendar.current.date(byAdding: .day, value: cadenceDays, to: normalizedBaseline)
    }

    private func daysSinceMeaningfulActivity(
        for application: JobApplication,
        referenceDate: Date
    ) -> Int {
        let baseline = application.lastContactDate ?? application.stageEnteredAt
        let calendar = Calendar.current
        return max(
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: baseline),
                to: calendar.startOfDay(for: referenceDate)
            ).day ?? 0,
            0
        )
    }

    private func isApplicationStale(
        _ application: JobApplication,
        stageLookup: [UUID: JobStage],
        referenceDate: Date
    ) -> Bool {
        let stageKind = stageLookup[application.stageID]?.kind ?? .custom
        let threshold: Int

        switch stageKind {
        case .saved:
            threshold = 10
        case .applied:
            threshold = 7
        case .interview:
            threshold = 5
        case .offer:
            threshold = 3
        case .accepted:
            return false
        case .custom:
            threshold = 7
        }

        return daysSinceMeaningfulActivity(for: application, referenceDate: referenceDate) > threshold
    }

    private func isFollowUpDue(
        _ application: JobApplication,
        stageLookup: [UUID: JobStage],
        referenceDate: Date
    ) -> Bool {
        guard let nextFollowUpDate = recommendedFollowUpDate(for: application, stageLookup: stageLookup, referenceDate: referenceDate) else {
            return false
        }

        return Calendar.current.startOfDay(for: nextFollowUpDate) <= Calendar.current.startOfDay(for: referenceDate)
    }

    private func priorityRank(for priority: String) -> Int {
        let normalizedPriority = priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedPriority.contains("urgent") || normalizedPriority.contains("critical") {
            return 4
        }

        if normalizedPriority.contains("high") {
            return 3
        }

        if normalizedPriority.contains("low") {
            return 1
        }

        return 2
    }

    private func isHighPriority(_ application: JobApplication) -> Bool {
        priorityRank(for: application.priority) >= 3
    }

    private func conversionRate(numerator: Int, denominator: Int) -> Int {
        guard denominator > 0 else { return 0 }
        return Int((Double(numerator) / Double(denominator) * 100).rounded())
    }

    private func sortStages(_ stages: [JobStage]) -> [JobStage] {
        stages.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.title < rhs.title
            }
            return lhs.order < rhs.order
        }
    }

    private func sortApplications(_ applications: [JobApplication]) -> [JobApplication] {
        applications.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.companyName < rhs.companyName
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func mergedStages(
        _ local: [JobStage],
        _ remote: [JobStage],
        tombstones: [DeletionTombstone]
    ) -> [JobStage] {
        let tombstoneIndex = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.id, $0.deletedAt) })
        let mergedByID = Dictionary(grouping: local + remote, by: \.id)
            .compactMapValues { candidates in
                candidates.max { lhs, rhs in
                    if lhs.updatedAt == rhs.updatedAt {
                        return lhs.order > rhs.order
                    }
                    return lhs.updatedAt < rhs.updatedAt
                }
            }

        let filtered = mergedByID.values.filter { stage in
            guard let deletedAt = tombstoneIndex[stage.id] else { return true }
            return stage.updatedAt > deletedAt
        }

        return filtered
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.title < rhs.title
                }
                return lhs.order < rhs.order
            }
            .enumerated()
            .map { index, stage in
                var updatedStage = stage
                updatedStage.order = index
                return updatedStage
            }
    }

    private func mergedApplications(
        _ local: [JobApplication],
        _ remote: [JobApplication],
        tombstones: [DeletionTombstone],
        validStageIDs: Set<UUID>,
        fallbackStageID: UUID
    ) -> [JobApplication] {
        let tombstoneIndex = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.id, $0.deletedAt) })
        let mergedByID = Dictionary(grouping: local + remote, by: \.id)
            .compactMapValues { candidates in
                candidates.max { lhs, rhs in
                    if lhs.updatedAt == rhs.updatedAt {
                        return lhs.companyName > rhs.companyName
                    }
                    return lhs.updatedAt < rhs.updatedAt
                }
            }

        return mergedByID.values
            .filter { application in
                guard let deletedAt = tombstoneIndex[application.id] else { return true }
                return application.updatedAt > deletedAt
            }
            .map { application in
                guard validStageIDs.contains(application.stageID) else {
                    var recovered = application
                    recovered.stageID = fallbackStageID
                    return recovered
                }
                return application
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.companyName < rhs.companyName
                }
                return lhs.updatedAt > rhs.updatedAt
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

    private func reindexStages() {
        stages = sortStages(stages).enumerated().map { index, stage in
            JobStage(
                id: stage.id,
                title: stage.title,
                subtitle: stage.subtitle,
                tone: stage.tone,
                kind: stage.kind,
                order: index,
                updatedAt: stage.updatedAt
            )
        }
    }

    private func normalizedStages(_ stages: [JobStage]) -> [JobStage] {
        var normalized = sortStages(stages).enumerated().map { index, stage in
            JobStage(
                id: stage.id,
                title: stage.title,
                subtitle: stage.subtitle,
                tone: stage.tone,
                kind: stage.kind,
                order: index,
                updatedAt: stage.updatedAt
            )
        }

        if !normalized.contains(where: { $0.kind == .accepted }) {
            let insertionIndex = min(
                (normalized.firstIndex(where: { $0.kind == .offer }) ?? (normalized.count - 1)) + 1,
                normalized.count
            )

            normalized.insert(
                JobStage(
                    title: "Offer Accepted",
                    subtitle: "Accepted roles you converted and can track as your current job.",
                    tone: .success,
                    kind: .accepted,
                    order: insertionIndex
                ),
                at: insertionIndex
            )
        }

        return sortStages(normalized).enumerated().map { index, stage in
            JobStage(
                id: stage.id,
                title: stage.title,
                subtitle: stage.subtitle,
                tone: stage.tone,
                kind: stage.kind,
                order: index,
                updatedAt: stage.updatedAt
            )
        }
    }

    private func ageInDays(for application: JobApplication, referenceDate: Date) -> Int {
        max(Calendar.current.dateComponents([.day], from: application.dateApplied, to: referenceDate).day ?? 0, 0)
    }

    private func averageAgeInDays(
        for applications: [JobApplication],
        referenceDate: Date
    ) -> Double {
        guard !applications.isEmpty else { return 0 }
        let ages = applications.map { Double(ageInDays(for: $0, referenceDate: referenceDate)) }
        return ages.reduce(0, +) / Double(ages.count)
    }

    private func clamped(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(max(value, minimum), maximum)
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

    private func upsertTombstone(id: UUID, in tombstones: inout [DeletionTombstone]) {
        let deletionDate = Date()

        if let index = tombstones.firstIndex(where: { $0.id == id }) {
            tombstones[index].deletedAt = deletionDate
        } else {
            tombstones.append(DeletionTombstone(id: id, deletedAt: deletionDate))
        }
    }

    private func touchAndPersist() {
        snapshotUpdatedAt = Date()
        rebuildDerivedState()
        persist()
    }

    private func persist() {
        persistence.save(snapshot(), forKey: storageKey, updatedAt: snapshotUpdatedAt)
    }

    private func selectDefaultApplication() {
        guard selectedApplicationID.flatMap({ applicationLookup[$0] }) == nil else {
            syncSelectedApplicationCache()
            return
        }

        selectedApplicationID = applications.first(where: { application in
            stage(for: application.stageID)?.kind == .interview
        })?.id ?? applications.first?.id
        syncSelectedApplicationCache()
    }

    private func syncSelectedApplicationCache() {
        selectedApplicationCache = selectedApplicationID.flatMap { applicationLookup[$0] }
    }
}

private extension JobApplicationStore {
    struct LegacySnapshot: Codable {
        let stages: [LegacyStage]
        let applications: [LegacyApplication]
    }

    struct LegacyStage: Codable {
        let id: UUID
        let title: String
        let subtitle: String
        let tone: StatusTone
        let order: Int
    }

    struct LegacyApplication: Codable {
        let id: UUID
        let companyName: String
        let role: String
        let stageID: UUID
        let dateApplied: Date
        let notes: String
        let priority: String
        let location: String
        let statusNote: String
        let createdAt: Date
        let updatedAt: Date
    }

    static func migrateLegacySnapshot(
        from defaults: UserDefaults,
        storageKey: String
    ) -> JobStoreSnapshot? {
        guard
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(LegacySnapshot.self, from: data),
            !snapshot.stages.isEmpty
        else {
            return nil
        }

        let stages = snapshot.stages.map { stage in
            JobStage(
                id: stage.id,
                title: stage.title,
                subtitle: stage.subtitle,
                tone: stage.tone,
                kind: JobStageKind.inferred(from: stage.title),
                order: stage.order,
                updatedAt: Date()
            )
        }

        let applications = snapshot.applications.map { application in
            JobApplication(
                id: application.id,
                companyName: application.companyName,
                role: application.role,
                stageID: application.stageID,
                dateApplied: application.dateApplied,
                notes: application.notes,
                feedback: "",
                priority: application.priority,
                location: application.location,
                statusNote: application.statusNote,
                lastContactDate: nil,
                stageEnteredAt: application.dateApplied,
                timeline: [
                    JobTimelineEvent(
                        kind: .created,
                        date: application.dateApplied,
                        title: "Application created",
                        detail: "Started tracking \(application.companyName) for \(application.role)."
                    )
                ],
                tags: [],
                webInterviewResearch: nil,
                createdAt: application.createdAt,
                updatedAt: application.updatedAt
            )
        }

        return JobStoreSnapshot(
            stages: stages,
            applications: applications,
            weeklyApplicationTarget: 5,
            deletedStageTombstones: [],
            deletedApplicationTombstones: [],
            selectedApplicationID: applications.first?.id,
            updatedAt: Date()
        )
    }

    static func looksLikeLegacySeedData(_ snapshot: JobStoreSnapshot) -> Bool {
        // These fingerprints are only used to clear old demo content from earlier builds.
        // They do not seed new installs.
        let companies = Set(snapshot.applications.map { $0.companyName.lowercased() })
        let seedCompanies: Set<String> = [
            "figma",
            "notion",
            "stripe",
            "canva",
            "airbnb",
            "deel",
            "webflow",
        ]

        return snapshot.applications.count == seedCompanies.count &&
            companies == seedCompanies
    }
}
