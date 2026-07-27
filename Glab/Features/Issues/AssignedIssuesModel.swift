import Foundation
import Observation

@MainActor
@Observable
final class AssignedIssuesModel {
    private(set) var issues: [GitLabIssue] = []
    private(set) var nextPageURL: URL?
    private(set) var loadError: GitLabSessionClientError?
    private(set) var isLoadingInitial = false
    private(set) var isRefreshing = false
    private(set) var isLoadingNextPage = false
    private(set) var didFailNextPage = false
    private(set) var hasLoaded = false
    var searchText = ""

    private let loader: any GitLabIssueLoading

    init(loader: any GitLabIssueLoading) {
        self.loader = loader
    }

    var displayedIssues: [GitLabIssue] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return issues
        }

        return issues.filter {
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
        await replaceIssues(isInitial: true)
    }

    func refresh() async {
        await replaceIssues(isInitial: false)
    }

    func loadNextPageIfNeeded(
        after issue: GitLabIssue
    ) async {
        guard issues.last?.route == issue.route else {
            return
        }
        await loadNextPage()
    }

    func retryNextPage() async {
        await loadNextPage()
    }

    private func replaceIssues(
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
        didFailNextPage = false

        defer {
            isLoadingInitial = false
            isRefreshing = false
        }

        do {
            let page = try await loader.loadAssignedIssuesPage(
                after: nil
            )
            guard !Task.isCancelled else {
                return
            }

            issues = Self.deduplicated(page.issues)
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
        didFailNextPage = false

        defer {
            isLoadingNextPage = false
        }

        do {
            let page = try await loader.loadAssignedIssuesPage(
                after: nextPageURL
            )
            guard !Task.isCancelled else {
                return
            }

            issues = Self.appending(
                page.issues,
                to: issues
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
        _ issues: [GitLabIssue]
    ) -> [GitLabIssue] {
        appending(issues, to: [])
    }

    private static func appending(
        _ newIssues: [GitLabIssue],
        to existingIssues: [GitLabIssue]
    ) -> [GitLabIssue] {
        var routes = Set(existingIssues.map(\.route))
        var result = existingIssues

        for issue in newIssues where routes.insert(issue.route).inserted {
            result.append(issue)
        }

        return result
    }

    private static func matches(
        _ issue: GitLabIssue,
        query: String
    ) -> Bool {
        let values = [
            issue.title,
            issue.references.full,
        ]
            + issue.labels
            + issue.assignees.flatMap {
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
