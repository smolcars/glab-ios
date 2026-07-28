import Foundation
import Observation

@MainActor
@Observable
final class HomeDashboardModel {
    private(set) var user: GitLabAuthenticatedUser?
    private(set) var authenticationFailure: GitLabSessionClientError?
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    private let loader: any HomeDashboardLoading
    private var sections: [
        HomeDashboardSection: HomeDashboardSectionState
    ]

    init(loader: any HomeDashboardLoading) {
        self.loader = loader
        sections = Dictionary(
            uniqueKeysWithValues: HomeDashboardSection.allCases.map {
                ($0, .idle)
            }
        )
    }

    var hasTotalWorkFailure: Bool {
        HomeDashboardSection.allCases.allSatisfy {
            if case .failed = state(for: $0) {
                true
            } else {
                false
            }
        }
    }

    func state(
        for section: HomeDashboardSection
    ) -> HomeDashboardSectionState {
        sections[section] ?? .idle
    }

    func presentation(
        for section: HomeDashboardSection
    ) -> HomeDashboardRowPresentation {
        switch state(for: section) {
        case .idle, .loading:
            HomeDashboardRowPresentation(
                status: .loading,
                subtitle: "Loading…",
                accessibilityValue: "Loading"
            )
        case let .loaded(items) where items.isEmpty:
            HomeDashboardRowPresentation(
                status: .empty,
                subtitle: section.emptyMessage,
                accessibilityValue: section.emptyMessage
            )
        case let .loaded(items):
            HomeDashboardRowPresentation(
                status: .content,
                subtitle: items[0].title,
                accessibilityValue: "Latest preview: \(items[0].title)"
            )
        case let .failed(error):
            HomeDashboardRowPresentation(
                status: .failed,
                subtitle: GitLabRecoveryPresentation(error: error).title,
                accessibilityValue: error.description
            )
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await load(isInitial: true)
    }

    func refresh() async {
        await load(isInitial: false)
    }

    private func load(isInitial: Bool) async {
        guard !isLoading else {
            return
        }

        let previousUser = user
        let previousAuthenticationFailure = authenticationFailure
        let previousSections = sections
        isLoading = true
        authenticationFailure = nil

        if isInitial {
            sections = Dictionary(
                uniqueKeysWithValues: HomeDashboardSection.allCases.map {
                    ($0, .loading)
                }
            )
        }

        defer {
            isLoading = false
        }

        do {
            try await loader.load { [weak self] update in
                await self?.apply(update)
            }
            guard !Task.isCancelled else {
                user = previousUser
                authenticationFailure = previousAuthenticationFailure
                sections = previousSections
                return
            }

            hasLoaded = true
        } catch {
            user = previousUser
            authenticationFailure = previousAuthenticationFailure
            sections = previousSections
        }
    }

    private func apply(
        _ update: HomeDashboardLoadUpdate
    ) {
        switch update {
        case let .user(.success(user)):
            self.user = user
        case let .user(.failure(error)):
            if error.requiresReauthentication {
                authenticationFailure = error
            }
        case let .section(section, .success(items)):
            sections[section] = .loaded(items)
        case let .section(section, .failure(error)):
            sections[section] = .failed(error)
            if error.requiresReauthentication {
                authenticationFailure = error
            }
        }
    }
}
