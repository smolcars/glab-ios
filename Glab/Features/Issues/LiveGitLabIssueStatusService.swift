import Foundation

nonisolated enum GitLabIssueStatusAvailability:
    Equatable,
    Sendable
{
    case supported(
        GitLabIssueStatusSnapshot
    )
    case unavailable
}

nonisolated enum GitLabIssueStatusMutationOutcome:
    Equatable,
    Sendable
{
    case updated(
        GitLabIssueStatusUpdateResult
    )
    case rejected
    case deliveryUnknown
}

nonisolated protocol GitLabIssueStatusServing:
    Sendable
{
    func loadStatus(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability

    func refreshStatus(
        projectPath: String,
        issueIID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability

    func updateStatus(
        from baseline:
            GitLabIssueStatusSnapshot,
        to selectedStatus:
            GitLabIssueWorkItemStatus
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusMutationOutcome
}

nonisolated struct LiveGitLabIssueStatusService:
    GitLabIssueStatusServing,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending
    private let apiAccess: GitLabAPIAccess

    init(
        client:
            any GitLabSessionRequestSending,
        apiAccess: GitLabAPIAccess
    ) {
        self.client = client
        self.apiAccess = apiAccess
    }

    @concurrent
    func loadStatus(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        try ensureNotCancelled()
        guard
            route.projectID > 0,
            route.issueIID > 0
        else {
            return .unavailable
        }
        let project = try await client.send(
            GitLabIssueStatusEndpoints
                .project(
                    projectID: route.projectID
                )
        )
        try ensureNotCancelled()

        guard
            project.id == route.projectID,
            let projectPath =
                Self.validatedProjectPath(
                    project.pathWithNamespace
                )
        else {
            return .unavailable
        }

        return try await refreshStatus(
            projectPath: projectPath,
            issueIID: route.issueIID
        )
    }

    @concurrent
    func refreshStatus(
        projectPath: String,
        issueIID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        try ensureNotCancelled()
        guard
            Self.validatedProjectPath(
                projectPath
            ) != nil,
            issueIID > 0
        else {
            return .unavailable
        }

        let endpoint:
            GitLabAPIRequest<
                GitLabIssueStatusGraphQLResponse
            >
        do {
            endpoint =
                try GitLabIssueStatusEndpoints
                    .status(
                        projectPath:
                            projectPath,
                        issueIID: issueIID
                    )
        } catch {
            throw .api(.invalidResponse)
        }

        let response = try await client.send(
            endpoint
        )
        guard
            let snapshot =
                response.validatedSnapshot(
                    projectPath:
                        projectPath,
                    issueIID: issueIID
                )
        else {
            return .unavailable
        }
        return .supported(snapshot)
    }

    @concurrent
    func updateStatus(
        from baseline:
            GitLabIssueStatusSnapshot,
        to selectedStatus:
            GitLabIssueWorkItemStatus
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusMutationOutcome
    {
        try ensureNotCancelled()
        guard apiAccess.canWrite else {
            throw .insufficientAccess(
                required: .write
            )
        }
        guard
            baseline.canUpdate,
            baseline.currentStatus?.id
                != selectedStatus.id,
            baseline.allowedStatuses
                .contains(selectedStatus)
        else {
            return .rejected
        }

        let endpoint:
            GitLabAPIRequest<
                GitLabIssueStatusUpdateGraphQLResponse
            >
        do {
            endpoint =
                try GitLabIssueStatusEndpoints
                    .update(
                        workItemID:
                            baseline
                                .workItemID,
                        statusID:
                            selectedStatus.id
                    )
        } catch {
            throw .api(.invalidResponse)
        }

        let response = try await client.send(
            endpoint
        )
        if
            let result =
                response.validatedResult(
                    workItemID:
                        baseline.workItemID,
                    issueIID:
                        baseline.issueIID,
                    selectedStatus:
                        selectedStatus,
                    baselineState:
                        baseline.state,
                    baselineLockVersion:
                        baseline.lockVersion
                )
        {
            return .updated(result)
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
}

private nonisolated extension LiveGitLabIssueStatusService {
    func ensureNotCancelled()
        throws(GitLabSessionClientError)
    {
        guard !Task.isCancelled else {
            throw .api(.cancelled)
        }
    }

    static func validatedProjectPath(
        _ value: String
    ) -> String? {
        guard
            !value.isEmpty,
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) == value
        else {
            return nil
        }
        return value
    }
}
