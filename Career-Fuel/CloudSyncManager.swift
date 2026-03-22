import CloudKit
import Combine
import Foundation
import UIKit

@MainActor
final class CloudSyncManager: ObservableObject {
    let isCloudSyncAvailable = false

    @Published var isCloudSyncEnabled: Bool {
        didSet {
            guard isCloudSyncAvailable else {
                if isCloudSyncEnabled {
                    isCloudSyncEnabled = false
                    return
                }

                hasPendingChanges = false
                lastSyncAt = nil
                syncMessage = Self.disabledMessage
                persistPreferences()
                return
            }

            persistPreferences()

            if isCloudSyncEnabled {
                Task {
                    await syncNow(trigger: "Enabled")
                }
            }
        }
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var hasPendingChanges: Bool
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var syncMessage: String

    var statusLabel: String {
        if !isCloudSyncAvailable {
            return "Unavailable"
        }
        if !isCloudSyncEnabled {
            return "Cloud Off"
        }
        if isSyncing {
            return "Syncing"
        }
        if hasPendingChanges {
            return "Pending"
        }
        if lastSyncAt != nil {
            return "Synced"
        }
        return "Ready"
    }

    var statusSymbol: String {
        if !isCloudSyncAvailable {
            return "icloud.slash"
        }
        if !isCloudSyncEnabled {
            return "icloud.slash"
        }
        if isSyncing {
            return "arrow.triangle.2.circlepath.icloud"
        }
        if hasPendingChanges {
            return "icloud.and.arrow.up"
        }
        return "icloud"
    }

    private let persistence: PersistenceController
    private let jobStore: JobApplicationStore
    private let expenseStore: ExpenseStore
    private let recordID = CKRecord.ID(recordName: "careerfuel-primary-state")
    private let preferencesKey = "careerfuel.cloudsync.preferences"
    private let deviceID: String

    private var cancellables = Set<AnyCancellable>()
    private var suppressObservedChanges = false

    private lazy var container: CKContainer = CKContainer.default()

    private var database: CKDatabase {
        container.privateCloudDatabase
    }

    init(
        persistence: PersistenceController,
        jobStore: JobApplicationStore,
        expenseStore: ExpenseStore
    ) {
        self.persistence = persistence
        self.jobStore = jobStore
        self.expenseStore = expenseStore
        deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        isCloudSyncEnabled = false
        lastSyncAt = nil
        hasPendingChanges = false
        syncMessage = Self.disabledMessage

        observeLocalChanges()
    }

    func syncNow(trigger: String = "Manual") async {
        guard isCloudSyncAvailable else {
            syncMessage = Self.disabledMessage
            return
        }

        guard isCloudSyncEnabled else {
            syncMessage = "Cloud sync is off. Enable it in Settings to sync across devices."
            return
        }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let status = try await accountStatus()
            guard status == .available else {
                hasPendingChanges = true
                syncMessage = "iCloud is unavailable on this device. Changes remain local until iCloud is available."
                persistPreferences()
                return
            }

            if let remoteRecord = try await fetchRecord() {
                if let remoteEnvelope = envelope(from: remoteRecord) {
                    mergeRemoteEnvelope(remoteEnvelope)
                }

                let mergedRecord = remoteRecord
                apply(envelope: buildLocalEnvelope(), to: mergedRecord)

                do {
                    _ = try await save(record: mergedRecord)
                } catch let error as CKError where error.code == .serverRecordChanged {
                    let serverRecord: CKRecord?
                    if let conflictRecord = conflictServerRecord(from: error) {
                        serverRecord = conflictRecord
                    } else {
                        serverRecord = try await fetchRecord()
                    }

                    if let serverRecord, let remoteEnvelope = envelope(from: serverRecord) {
                        mergeRemoteEnvelope(remoteEnvelope)
                        let retryRecord = serverRecord
                        apply(envelope: buildLocalEnvelope(), to: retryRecord)
                        _ = try await save(record: retryRecord)
                    } else {
                        throw error
                    }
                }
            } else {
                let newRecord = CKRecord(recordType: "CareerFuelState", recordID: recordID)
                apply(envelope: buildLocalEnvelope(), to: newRecord)
                _ = try await save(record: newRecord)
            }

            hasPendingChanges = false
            lastSyncAt = Date()
            syncMessage = trigger == "Manual"
                ? "Cloud sync completed just now."
                : "Changes synced to iCloud."
            persistPreferences()
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            hasPendingChanges = true
            syncMessage = "Cloud sync failed: \(error.localizedDescription)"
            persistPreferences()
        }
    }

    func resetLocalPreferences() {
        isCloudSyncEnabled = false
        isSyncing = false
        hasPendingChanges = false
        lastSyncAt = nil
        syncMessage = Self.disabledMessage
        persistence.removeValue(forKey: preferencesKey)
    }

    private func observeLocalChanges() {
        let changePublishers: [AnyPublisher<Void, Never>] = [
            jobStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            expenseStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(changePublishers)
            .debounce(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.suppressObservedChanges, self.isCloudSyncAvailable else { return }
                self.hasPendingChanges = true
                self.persistPreferences()

                guard self.isCloudSyncEnabled else { return }
                Task {
                    await self.syncNow(trigger: "Automatic")
                }
            }
            .store(in: &cancellables)
    }

    private func mergeRemoteEnvelope(_ envelope: CloudSyncEnvelope) {
        suppressObservedChanges = true
        jobStore.merge(snapshot: envelope.jobSnapshot)
        expenseStore.merge(snapshot: envelope.expenseSnapshot)
        suppressObservedChanges = false
    }

    private func buildLocalEnvelope() -> CloudSyncEnvelope {
        CloudSyncEnvelope(
            jobSnapshot: jobStore.snapshot(),
            expenseSnapshot: expenseStore.snapshot(),
            updatedAt: Date(),
            deviceID: deviceID
        )
    }

    private func apply(envelope: CloudSyncEnvelope, to record: CKRecord) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        record["payload"] = data as NSData
        record["updatedAt"] = envelope.updatedAt as NSDate
        record["deviceID"] = envelope.deviceID as NSString
    }

    private func envelope(from record: CKRecord) -> CloudSyncEnvelope? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(CloudSyncEnvelope.self, from: data)
    }

    private func persistPreferences() {
        let snapshot = CloudSyncPreferenceSnapshot(
            isEnabled: isCloudSyncEnabled,
            lastSyncAt: lastSyncAt,
            hasPendingChanges: hasPendingChanges
        )

        persistence.save(snapshot, forKey: preferencesKey, updatedAt: Date())
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: status)
            }
        }
    }

    private func fetchRecord() async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord?, Error>) in
            database.fetch(withRecordID: recordID) { record, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: record)
            }
        }
    }

    private func save(record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let savedRecord else {
                    continuation.resume(throwing: NSError(domain: "CareerFuel.CloudSync", code: -1))
                    return
                }

                continuation.resume(returning: savedRecord)
            }
        }
    }

    private func conflictServerRecord(from error: CKError) -> CKRecord? {
        error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
    }

    private func handleCloudKitError(_ error: CKError) {
        hasPendingChanges = true

        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            syncMessage = "Cloud sync is offline right now. Local changes are queued and will merge later."
        case .notAuthenticated:
            syncMessage = "Sign in to iCloud to sync across devices."
        default:
            syncMessage = "Cloud sync failed: \(error.localizedDescription)"
        }

        persistPreferences()
    }
}

private extension CloudSyncManager {
    static let disabledMessage = "Cloud sync is disabled in this build."
}
