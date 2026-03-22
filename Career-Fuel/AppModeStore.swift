import Combine
import Foundation

@MainActor
final class AppModeStore: ObservableObject {
    @Published private(set) var mode: AppMode = .jobSearch
    @Published private(set) var acceptedEmployment: AcceptedEmployment?

    private var manualModeOverride: AppMode?
    private var cancellables = Set<AnyCancellable>()

    init(jobStore: JobApplicationStore) {
        jobStore.$employmentSnapshot
            .map(\.acceptedEmployment)
            .removeDuplicates()
            .sink { [weak self] acceptedEmployment in
                guard let self else { return }
                self.acceptedEmployment = acceptedEmployment
                self.applyResolvedMode()
            }
            .store(in: &cancellables)
    }

    var isEmployed: Bool {
        mode == .employed
    }

    var isUsingManualModeOverride: Bool {
        manualModeOverride != nil
    }

    func reopenJobSearch() {
        manualModeOverride = .jobSearch
        applyResolvedMode()
    }

    func resumeAutomaticMode() {
        manualModeOverride = nil
        applyResolvedMode()
    }

    private func applyResolvedMode() {
        let automaticMode: AppMode = acceptedEmployment == nil ? .jobSearch : .employed
        mode = manualModeOverride ?? automaticMode
    }
}
