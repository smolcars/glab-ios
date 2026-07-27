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
                subtitle: "Couldn’t load",
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
            let result = try await loader.load()
            guard !Task.isCancelled else {
                user = previousUser
                authenticationFailure = previousAuthenticationFailure
                sections = previousSections
                return
            }

            authenticationFailure = authenticationFailure(in: result)

            if case let .success(user) = result.user {
                self.user = user
            }

            for section in HomeDashboardSection.allCases {
                guard let result = result.sections[section] else {
                    sections[section] = .failed(
                        .api(.invalidResponse)
                    )
                    continue
                }

                switch result {
                case let .success(items):
                    sections[section] = .loaded(items)
                case let .failure(error):
                    sections[section] = .failed(error)
                }
            }

            hasLoaded = true
        } catch {
            user = previousUser
            authenticationFailure = previousAuthenticationFailure
            sections = previousSections
        }
    }

    private func authenticationFailure(
        in result: HomeDashboardLoadResult
    ) -> GitLabSessionClientError? {
        if
            case let .failure(error) = result.user,
            error.requiresReauthentication
        {
            return error
        }

        for section in HomeDashboardSection.allCases {
            if
                case let .failure(error) = result.sections[section],
                error.requiresReauthentication
            {
                return error
            }
        }

        return nil
    }
}
