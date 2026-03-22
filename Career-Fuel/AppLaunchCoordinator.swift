import Combine
import Foundation
import SwiftUI

@MainActor
final class AppLaunchCoordinator: ObservableObject {
    @Published private(set) var isShowingLaunchOverlay = true

    private let minimumVisibleDuration: Duration
    private var cancellables = Set<AnyCancellable>()
    private var hasFinishedMinimumDuration = false
    private var hasFinishedInitialWarmup = false
    private var isConfigured = false

    init(minimumVisibleDuration: Duration = .milliseconds(700)) {
        self.minimumVisibleDuration = minimumVisibleDuration
    }

    func configureIfNeeded(aiService: AIInsightService) {
        guard !isConfigured else { return }
        isConfigured = true

        Publishers.CombineLatest(
            aiService.$isRefreshingExpenseInsights.removeDuplicates(),
            aiService.$isRefreshingJobInsights.removeDuplicates()
        )
        .map { !$0 && !$1 }
        .removeDuplicates()
        .sink { [weak self] isReady in
            guard let self else { return }
            hasFinishedInitialWarmup = isReady
            finishIfReady()
        }
        .store(in: &cancellables)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.minimumVisibleDuration)
            hasFinishedMinimumDuration = true
            finishIfReady()
        }
    }

    private func finishIfReady() {
        guard isShowingLaunchOverlay, hasFinishedMinimumDuration, hasFinishedInitialWarmup else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            isShowingLaunchOverlay = false
        }
    }
}
