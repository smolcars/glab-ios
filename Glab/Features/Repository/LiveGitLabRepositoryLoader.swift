import Foundation

nonisolated protocol GitLabRepositoryBrowsing:
    Sendable
{
    func loadTreePage(
        projectID: Int,
        ref: String,
        path: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryEntryPage

    func loadTreeFirstPage(
        projectID: Int,
        ref: String,
        path: String,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabRepositoryEntry
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadBranchesPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryBranchPage

    func loadBranch(
        projectID: Int,
        name: String
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryBranch

    func loadSearchPage(
        projectID: Int,
        ref: String,
        query: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositorySearchPage
}

nonisolated protocol GitLabRepositorySourceLoading:
    Sendable
{
    func loadSource(
        at route: GitLabRepositoryFileRoute
    ) async throws(GitLabRepositorySourceLoadError)
        -> GitLabSourceDocument
}

nonisolated protocol GitLabRepositoryLoading:
    GitLabRepositoryBrowsing,
    GitLabRepositorySourceLoading
{}

extension GitLabRepositoryBrowsing {
    func loadTreeFirstPage(
        projectID: Int,
        ref: String,
        path: String,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabRepositoryEntry
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadTreePage(
            projectID: projectID,
            ref: ref,
            path: path,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: GitLabResourcePage(
                    items: page.entries,
                    nextPageURL:
                        page.nextPageURL
                ),
                source: .network
            )
        )
    }
}

nonisolated struct LiveGitLabRepositoryLoader:
    GitLabRepositoryLoading,
    Sendable
{
    static let maximumSourceByteCount =
        10 * 1_024 * 1_024

    private let client:
        any GitLabPaginatedSessionRequestSending
            & GitLabRawFileSessionDownloading

    init(
        client:
            any GitLabPaginatedSessionRequestSending
                & GitLabRawFileSessionDownloading
    ) {
        self.client = client
    }

    @concurrent
    func loadTreePage(
        projectID: Int,
        ref: String,
        path: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryEntryPage
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabRepositoryEntry]
            > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabRepositoryEndpoints
                        .tree(
                            projectID: projectID,
                            ref: ref,
                            path: path
                        )
                )
            }
        let response = try await client
            .sendPage(request)

        return GitLabRepositoryEntryPage(
            entries: response.value,
            nextPageURL:
                response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadTreeFirstPage(
        projectID: Int,
        ref: String,
        path: String,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabRepositoryEntry
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabRepositoryEndpoints
                    .tree(
                        projectID: projectID,
                        ref: ref,
                        path: path
                    )
            ),
            cachePolicy: .repositoryTree,
            refreshBehavior: refreshBehavior
        ) {
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: $0
                )
            )
        }
    }

    @concurrent
    func loadBranchesPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryBranchPage
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabRepositoryBranch]
            > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabRepositoryEndpoints
                        .branches(
                            projectID: projectID,
                            search: search
                        )
                )
            }
        let response = try await client
            .sendPage(request)

        return GitLabRepositoryBranchPage(
            branches: response.value,
            nextPageURL:
                response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadBranch(
        projectID: Int,
        name: String
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryBranch
    {
        try await client.send(
            GitLabRepositoryEndpoints.branch(
                projectID: projectID,
                name: name
            )
        )
    }

    @concurrent
    func loadSearchPage(
        projectID: Int,
        ref: String,
        query: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositorySearchPage
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabRepositorySearchResult]
            > =
            if let nextPageURL {
                .next(nextPageURL)
            } else {
                .initial(
                    GitLabRepositoryEndpoints
                        .search(
                            projectID: projectID,
                            ref: ref,
                            query: query
                        )
                )
            }
        let response = try await client
            .sendPage(request)

        return GitLabRepositorySearchPage(
            results: response.value,
            nextPageURL:
                response.metadata.nextPageURL
        )
    }

    @concurrent
    func loadSource(
        at route: GitLabRepositoryFileRoute
    ) async throws(GitLabRepositorySourceLoadError)
        -> GitLabSourceDocument
    {
        let directory = FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "glab-source-"
                    + UUID().uuidString,
                directoryHint: .isDirectory
            )
        do {
            try FileManager.default
                .createDirectory(
                    at: directory,
                    withIntermediateDirectories:
                        false
                )
        } catch {
            throw .storage
        }
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }

        do {
            let downloaded = try await client
                .downloadRawFile(
                    GitLabRepositoryEndpoints
                        .rawFile(at: route),
                    maximumByteCount:
                        Self.maximumSourceByteCount,
                    temporaryDirectory:
                        directory
                )
            try Task.checkCancellation()
            let data = try Data(
                contentsOf:
                    downloaded.fileURL,
                options: .mappedIfSafe
            )
            try Task.checkCancellation()
            return try GitLabSourceDocument
                .decode(
                    data,
                    fileName: route.fileName
                )
        } catch {
            throw Self.mapSourceError(error)
        }
    }

    private static func mapSourceError(
        _ error: any Error
    ) -> GitLabRepositorySourceLoadError {
        if
            let error = error as?
                GitLabRepositorySourceLoadError
        {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        if
            let error = error as?
                GitLabRawFileSessionError
        {
            switch error {
            case let .session(error):
                return .session(error)
            case .responseTooLarge:
                return .tooLarge
            case .incompleteResponse:
                return .incomplete
            case .unsafeRedirect:
                return .unsafeRedirect
            case .storageFailure:
                return .storage
            }
        }
        return .storage
    }
}
