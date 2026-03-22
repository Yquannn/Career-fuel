import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var jobStore: JobApplicationStore
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var aiService: AIInsightService
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var showingResetConfirmation = false
    @State private var geminiAPIKeyInput = ""
    @State private var geminiMessage: String?
    @State private var geminiMessageTone: StatusTone = .info
    @State private var reminderTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Settings",
                subtitle: "Manage local testing preferences, Gemini interview research, and smart alerts. Cloud sync is disabled in this build."
            )

            SurfaceCard {
                VStack(alignment: .leading, spacing: 18) {
                    settingsRow(
                        title: "Web interview research",
                        subtitle: aiService.webInterviewResearchStatusMessage,
                        symbol: "network"
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { aiService.isWebInterviewResearchEnabled },
                                set: { aiService.setWebInterviewResearchEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .tint(AppPalette.primary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Gemini API key")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        SecureField(
                            aiService.hasStoredGeminiAPIKey
                                ? "Stored securely. Paste a new key to replace it."
                                : "AIza...",
                            text: $geminiAPIKeyInput
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppPalette.surfaceSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppPalette.border, lineWidth: 1)
                        )

                        HStack(spacing: 12) {
                            Button(aiService.hasStoredGeminiAPIKey ? "Update Key" : "Save Key") {
                                handleSaveGeminiAPIKey()
                            }
                            .buttonStyle(.plain)
                            .disabled(geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppPalette.primary)
                            )
                            .foregroundStyle(.white)

                            if aiService.hasStoredGeminiAPIKey {
                                Button("Remove Key", role: .destructive) {
                                    handleRemoveGeminiAPIKey()
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppPalette.danger.opacity(0.14))
                                )
                                .foregroundStyle(AppPalette.danger)
                            }
                        }

                        Text("CareerFuel uses the Gemini Developer API with Google Search grounding to pull public interview feedback and attach source-backed questions to each saved job.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let geminiMessage {
                            Label(geminiMessage, systemImage: geminiMessageTone == .danger ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundStyle(geminiMessageTone.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 18) {
                    settingsRow(
                        title: "Cloud sync",
                        subtitle: cloudSyncManager.syncMessage,
                        symbol: cloudSyncManager.statusSymbol
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { cloudSyncManager.isCloudSyncEnabled },
                                set: { cloudSyncManager.isCloudSyncEnabled = $0 }
                            )
                        )
                        .labelsHidden()
                        .tint(AppPalette.primary)
                        .disabled(!cloudSyncManager.isCloudSyncAvailable)
                    }

                    settingsRow(
                        title: "Daily reminders & alerts",
                        subtitle: notificationManager.statusMessage,
                        symbol: "bell.badge.fill"
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { notificationManager.isNotificationsEnabled },
                                set: { newValue in
                                    Task {
                                        await notificationManager.setNotificationsEnabled(newValue)
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .tint(AppPalette.primary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reminder time")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        DatePicker(
                            "Daily reminder time",
                            selection: Binding(
                                get: { reminderTime },
                                set: { newValue in
                                    reminderTime = newValue
                                    notificationManager.setDailyReminderTime(newValue)
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(AppPalette.primary)
                        .disabled(!notificationManager.isNotificationsEnabled)

                        Text("The reminder adapts to your mode. In job search, it can prompt expenses and applications. In employed mode, it focuses on financial tracking.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await cloudSyncManager.syncNow()
                            }
                        } label: {
                            Label(
                                cloudSyncManager.isSyncing ? "Syncing…" : "Sync Now",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(cloudSyncManager.isCloudSyncEnabled ? AppPalette.primary : AppPalette.textSecondary)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!cloudSyncManager.isCloudSyncAvailable || !cloudSyncManager.isCloudSyncEnabled || cloudSyncManager.isSyncing)

                        if let lastSyncAt = cloudSyncManager.lastSyncAt {
                            InfoChip(
                                symbol: "clock.badge.checkmark",
                                title: "Last sync \(lastSyncAt.formatted(.dateTime.hour().minute()))"
                            )
                        }
                    }

                    Text(notificationStatusLine)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Local data")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text("Clear all jobs, expenses, local notification state, local sync preferences, and locally stored Gemini research settings on this device.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.textSecondary)

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Clear Local Storage", systemImage: "trash")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppPalette.danger)
                            )
                    }
                    .buttonStyle(.plain)

                    Text("Cloud data is not deleted. This build keeps Cloud Sync disabled so you can test locally with a free developer account.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }
        }
        .confirmationDialog(
            "Clear local storage?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Local Storage", role: .destructive) {
                Task {
                    await clearLocalStorage()
                }
            }
        } message: {
            Text("This removes locally stored jobs, expenses, smart alert history, Gemini research settings, and local sync preferences from this device.")
        }
        .task {
            reminderTime = notificationManager.dailyReminderTime
        }
        .onChange(of: notificationManager.dailyReminderTime, initial: false) { _, newValue in
            reminderTime = newValue
        }
    }

    @ViewBuilder
    private func settingsRow<Accessory: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppPalette.primary)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppPalette.primary.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            accessory()
        }
    }

    private var notificationStatusLine: String {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notification permission is available on this device. Daily reminders repeat at \(notificationManager.formattedReminderTime)."
        case .denied:
            return "Notification permission is denied. Enable it in iOS Settings if you want daily reminders and alerts."
        case .notDetermined:
            return "Notification permission has not been decided yet."
        @unknown default:
            return "Notification permission status is unavailable."
        }
    }

    private func clearLocalStorage() async {
        aiService.resetLocalPreferences()
        cloudSyncManager.resetLocalPreferences()
        jobStore.resetLocalData()
        expenseStore.resetLocalData()
        await notificationManager.resetLocalPreferences()
        geminiAPIKeyInput = ""
        geminiMessage = "Local data and saved Gemini API key were cleared from this device."
        geminiMessageTone = .success
    }

    private func handleSaveGeminiAPIKey() {
        if let message = aiService.saveGeminiAPIKey(geminiAPIKeyInput) {
            geminiMessage = message
            geminiMessageTone = .danger
        } else {
            geminiAPIKeyInput = ""
            geminiMessage = "Gemini API key saved securely."
            geminiMessageTone = .success
        }
    }

    private func handleRemoveGeminiAPIKey() {
        if let message = aiService.removeGeminiAPIKey() {
            geminiMessage = message
            geminiMessageTone = .danger
        } else {
            geminiAPIKeyInput = ""
            geminiMessage = "Stored Gemini API key removed."
            geminiMessageTone = .success
        }
    }
}
