import SwiftUI

struct ModalView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var jobStore: JobApplicationStore
    @EnvironmentObject private var aiService: AIInsightService

    private let application: JobApplication?
    private let preselectedStageID: UUID?

    @State private var companyName: String
    @State private var role: String
    @State private var selectedStageID: UUID?
    @State private var dateApplied: Date
    @State private var notes: String
    @State private var feedback: String
    @State private var priority: String
    @State private var location: String
    @State private var statusNote: String
    @State private var hasLastContactDate: Bool
    @State private var lastContactDate: Date
    @State private var livePreviewSuggestion: AIJobSuggestion?
    @State private var isPreviewLoading = false
    @State private var previewTask: Task<Void, Never>?

    init(application: JobApplication? = nil, preselectedStageID: UUID? = nil) {
        self.application = application
        self.preselectedStageID = preselectedStageID
        _companyName = State(initialValue: application?.companyName ?? "")
        _role = State(initialValue: application?.role ?? "")
        _selectedStageID = State(initialValue: application?.stageID ?? preselectedStageID)
        _dateApplied = State(initialValue: application?.dateApplied ?? Date())
        _notes = State(initialValue: application?.notes ?? "")
        _feedback = State(initialValue: application?.feedback ?? "")
        _priority = State(initialValue: application?.priority ?? "Standard")
        _location = State(initialValue: application?.location ?? "Remote")
        _statusNote = State(initialValue: application?.statusNote ?? "Updated today")
        _hasLastContactDate = State(initialValue: application?.lastContactDate != nil)
        _lastContactDate = State(initialValue: application?.lastContactDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    TextField("Company Name", text: $companyName)
                    TextField("Role", text: $role)

                    Picker("Status", selection: stageBinding) {
                        ForEach(jobStore.sortedStages) { stage in
                            Text(stage.title).tag(Optional(stage.id))
                        }
                    }
                }

                Section("Timeline") {
                    DatePicker("Date Applied", selection: $dateApplied, displayedComponents: .date)
                    TextField("Status Note", text: $statusNote)

                    Toggle("Last contact recorded", isOn: $hasLastContactDate.animation(.easeInOut(duration: 0.18)))

                    if hasLastContactDate {
                        DatePicker("Last Contact", selection: $lastContactDate, displayedComponents: .date)
                    }
                }

                Section("Context") {
                    TextField("Priority", text: $priority)
                    TextField("Location", text: $location)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                    TextField("Feedback", text: $feedback, axis: .vertical)
                        .lineLimit(3...6)
                }

                if isPreviewLoading || livePreviewSuggestion != nil {
                    Section("On-device AI Suggestions") {
                        if isPreviewLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(AppPalette.primary)
                                Text("Updating interview prep…")
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                        }

                        if let suggestion = livePreviewSuggestion {
                            if !suggestion.relatedCompanies.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Related companies")
                                        .font(.subheadline.weight(.semibold))

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(suggestion.relatedCompanies, id: \.self) { company in
                                                SmallChip(title: company)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Possible interview questions")
                                    .font(.subheadline.weight(.semibold))

                                ForEach(suggestion.interviewQuestions.prefix(3), id: \.self) { question in
                                    Label(question, systemImage: "sparkles")
                                        .font(.subheadline)
                                        .foregroundStyle(AppPalette.textPrimary)
                                }
                            }

                            Label(suggestion.coachingTip, systemImage: "lightbulb.max.fill")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textSecondary)

                            if aiService.isAdvancedAIEnabled {
                                Text("Save this application, then open it from the Applications tab to run optional advanced AI research with public source links.")
                                    .font(.caption)
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .navigationTitle(application == nil ? "New Application" : "Edit Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(application == nil ? "Save" : "Update") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if selectedStageID == nil {
                    selectedStageID = preselectedStageID ?? jobStore.sortedStages.first?.id
                }
                schedulePreviewRefresh()
            }
            .onDisappear {
                previewTask?.cancel()
            }
            .onChange(of: companyName) { _, _ in schedulePreviewRefresh() }
            .onChange(of: role) { _, _ in schedulePreviewRefresh() }
            .onChange(of: notes) { _, _ in schedulePreviewRefresh() }
            .onChange(of: feedback) { _, _ in schedulePreviewRefresh() }
            .onChange(of: priority) { _, _ in schedulePreviewRefresh() }
            .onChange(of: location) { _, _ in schedulePreviewRefresh() }
        }
    }

    private var stageBinding: Binding<UUID?> {
        Binding(
            get: { selectedStageID },
            set: { selectedStageID = $0 }
        )
    }

    private var isValid: Bool {
        !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedStageID != nil
    }

    private var preview: JobApplication? {
        guard let selectedStageID else { return nil }
        let draftPreview = JobApplication(
            id: application?.id ?? UUID(),
            companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.trimmingCharacters(in: .whitespacesAndNewlines),
            stageID: selectedStageID,
            dateApplied: dateApplied,
            notes: notes,
            feedback: feedback,
            priority: priority,
            location: location,
            statusNote: statusNote,
            lastContactDate: hasLastContactDate ? lastContactDate : nil,
            stageEnteredAt: application?.stageEnteredAt ?? dateApplied,
            timeline: application?.timeline ?? [],
            tags: application?.tags ?? [],
            createdAt: application?.createdAt ?? Date(),
            updatedAt: Date()
        )

        guard !draftPreview.companyName.isEmpty, !draftPreview.role.isEmpty else { return nil }
        return draftPreview
    }

    private var suggestedTags: [String] {
        guard let preview else { return application?.tags ?? [] }
        return Array(Set((application?.tags ?? []) + aiService.suggestedJobTags(for: preview))).sorted()
    }

    private func save() {
        guard let selectedStageID else { return }
        previewTask?.cancel()

        let draft = JobApplicationDraft(
            companyName: companyName,
            role: role,
            stageID: selectedStageID,
            dateApplied: dateApplied,
            notes: notes,
            feedback: feedback,
            priority: priority,
            location: location,
            statusNote: statusNote,
            lastContactDate: hasLastContactDate ? lastContactDate : nil,
            tags: suggestedTags
        )

        if let application {
            jobStore.edit(id: application.id, with: draft)
        } else {
            jobStore.add(draft)
        }

        dismiss()
    }

    private func schedulePreviewRefresh() {
        previewTask?.cancel()

        guard let preview else {
            livePreviewSuggestion = nil
            isPreviewLoading = false
            return
        }

        isPreviewLoading = true

        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                isPreviewLoading = false
                return
            }
            livePreviewSuggestion = aiService.jobSuggestion(for: preview)
            isPreviewLoading = false
        }
    }
}
