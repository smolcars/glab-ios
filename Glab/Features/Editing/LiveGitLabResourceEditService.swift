import Foundation

nonisolated struct LiveGitLabResourceEditService:
    GitLabResourceEditing,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending
    private let paginatedClient:
        (any GitLabPaginatedSessionRequestSending)?
    private let readInvalidator:
        GitLabResourceReadInvalidator

    init(
        client: any GitLabSessionRequestSending
    ) {
        self.client = client
        paginatedClient =
            client as?
                any GitLabPaginatedSessionRequestSending
        readInvalidator =
            GitLabResourceReadInvalidator(
                client: client
            )
    }

    @concurrent
    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        switch target {
        case let .issue(route):
            let issue = try await client.send(
                GitLabIssueEndpoints.issue(
                    at: route
                )
            )
            return .issue(issue)
        case let .mergeRequest(route):
            let mergeRequest =
                try await client.send(
                    GitLabMergeRequestEndpoints
                        .mergeRequest(at: route)
                )
            return .mergeRequest(
                mergeRequest
            )
        }
    }

    @concurrent
    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        switch target {
        case let .issue(route):
            let endpoint:
                GitLabAPIRequest<GitLabIssue>
            do {
                endpoint =
                    try GitLabIssueEndpoints
                        .update(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let issue = try await client.send(
                endpoint
            )
            return .issue(issue)

        case let .mergeRequest(route):
            let endpoint:
                GitLabAPIRequest<
                    GitLabMergeRequest
                >
            do {
                endpoint =
                    try GitLabMergeRequestEndpoints
                        .update(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let mergeRequest =
                try await client.send(
                    endpoint
                )
            return .mergeRequest(
                mergeRequest
            )
        }
    }

    @concurrent
    func loadLabelsPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >
    {
        try await loadMetadataPage(
            initial:
                GitLabIssueCreationEndpoints
                .labels(
                    projectID: projectID,
                    search: search
                ),
            after: nextPageURL
        )
    }

    @concurrent
    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        try await loadMetadataPage(
            initial:
                GitLabProjectMemberEndpoints
                .members(
                    projectID: projectID,
                    search: search
                ),
            after: nextPageURL
        )
    }

    @concurrent
    func updateMetadata(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceMetadataChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        switch target {
        case let .issue(route):
            let endpoint:
                GitLabAPIRequest<GitLabIssue>
            do {
                endpoint =
                    try GitLabIssueEndpoints
                        .updateMetadata(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let issue = try await client.send(
                endpoint
            )
            return .issue(issue)

        case let .mergeRequest(route):
            let endpoint:
                GitLabAPIRequest<
                    GitLabMergeRequest
                >
            do {
                endpoint =
                    try GitLabMergeRequestEndpoints
                        .updateMetadata(
                            at: route,
                            changes: changes
                        )
            } catch {
                throw .api(.invalidResponse)
            }
            let mergeRequest =
                try await client.send(
                    endpoint
                )
            return .mergeRequest(
                mergeRequest
            )
        }
    }

    @concurrent
    func loadIssueMilestones(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueMilestone]
    {
        try await client.send(
            GitLabIssueCreationEndpoints
                .milestones(
                    projectID: projectID
                )
        )
    }

    @concurrent
    func loadIssueIterations(
        projectID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabIssueIteration]
    {
        do {
            return try await client.send(
                GitLabIssueCreationEndpoints
                    .iterations(
                        projectID: projectID
                    )
            )
        } catch let error {
            switch error {
            case .api(.forbidden),
                 .api(.notFound):
                return []
            default:
                throw error
            }
        }
    }

    @concurrent
    func loadIssuePlanning(
        for issue: GitLabIssue
    ) async throws(GitLabSessionClientError)
        -> GitLabIssuePlanningAvailability
    {
        guard
            issue.projectID > 0,
            issue.iid > 0
        else {
            return .unavailable
        }
        let project = try await client.send(
            GitLabIssueStatusEndpoints
                .project(
                    projectID:
                        issue.projectID
                )
        )
        guard
            project.id == issue.projectID,
            !project.pathWithNamespace
                .isEmpty
        else {
            return .unavailable
        }
        return try await refreshIssuePlanning(
            projectPath:
                project.pathWithNamespace,
            issueIID: issue.iid
        )
    }

    @concurrent
    func refreshIssuePlanning(
        projectPath: String,
        issueIID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabIssuePlanningAvailability
    {
        guard
            !projectPath.isEmpty,
            projectPath.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) == projectPath,
            issueIID > 0
        else {
            return .unavailable
        }
        let endpoint:
            GitLabAPIRequest<
                GitLabIssuePlanningGraphQLResponse
            >
        do {
            endpoint =
                try GitLabIssuePlanningEndpoints
                    .planning(
                        projectPath:
                            projectPath,
                        issueIID:
                            issueIID
                    )
        } catch {
            throw .api(.invalidResponse)
        }
        let response =
            try await client.send(endpoint)
        guard
            let snapshot =
                response.validatedSnapshot(
                    projectPath:
                        projectPath,
                    issueIID:
                        issueIID
                )
        else {
            return .unavailable
        }
        return .supported(snapshot)
    }

    @concurrent
    func updateIssuePlanning(
        from baseline:
            GitLabIssuePlanningSnapshot,
        change:
            GitLabIssuePlanningChange
    ) async throws(GitLabSessionClientError)
        -> GitLabIssuePlanningMutationOutcome
    {
        guard baseline.canUpdate else {
            return .rejected
        }
        let endpoint:
            GitLabAPIRequest<
                GitLabIssuePlanningUpdateGraphQLResponse
            >
        do {
            endpoint =
                try GitLabIssuePlanningEndpoints
                    .update(
                        workItemID:
                            baseline.workItemID,
                        change: change
                    )
        } catch {
            throw .api(.invalidResponse)
        }
        let response =
            try await client.send(endpoint)
        if
            let updated =
                response.validatedSnapshot(
                    baseline: baseline,
                    change: change
                )
        {
            return .updated(updated)
        }
        if response.errors?.isEmpty == false {
            return .deliveryUnknown
        }
        if
            let payload =
                response.data?
                    .workItemUpdate,
            payload.errors?.isEmpty == false,
            payload.workItem == nil
        {
            return .rejected
        }
        return .deliveryUnknown
    }

    @concurrent
    func invalidateAffectedReads(
        for target: GitLabResourceEditTarget
    ) async {
        switch target {
        case let .issue(route):
            await readInvalidator
                .invalidateIssueReads(
                route: route
            )
        case let .mergeRequest(route):
            await readInvalidator
                .invalidateMergeRequestReads(
                route: route
            )
        }
    }

    @concurrent
    func invalidateProjectLabels(
        projectID: Int
    ) async {
        await client.invalidateCachedResponse(
            GitLabIssueCreationEndpoints
                .labels(
                    projectID: projectID
                )
        )
    }

    private func loadMetadataPage<Item>(
        initial:
            GitLabAPIRequest<[Item]>,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<Item>
    where
        Item: Decodable & Sendable
    {
        guard let paginatedClient else {
            throw .api(.invalidResponse)
        }
        let request:
            GitLabAPIPageRequest<[Item]> =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(initial)
                }
        let response =
            try await paginatedClient
                .sendPage(request)
        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }
}
