import Foundation
import Observation

@MainActor
@Observable
final class MergeRequestsModel {
    let mode: GitLabMergeRequestListMode

    private(set) var mergeRequests: [GitLabMergeRequest] = []
    private(set) var nextPageURL: URL?
    private(set) var loadError: GitLabSessionClientError?
    private(set) var isLoadingInitial = false
    private(set) var isRefreshing = false
    private(set) var isLoadingNextPage = false
    private(set) var didFailRefresh = false
    private(set) var didFailNextPage = false
    private(set) var hasLoaded = false
    var searchText = ""

    private let loader: any GitLabMergeRequestLoading

    init(
        mode: GitLabMergeRequestListMode,
        loader: any GitLabMergeRequestLoading
    ) {
        self.mode = mode
        self.loader = loader
    }

    var displayedMergeRequests: [GitLabMergeRequest] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return mergeRequests
        }

        return mergeRequests.filter {
            Self.matches($0, query: query)
        }
    }

    var authenticationFailure: GitLabSessionClientError? {
        guard loadError?.requiresReauthentication == true else {
            return nil
        }
        return loadError
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        await replaceMergeRequests(isInitial: true)
    }

    func refresh() async {
        await replaceMergeRequests(isInitial: false)
    }

    func loadNextPageIfNeeded(
        after mergeRequest: GitLabMergeRequest
    ) async {
        guard
            mergeRequests.last?.route == mergeRequest.route
        else {
            return
        }
        await loadNextPage()
    }

    func retryNextPage() async {
        await loadNextPage()
    }

    private func replaceMergeRequests(
        isInitial: Bool
    ) async {
        guard
            !isLoadingInitial,
            !isRefreshing,
            !isLoadingNextPage
        else {
            return
        }

        if isInitial {
            isLoadingInitial = true
        } else {
            isRefreshing = true
        }
        loadError = nil
        didFailRefresh = false
        didFailNextPage = false

        defer {
            isLoadingInitial = false
            isRefreshing = false
        }

        do {
            let page = try await loader
                .loadMergeRequestsPage(
                    for: mode,
                    after: nil
                )
            guard !Task.isCancelled else {
                return
            }

            mergeRequests = Self.deduplicated(
                page.mergeRequests
            )
            nextPageURL = page.nextPageURL
            hasLoaded = true
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }

            loadError = error
            didFailRefresh = !isInitial
            hasLoaded = true
        }
    }

    private func loadNextPage() async {
        guard
            let nextPageURL,
            !isLoadingInitial,
            !isRefreshing,
            !isLoadingNextPage
        else {
            return
        }

        isLoadingNextPage = true
        loadError = nil
        didFailRefresh = false
        didFailNextPage = false

        defer {
            isLoadingNextPage = false
        }

        do {
            let page = try await loader
                .loadMergeRequestsPage(
                    for: mode,
                    after: nextPageURL
                )
            guard !Task.isCancelled else {
                return
            }

            mergeRequests = Self.appending(
                page.mergeRequests,
                to: mergeRequests
            )
            self.nextPageURL = page.nextPageURL
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }

            loadError = error
            didFailNextPage = true
        }
    }

    private static func deduplicated(
        _ mergeRequests: [GitLabMergeRequest]
    ) -> [GitLabMergeRequest] {
        appending(mergeRequests, to: [])
    }

    private static func appending(
        _ newMergeRequests: [GitLabMergeRequest],
        to existingMergeRequests: [GitLabMergeRequest]
    ) -> [GitLabMergeRequest] {
        var routes = Set(
            existingMergeRequests.map(\.route)
        )
        var result = existingMergeRequests

        for mergeRequest in newMergeRequests
        where routes.insert(mergeRequest.route).inserted
        {
            result.append(mergeRequest)
        }

        return result
    }

    private static func matches(
        _ mergeRequest: GitLabMergeRequest,
        query: String
    ) -> Bool {
        let users =
            [mergeRequest.author]
            + mergeRequest.assignees
            + mergeRequest.reviewers
        let values = [
            mergeRequest.title,
            mergeRequest.references.full,
            mergeRequest.sourceBranch,
            mergeRequest.targetBranch,
        ]
            + mergeRequest.labels
            + users.flatMap {
                [$0.name, $0.username]
            }

        return values.contains {
            $0.range(
                of: query,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                ]
            ) != nil
        }
    }
}
