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
            deletedStageTombstones = migrated.deletedStageTombstones
            deletedApplicationTombstones = migrated.deletedApplicationTombstones
            selectedApplicationID = migrated.selectedApplicationID
            snapshotUpdatedAt = migrated.updatedAt
            persist()
        } else {
            stages = AppDefaults.defaultStages
            applications = []
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

    func stage(for id: UUID) -> JobStage? {
        stageLookup[id]
    }

    func applications(in stage: JobStage) -> [JobApplication] {
        applicationsByStageCache[stage.id] ?? []
    }

    func selectApplication(_ id: UUID?) {
        guard selectedApplicationID != id else { return }
        selectedApplicationID = id
        syncSelectedApplicationCache()
    }

    func add(_ draft: JobApplicationDraft) {
        let application = JobApplication(
            companyName: normalized(draft.companyName, fallback: "New Company"),
            role: normalized(draft.role, fallback: "New Role"),
            stageID: draft.stageID,
            dateApplied: draft.dateApplied,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            feedback: draft.feedback.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: normalized(draft.priority, fallback: "Standard"),
            location: normalized(draft.location, fallback: "Remote"),
            statusNote: normalized(draft.statusNote, fallback: "Updated today"),
            tags: normalizedTags(draft.tags),
            webInterviewResearch: nil
        )

        applications.append(application)
        selectedApplicationID = application.id
        deletedApplicationTombstones.removeAll { $0.id == application.id }
        touchAndPersist()
    }

    func resetLocalData() {
        stages = AppDefaults.defaultStages
        applications = []
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

        let normalizedCompany = normalized(draft.companyName, fallback: applications[index].companyName)
        let normalizedRole = normalized(draft.role, fallback: applications[index].role)
        let trimmedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFeedback = draft.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldInvalidateResearch =
            normalizedCompany != applications[index].companyName ||
            normalizedRole != applications[index].role ||
            trimmedNotes != applications[index].notes ||
            trimmedFeedback != applications[index].feedback

        applications[index].companyName = normalizedCompany
        applications[index].role = normalizedRole
        applications[index].stageID = draft.stageID
        applications[index].dateApplied = draft.dateApplied
        applications[index].notes = trimmedNotes
        applications[index].feedback = trimmedFeedback
        applications[index].priority = normalized(draft.priority, fallback: "Standard")
        applications[index].location = normalized(draft.location, fallback: "Remote")
        applications[index].statusNote = normalized(draft.statusNote, fallback: "Updated today")
        applications[index].tags = normalizedTags(draft.tags)
        if shouldInvalidateResearch {
            applications[index].webInterviewResearch = nil
        }
        applications[index].updatedAt = Date()
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

        applications[index].stageID = stageID
        applications[index].statusNote = "Moved today"
        applications[index].updatedAt = Date()
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
            deletedStageTombstones: stageTombstones,
            deletedApplicationTombstones: applicationTombstones,
            selectedApplicationID: mergedSelection,
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private func apply(snapshot: JobStoreSnapshot) {
        stages = normalizedStages(snapshot.stages.isEmpty ? AppDefaults.defaultStages : snapshot.stages)
        applications = snapshot.applications
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
            stageLookup: nextStageLookup
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
        stageLookup: [UUID: JobStage]
    ) -> JobDecisionSnapshot {
        applications.reduce(into: JobDecisionSnapshot.empty) { snapshot, application in
            let stageKind = stageLookup[application.stageID]?.kind ?? .custom

            if stageKind.isLivePipelineStage {
                snapshot.activeApplicationsCount += 1
            }

            if stageKind == .interview {
                snapshot.interviewCount += 1
            } else if stageKind == .offer {
                snapshot.offerCount += 1
            }
        }
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
                : 0
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
            startDate: application.updatedAt,
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
            hiringLikelihood: Int((likelihoodScore * 100).rounded())
        )
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
                tags: [],
                webInterviewResearch: nil,
                createdAt: application.createdAt,
                updatedAt: application.updatedAt
            )
        }

        return JobStoreSnapshot(
            stages: stages,
            applications: applications,
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
