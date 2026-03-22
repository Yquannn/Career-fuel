import SwiftUI
import UniformTypeIdentifiers

struct KanbanBoardView: View {
    @EnvironmentObject private var jobStore: JobApplicationStore
    @EnvironmentObject private var appModeStore: AppModeStore
    @EnvironmentObject private var aiService: AIInsightService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingJobModal = false
    @State private var editingApplication: JobApplication?
    @State private var preselectedStageID: UUID?
    @State private var pendingDeleteApplication: JobApplication?

    @State private var showingStageEditor = false
    @State private var editingStage: JobStage?
    @State private var pendingDeleteStage: JobStage?
    @State private var showingTargetEditor = false
    @State private var isResearchExpanded = false
    @State private var isPrepExpanded = false

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var currentJobApplication: JobApplication? {
        guard let acceptedEmployment = appModeStore.acceptedEmployment else { return nil }
        return jobStore.applications.first { $0.id == acceptedEmployment.applicationID }
    }

    private var pastApplicationGroups: [CareerHistoryGroup] {
        let currentJobID = currentJobApplication?.id
        return jobStore.sortedStages.compactMap { stage in
            let applications = jobStore.applications(in: stage)
                .filter { $0.id != currentJobID }

            guard !applications.isEmpty else { return nil }
            return CareerHistoryGroup(stage: stage, applications: applications)
        }
    }

