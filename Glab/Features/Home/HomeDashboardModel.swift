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
    private var refreshFailures: [
        HomeDashboardSection: GitLabSessionClientError
    ] = [:]

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
        let refreshFailure = refreshFailures[section]

        return switch state(for: section) {
        case .idle, .loading:
            HomeDashboardRowPresentation(
                status: .loading,
                subtitle: "Loading…",
                accessibilityValue: "Loading"
            )
        case let .loaded(items) where items.isEmpty:
            HomeDashboardRowPresentation(
                status:
                    refreshFailure == nil
                    ? .empty
                    : .stale,
                subtitle: section.emptyMessage,
                accessibilityValue:
                    accessibilityValue(
                        section.emptyMessage,
                        refreshFailure: refreshFailure
                    )
            )
        case let .loaded(items):
            HomeDashboardRowPresentation(
                status:
                    refreshFailure == nil
                    ? .content
                    : .stale,
                subtitle: items[0].title,
                accessibilityValue:
                    accessibilityValue(
                        "Latest preview: \(items[0].title)",
                        refreshFailure: refreshFailure
                    )
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

    func reconcileEditedResource(
        _ result: GitLabResourceEditResult
    ) {
        switch result {
        case let .issue(issue):
            reconcileLoadedPreview(
                GitLabHomeWorkItem(
                    id:
                        "issue:\(issue.projectID):\(issue.iid)",
                    title: issue.title,
                    detail: issue.references.full,
                    webURL: issue.webURL
                ),
                in: [.assignedIssues]
            )
        case let .mergeRequest(mergeRequest):
            reconcileLoadedPreview(
                GitLabHomeWorkItem(
                    id:
                        "merge-request:\(mergeRequest.projectID):\(mergeRequest.iid)",
                    title: mergeRequest.title,
                    detail:
                        mergeRequest.references.full,
                    webURL: mergeRequest.webURL
                ),
                in: [
                    .assignedMergeRequests,
                    .reviewRequests,
                ]
            )
        }
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
            refreshFailures.removeAll()
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
            try await loader.load(
                refreshBehavior:
                    isInitial ? .ifStale : .always
            ) { [weak self] update in
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
            refreshFailures[section] = nil
        case let .section(section, .failure(error)):
            if case .loaded = sections[section] {
                refreshFailures[section] = error
            } else {
                sections[section] = .failed(error)
            }
            if error.requiresReauthentication {
                authenticationFailure = error
            }
        }
    }

    private func accessibilityValue(
        _ content: String,
        refreshFailure: GitLabSessionClientError?
    ) -> String {
        guard refreshFailure != nil else {
            return content
        }

        return "\(content). Could not refresh; showing saved data."
    }

    private func reconcileLoadedPreview(
        _ item: GitLabHomeWorkItem,
        in candidateSections: [HomeDashboardSection]
    ) {
        for section in candidateSections {
            guard
                case var .loaded(items) =
                    sections[section],
                let index = items.firstIndex(
                    where: { $0.id == item.id }
                )
            else {
                continue
            }

            items[index] = item
            sections[section] = .loaded(items)
        }
    }
}