    private var shouldShowReturnToCareerModeButton: Bool {
        appModeStore.acceptedEmployment != nil && appModeStore.isUsingManualModeOverride
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if appModeStore.mode == .jobSearch {
                jobSearchBoard
            } else {
                careerTracker
            }
        }
        .sheet(isPresented: $showingJobModal, onDismiss: resetJobModalState) {
            ModalView(application: editingApplication, preselectedStageID: preselectedStageID)
                .environmentObject(jobStore)
        }
        .sheet(isPresented: $showingStageEditor, onDismiss: { editingStage = nil }) {
            StageEditorSheet(stage: editingStage) { title, subtitle, tone in
                if let editingStage {
                    jobStore.editStage(id: editingStage.id, title: title, subtitle: subtitle, tone: tone)
                } else {
                    jobStore.addStage(title: title, subtitle: subtitle, tone: tone)
                }
            }
        }
        .sheet(isPresented: $showingTargetEditor) {
            WeeklyTargetSheet(initialTarget: jobStore.weeklyApplicationTarget) { target in
                jobStore.updateWeeklyApplicationTarget(target)
            }
        }
        .confirmationDialog(
            "Delete application?",
            isPresented: Binding(
                get: { pendingDeleteApplication != nil },
                set: { if !$0 { pendingDeleteApplication = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteApplication {
                    jobStore.delete(id: pendingDeleteApplication.id)
                }
                pendingDeleteApplication = nil
            }
        } message: {
            Text("This removes the card from the board and updates metrics immediately.")
        }
        .confirmationDialog(
            "Delete column?",
            isPresented: Binding(
                get: { pendingDeleteStage != nil },
                set: { if !$0 { pendingDeleteStage = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteStage {
                    jobStore.deleteStage(id: pendingDeleteStage.id)
                }
                pendingDeleteStage = nil
            }
        } message: {
            Text("Cards in the deleted column are reassigned to the first remaining column.")
        }
        .onChange(of: jobStore.selectedApplicationID, initial: false) { _, _ in
            resetAISectionState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: appModeStore.mode == .jobSearch ? "Job tracker" : "Career tracker",
                subtitle: appModeStore.mode == .jobSearch
                    ? "Drag cards between columns, create new workflow stages, and add source-backed interview research to the roles that matter most."
                    : "Track the role you accepted, keep your past applications visible, and update your career record without losing any search history."
            )

            if appModeStore.mode == .jobSearch {
                if isWideLayout && !shouldShowReturnToCareerModeButton {
                    HStack(spacing: 12) {
                        addColumnButton
                        newJobButton
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if shouldShowReturnToCareerModeButton {
                            returnToCareerModeButton
                        }
                        addColumnButton
                        newJobButton
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                if isWideLayout {
                    HStack(spacing: 12) {
                        reopenJobSearchButton
                        updateCurrentJobButton
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        reopenJobSearchButton
                        updateCurrentJobButton
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var jobSearchBoard: some View {
        Group {
            jobSearchSummary

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(jobStore.sortedStages) { stage in
                        JobStageColumn(
                            stage: stage,
                            jobs: jobStore.applications(in: stage),
                            selectedApplicationID: jobStore.selectedApplicationID,
                            onSelect: { application in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    jobStore.selectApplication(application.id)
                                }
                            },
                            onCreateCard: {
                                startCreateJob(in: stage.id)
                            },
                            onEditCard: { application in
                                editingApplication = application
                                preselectedStageID = application.stageID
                                showingJobModal = true
                            },
                            onDeleteCard: { application in
                                pendingDeleteApplication = application
                            },
                            onEditStage: {
                                editingStage = stage
                                showingStageEditor = true
                            },
                            onDeleteStage: {
                                pendingDeleteStage = stage
                            },
                            onDropCard: { applicationID in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    jobStore.moveApplication(id: applicationID, to: stage.id)
                                }
                            }
                        )
                        .frame(width: 292)
                    }

                    Button {
                        editingStage = nil
                        showingStageEditor = true
                    } label: {
                        VStack(spacing: 14) {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppPalette.primary)

                            Text("Add Column")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)

                            Text("Create a new workflow stage for the board.")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .frame(width: 220, height: 210)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppPalette.surfaceSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                                .foregroundStyle(AppPalette.border)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            if let selectedApplication = jobStore.selectedApplication {
                selectedApplicationCard(selectedApplication)
            } else {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No applications yet")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text("Create your first job card to start tracking stages and generating interview prep suggestions.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var careerTracker: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let currentJobApplication, let acceptedEmployment = appModeStore.acceptedEmployment {
                currentJobSection(application: currentJobApplication, employment: acceptedEmployment)
            } else {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No current job linked")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text("Career mode is on, but the accepted application could not be resolved. Your application history is still available below.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            pastApplicationsSection

            if let selectedApplication = jobStore.selectedApplication {
                selectedApplicationCard(selectedApplication)
            }
        }
    }

    private var newJobButton: some View {
        Button {
            startCreateJob(in: jobStore.sortedStages.first?.id)
        } label: {
            Label("New Job", systemImage: "plus")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.primary)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var updateCurrentJobButton: some View {
        Button {
            guard let currentJobApplication else { return }
            editingApplication = currentJobApplication
            preselectedStageID = currentJobApplication.stageID
            showingJobModal = true
        } label: {
            Label("Update Current Job", systemImage: "pencil.circle.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(currentJobApplication == nil ? AppPalette.textSecondary : AppPalette.primary)
                )
        }
        .buttonStyle(.plain)
        .disabled(currentJobApplication == nil)
        .frame(maxWidth: .infinity)
    }

    private var reopenJobSearchButton: some View {
        Button {
            appModeStore.reopenJobSearch()
        } label: {
            Label("Reopen Job Search", systemImage: "arrow.uturn.backward.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var returnToCareerModeButton: some View {
        Button {
            appModeStore.resumeAutomaticMode()
        } label: {
            Label("Return to Career Mode", systemImage: "briefcase.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var addColumnButton: some View {
        Button {
            editingStage = nil
            showingStageEditor = true
        } label: {
            Label("Add Column", systemImage: "square.split.2x1")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var jobSearchSummary: some View {
        let snapshot = jobStore.decisionSnapshot

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pipeline Health")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text("\(snapshot.pipelineHealth.score)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(snapshot.pipelineHealth.tone.color)
                                .monospacedDigit()

                            StatusBadge(label: snapshot.pipelineHealth.label, tone: snapshot.pipelineHealth.tone)
                        }

                        Text(snapshot.pipelineHealth.message)
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        showingTargetEditor = true
                    } label: {
                        Label("Weekly Target", systemImage: "target")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppPalette.surfaceSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppPalette.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Group {
                    if isWideLayout {
                        HStack(spacing: 12) {
                            MiniStatCard(
                                title: "Weekly Progress",
                                value: "\(snapshot.weeklyApplicationsProgress)/\(snapshot.weeklyApplicationTarget)"
                            )
                            MiniStatCard(
                                title: "App -> Interview",
                                value: "\(snapshot.conversions.applicationToInterviewRate)%"
                            )
                            MiniStatCard(
                                title: "Interview -> Offer",
                                value: "\(snapshot.conversions.interviewToOfferRate)%"
                            )
                            MiniStatCard(
                                title: "Follow-ups Due",
                                value: "\(snapshot.followUpDueCount)"
                            )
                        }
                    } else {
                        VStack(spacing: 12) {
                            MiniStatCard(
                                title: "Weekly Progress",
                                value: "\(snapshot.weeklyApplicationsProgress)/\(snapshot.weeklyApplicationTarget)"
                            )
                            MiniStatCard(
                                title: "App -> Interview",
                                value: "\(snapshot.conversions.applicationToInterviewRate)%"
                            )
                            MiniStatCard(
                                title: "Interview -> Offer",
                                value: "\(snapshot.conversions.interviewToOfferRate)%"
                            )
                            MiniStatCard(
                                title: "Follow-ups Due",
                                value: "\(snapshot.followUpDueCount)"
                            )
                        }
                    }
                }

                if snapshot.staleApplicationsCount > 0 {
                    Label(
                        "\(snapshot.staleApplicationsCount) application\(snapshot.staleApplicationsCount == 1 ? " is" : "s are") stale. Refresh the quietest roles first.",
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(snapshot.highPriorityStaleCount > 0 ? AppPalette.danger : AppPalette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func currentJobSection(
        application: JobApplication,
        employment: AcceptedEmployment
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                jobStore.selectApplication(application.id)
            }
        } label: {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current Job")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)

                            Text("\(application.companyName) · \(application.role)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)
                        }

                        Spacer()

                        StatusBadge(label: "Current Job", tone: .success)
                    }

                    Group {
                        if isWideLayout {
                            HStack(spacing: 12) {
                                MiniStatCard(title: "Company", value: employment.companyName)
                                MiniStatCard(title: "Role", value: employment.role)
                                MiniStatCard(title: "Start date", value: employment.startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                            }
                        } else {
                            VStack(spacing: 12) {
                                MiniStatCard(title: "Company", value: employment.companyName)
                                MiniStatCard(title: "Role", value: employment.role)
                                MiniStatCard(title: "Start date", value: employment.startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                            }
                        }
                    }

                    if !application.feedback.isEmpty {
                        Label(application.feedback, systemImage: "quote.bubble.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(application.statusNote)
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Tap to review the full application details, notes, and interview research for this role.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var pastApplicationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Applications")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)

            Text("Your previous opportunities stay intact here for reference, learning, and career history.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if pastApplicationGroups.isEmpty {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No past applications yet")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text("Once you have previous applications beyond your current job, they will appear here grouped by stage.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(pastApplicationGroups) { group in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center, spacing: 10) {
                                Text(group.stage.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppPalette.textPrimary)

                                Spacer()

                                StatusBadge(label: "\(group.applications.count) saved", tone: group.stage.tone)
                            }

                            LazyVStack(spacing: 12) {
                                ForEach(group.applications) { application in
                                    JobApplicationCard(
                                        application: application,
                                        tone: group.stage.tone,
                                        isSelected: jobStore.selectedApplicationID == application.id,
                                        onSelect: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                                jobStore.selectApplication(application.id)
                                            }
                                        },
                                        onEdit: {
                                            editingApplication = application
                                            preselectedStageID = application.stageID
                                            showingJobModal = true
                                        },
                                        onDelete: {
                                            pendingDeleteApplication = application
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func selectedApplicationCard(_ application: JobApplication) -> some View {
        let suggestion = aiService.jobSuggestions[application.id] ?? aiService.jobSuggestion(for: application)
        let researchStatus = aiService.interviewResearchStatus(for: application.id)
        let showsQuestionFallback = suggestion.webResearch?.likelyQuestions.isEmpty ?? true
        let daysInStage = jobStore.daysInStage(for: application)
        let followUpDate = jobStore.recommendedFollowUpDate(for: application)
        let isFollowUpDue = jobStore.isFollowUpDue(application)
        let isStale = jobStore.isStale(application)
        let lastContactText = application.lastContactDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "No contact yet"
        let nextFollowUpText = followUpDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "No follow-up needed"

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let stage = jobStore.stage(for: application.stageID) {
                            StatusBadge(label: stage.title, tone: stage.tone)
                        }

                        Text("\(application.companyName) · \(application.role)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text(application.notes.isEmpty ? "No notes yet for this application." : application.notes)
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !application.feedback.isEmpty {
                            Label(application.feedback, systemImage: "quote.bubble.fill")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if isStale || isFollowUpDue {
                            Label(
                                isStale
                                    ? "This application looks stale. A fresh follow-up could restart momentum."
                                    : "A follow-up is due soon. Keep this role warm while the conversation is active.",
                                systemImage: isStale ? "clock.badge.exclamationmark" : "paperplane.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isStale ? AppPalette.danger : AppPalette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()

                    Menu {
                        Button("Edit") {
                            editingApplication = application
                            preselectedStageID = application.stageID
                            showingJobModal = true
                        }

                        Button("Delete", role: .destructive) {
                            pendingDeleteApplication = application
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Group {
                    if isWideLayout {
                        HStack(spacing: 12) {
                            MiniStatCard(title: "Date applied", value: application.dateApplied.formatted(.dateTime.month(.abbreviated).day()))
                            MiniStatCard(title: "Days in stage", value: daysInStage == 0 ? "Today" : "\(daysInStage)d")
                            MiniStatCard(title: "Priority", value: application.priority)
                            MiniStatCard(title: "Last contact", value: lastContactText)
                            MiniStatCard(title: "Next follow-up", value: nextFollowUpText)
                        }
                    } else {
                        VStack(spacing: 12) {
                            MiniStatCard(title: "Date applied", value: application.dateApplied.formatted(.dateTime.month(.abbreviated).day()))
                            MiniStatCard(title: "Days in stage", value: daysInStage == 0 ? "Today" : "\(daysInStage)d")
                            MiniStatCard(title: "Priority", value: application.priority)
                            MiniStatCard(title: "Last contact", value: lastContactText)
                            MiniStatCard(title: "Next follow-up", value: nextFollowUpText)
                        }
                    }
                }

                if appModeStore.mode == .jobSearch {
                    Button {
                        jobStore.logFollowUp(id: application.id)
                    } label: {
                        Label("Log Follow-up Today", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppPalette.primary)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if !application.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(application.tags, id: \.self) { tag in
                                SmallChip(title: tag)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Timeline")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    ForEach(application.timeline.prefix(6)) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.kind.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.primary)
                                .frame(width: 18, height: 18)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppPalette.textPrimary)

                                    Spacer()

                                    Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppPalette.textSecondary)
                                }

                                Text(event.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppPalette.surfaceSecondary)
                        )
                    }
                }

                ToggleableInsightSection(
                    title: "Interview Research",
                    preview: researchPreview(
                        for: application,
                        suggestion: suggestion,
                        researchStatus: researchStatus
                    ),
                    isExpanded: $isResearchExpanded
                ) {
                    webInterviewResearchSection(
                        for: application,
                        suggestion: suggestion,
                        researchStatus: researchStatus
                    )
                }

                ToggleableInsightSection(
                    title: showsQuestionFallback ? "On-device AI Prep" : "On-device Backup Prep",
                    preview: prepPreview(
                        suggestion: suggestion,
                        showsQuestionFallback: showsQuestionFallback
                    ),
                    isExpanded: $isPrepExpanded
                ) {
                    onDevicePrepSection(
                        suggestion: suggestion,
                        showsQuestionFallback: showsQuestionFallback
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func webInterviewResearchSection(
        for application: JobApplication,
        suggestion: AIJobSuggestion,
        researchStatus: InterviewResearchStatus
    ) -> some View {
        let displayedResearch = suggestion.webResearch ?? researchStatus.fallbackResearch

        VStack(alignment: .leading, spacing: 14) {
            Button {
                Task {
                    await aiService.refreshWebInterviewResearch(for: application.id)
                }
            } label: {
                Label(
                    researchStatus.isLoading ? "Researching…" : (application.webInterviewResearch == nil ? "Research" : "Refresh"),
                    systemImage: researchStatus.isLoading ? "hourglass" : "globe"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(aiService.canUseWebInterviewResearch ? AppPalette.primary : AppPalette.textSecondary)
                )
            }
            .buttonStyle(.plain)
            .disabled(researchStatus.isLoading || !aiService.canUseWebInterviewResearch)

            if !aiService.isAdvancedAIEnabled {
                Label("Advanced AI is optional. Turn it on in Settings if you want live public interview research and source links. Your on-device prep is already active below.", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !aiService.hasStoredGeminiAPIKey {
                Label("Add a Gemini API key in Settings only if you want live public interview research. CareerFuel will keep using on-device AI without it.", systemImage: "key.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if researchStatus.isLoading {
                ProgressView("Searching public interview feedback…")
                    .tint(AppPalette.primary)
            }

            if let errorMessage = researchStatus.errorMessage {
                Label(errorMessage, systemImage: researchStatus.fallbackResearch == nil ? "exclamationmark.triangle.fill" : "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(researchStatus.fallbackResearch == nil ? AppPalette.danger : AppPalette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let research = displayedResearch {
                HStack(spacing: 10) {
                    InfoChip(
                        symbol: "clock.badge.checkmark",
                        title: "Updated \(research.generatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
                    )

                    InfoChip(symbol: "brain.head.profile", title: research.model)
                }

                Text(research.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !research.hiringSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Public hiring signals")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        ForEach(research.hiringSignals, id: \.self) { signal in
                            Label(signal, systemImage: "dot.scope")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !research.likelyQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Likely interview questions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        ForEach(research.likelyQuestions, id: \.self) { question in
                            Label(question, systemImage: "sparkles")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !research.preparationFocus.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preparation focus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        ForEach(research.preparationFocus, id: \.self) { focus in
                            Label(focus, systemImage: "checklist")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !research.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sources")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        ForEach(research.sources) { source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "link")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppPalette.primary)
                                            .frame(width: 20)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(AppPalette.textPrimary)
                                                .multilineTextAlignment(.leading)

                                            Text(url.host ?? source.url)
                                                .font(.caption)
                                                .foregroundStyle(AppPalette.textSecondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(AppPalette.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(AppPalette.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else if aiService.canUseWebInterviewResearch && !researchStatus.isLoading {
                Text("No live research cached yet. Tap Research to pull current public interview signals for this application.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func onDevicePrepSection(
        suggestion: AIJobSuggestion,
        showsQuestionFallback: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if aiService.isRefreshingJobInsights {
                ActivityPill(title: "Refreshing prep")
            }

            Label(suggestion.coachingTip, systemImage: "lightbulb.max.fill")
                .font(.subheadline)
                .foregroundStyle(AppPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .topLeading)

            if !suggestion.relatedCompanies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related companies")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestion.relatedCompanies, id: \.self) { company in
                                SmallChip(title: company)
                            }
                        }
                    }
                }
            }

            if showsQuestionFallback {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested interview questions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    ForEach(suggestion.interviewQuestions.prefix(4), id: \.self) { question in
                        Label(question, systemImage: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: aiService.isRefreshingJobInsights)
    }

    private func startCreateJob(in stageID: UUID?) {
        editingApplication = nil
        preselectedStageID = stageID
        showingJobModal = true
    }

    private func resetJobModalState() {
        editingApplication = nil
        preselectedStageID = nil
    }

    private func resetAISectionState() {
        isResearchExpanded = false
        isPrepExpanded = false
    }

    private func researchPreview(
        for application: JobApplication,
        suggestion: AIJobSuggestion,
        researchStatus: InterviewResearchStatus
    ) -> String {
        if researchStatus.isLoading {
            return "Searching public interview feedback for this role."
        }

        if let errorMessage = researchStatus.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }

        if let summary = (suggestion.webResearch ?? researchStatus.fallbackResearch)?.summary, !summary.isEmpty {
            return summary
        }

        if aiService.canUseWebInterviewResearch {
            return "Source-backed interview themes, likely questions, and links for this application."
        }

        if !aiService.isAdvancedAIEnabled {
            return "On-device AI prep is already active. Turn on Advanced AI in Settings only if you want public interview sources and live research."
        }

        if !aiService.hasStoredGeminiAPIKey {
            return "Advanced AI is on, but no Gemini API key is saved yet. On-device AI prep is still available."
        }

        return "Run live research to pull public interview feedback and source links for this role."
    }

    private func prepPreview(
        suggestion: AIJobSuggestion,
        showsQuestionFallback: Bool
    ) -> String {
        if showsQuestionFallback, let firstQuestion = suggestion.interviewQuestions.first {
            return firstQuestion
        }

        return suggestion.coachingTip
    }
}

private struct ToggleableInsightSection<Content: View>: View {
    let title: String
    let preview: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppPalette.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppPalette.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

private struct CareerHistoryGroup: Identifiable {
    let stage: JobStage
    let applications: [JobApplication]

    var id: UUID { stage.id }
}

private struct JobStageColumn: View {
    let stage: JobStage
    let jobs: [JobApplication]
    let selectedApplicationID: UUID?
    let onSelect: (JobApplication) -> Void
    let onCreateCard: () -> Void
    let onEditCard: (JobApplication) -> Void
    let onDeleteCard: (JobApplication) -> Void
    let onEditStage: () -> Void
    let onDeleteStage: () -> Void
    let onDropCard: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text(stage.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Menu {
                    Button("Add Card") {
                        onCreateCard()
                    }

                    Button("Edit Column") {
                        onEditStage()
                    }

                    Button("Delete Column", role: .destructive) {
                        onDeleteStage()
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text("\(jobs.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppPalette.surface)
                            )

                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                onCreateCard()
            } label: {
                Label("Add card", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stage.tone.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppPalette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(stage.tone.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            LazyVStack(spacing: 12) {
                ForEach(jobs) { application in
                    JobApplicationCard(
                        application: application,
                        tone: stage.tone,
                        isSelected: selectedApplicationID == application.id,
                        onSelect: { onSelect(application) },
                        onEdit: { onEditCard(application) },
                        onDelete: { onDeleteCard(application) }
                    )
                    .onDrag {
                        NSItemProvider(object: application.id.uuidString as NSString)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard
                let uuidString = object as? String,
                let applicationID = UUID(uuidString: uuidString.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return
            }

            DispatchQueue.main.async {
                guard !jobs.contains(where: { $0.id == applicationID }) else { return }
                onDropCard(applicationID)
            }
        }

        return true
    }
}

private struct JobApplicationCard: View {
    @EnvironmentObject private var jobStore: JobApplicationStore

    let application: JobApplication
    let tone: StatusTone
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var daysInStage: Int {
        jobStore.daysInStage(for: application)
    }

    private var isFollowUpDue: Bool {
        jobStore.isFollowUpDue(application)
    }

    private var isStale: Bool {
        jobStore.isStale(application)
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(application.companyName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text(application.role)
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Circle()
                        .fill(tone.color)
                        .frame(width: 12, height: 12)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    SmallChip(title: application.priority)
                    SmallChip(title: daysInStage == 0 ? "Today" : "\(daysInStage)d in stage")
                    if isFollowUpDue {
                        SmallChip(title: "Follow up")
                    }
                    if isStale {
                        SmallChip(title: "Stale")
                    }
                    SmallChip(title: application.location)
                }

                if !application.statusNote.isEmpty {
                    Text(application.statusNote)
                        .font(.caption)
                        .foregroundStyle(AppPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? AppPalette.primary.opacity(0.35) : AppPalette.border, lineWidth: 1)
            )
            .shadow(color: AppPalette.shadow.opacity(0.5), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") {
                onEdit()
            }

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

private struct StageEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let stage: JobStage?
    private let onSave: (String, String, StatusTone) -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var tone: StatusTone

    init(stage: JobStage?, onSave: @escaping (String, String, StatusTone) -> Void) {
        self.stage = stage
        self.onSave = onSave
        _title = State(initialValue: stage?.title ?? "")
        _subtitle = State(initialValue: stage?.subtitle ?? "")
        _tone = State(initialValue: stage?.tone ?? .info)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Column title", text: $title)
                TextField("Column subtitle", text: $subtitle)

                Picker("Tone", selection: $tone) {
                    ForEach(StatusTone.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle(stage == nil ? "New Column" : "Edit Column")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(stage == nil ? "Create" : "Save") {
                        onSave(title, subtitle, tone)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct WeeklyTargetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Int) -> Void

    @State private var target: Int

    init(initialTarget: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _target = State(initialValue: max(initialTarget, 1))
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $target, in: 1...30) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weekly application target")
                        Text("Set how many applications you want to send each week.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }

                LabeledContent("Target", value: "\(target)")
            }
            .navigationTitle("Weekly Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(target)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
