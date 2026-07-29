import Foundation

nonisolated struct GitLabMergeRequestApproval:
    Decodable,
    Equatable,
    Sendable
{
    let user: GitLabAPIUser?
    let approvedAt: Date?

    init(
        user: GitLabAPIUser?,
        approvedAt: Date? = nil
    ) {
        self.user = user
        self.approvedAt = approvedAt
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case user
        case approvedAt = "approved_at"
    }
}

nonisolated struct GitLabMergeRequestApprovalSummary:
    Decodable,
    Equatable,
    Sendable
{
    let approved: Bool?
    let approvalsRequired: Int?
    let approvalsLeft: Int?
    let approvedBy:
        [GitLabMergeRequestApproval]

    init(
        approved: Bool?,
        approvalsRequired: Int?,
        approvalsLeft: Int?,
        approvedBy:
            [GitLabMergeRequestApproval]
    ) {
        self.approved = approved
        self.approvalsRequired =
            approvalsRequired
        self.approvalsLeft = approvalsLeft
        self.approvedBy = approvedBy
    }

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        approved = try container.decodeIfPresent(
            Bool.self,
            forKey: .approved
        )
        approvalsRequired =
            try container.decodeIfPresent(
                Int.self,
                forKey: .approvalsRequired
            )
        approvalsLeft =
            try container.decodeIfPresent(
                Int.self,
                forKey: .approvalsLeft
            )
        approvedBy =
            try container.decodeIfPresent(
                [GitLabMergeRequestApproval].self,
                forKey: .approvedBy
            )
            ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case approved
        case approvalsRequired =
            "approvals_required"
        case approvalsLeft = "approvals_left"
        case approvedBy = "approved_by"
    }
}

nonisolated enum GitLabMergeRequestApprovalAvailability:
    Equatable,
    Sendable
{
    case available(
        GitLabMergeRequestApprovalSummary
    )
    case unavailable
}

nonisolated enum GitLabMergeRequestReadinessOverall:
    Equatable,
    Sendable
{
    case ready
    case blocked
    case pending
    case unknown

    var title: String {
        switch self {
        case .ready:
            "Ready to merge"
        case .blocked:
            "Needs attention"
        case .pending:
            "GitLab is checking"
        case .unknown:
            "Readiness unavailable"
        }
    }
}

nonisolated enum GitLabMergeRequestReadinessCheckKind:
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case pipeline
    case approvals
    case conflicts
    case discussions
    case reviewState

    var title: String {
        switch self {
        case .pipeline:
            "Pipeline"
        case .approvals:
            "Approvals"
        case .conflicts:
            "Conflicts"
        case .discussions:
            "Discussions"
        case .reviewState:
            "Review state"
        }
    }
}

nonisolated enum GitLabMergeRequestReadinessCheckState:
    Equatable,
    Sendable
{
    case satisfied
    case blocked
    case pending
    case notRequired
    case unavailable
    case unknown
}

nonisolated struct GitLabMergeRequestReadinessCheck:
    Equatable,
    Identifiable,
    Sendable
{
    let kind:
        GitLabMergeRequestReadinessCheckKind
    let state:
        GitLabMergeRequestReadinessCheckState
    let title: String
    let detail: String
    let destination: URL?

    var id:
        GitLabMergeRequestReadinessCheckKind
    {
        kind
    }

    var accessibilityLabel: String {
        "\(kind.title), \(title). \(detail)"
    }
}

nonisolated struct GitLabMergeRequestReadiness:
    Equatable,
    Sendable
{
    let overall:
        GitLabMergeRequestReadinessOverall
    let pipeline:
        GitLabMergeRequestReadinessCheck
    let approvals:
        GitLabMergeRequestReadinessCheck
    let conflicts:
        GitLabMergeRequestReadinessCheck
    let discussions:
        GitLabMergeRequestReadinessCheck
    let reviewState:
        GitLabMergeRequestReadinessCheck

    init(
        mergeRequest: GitLabMergeRequest,
        approvalState:
            GitLabResourceDetailState<
                GitLabMergeRequestApprovalAvailability
            >,
        hasRefreshFailure: Bool = false
    ) {
        let status =
            Self.normalized(
                mergeRequest
                    .detailedMergeStatus
            )
        pipeline = Self.pipelineCheck(
            mergeRequest.headPipeline
        )
        approvals = Self.approvalCheck(
            approvalState
        )
        conflicts = Self.conflictCheck(
            mergeRequest.hasConflicts,
            detailedStatus: status
        )
        discussions = Self.discussionCheck(
            mergeRequest
                .blockingDiscussionsResolved,
            detailedStatus: status
        )
        reviewState = Self.reviewStateCheck(
            draft: mergeRequest.draft,
            legacyWorkInProgress:
                mergeRequest
                .legacyWorkInProgress
        )

        let derivedOverall =
            Self.overallState(
                mergeRequestState:
                    mergeRequest.stateKind,
                detailedStatus: status,
                checks: [
                    pipeline,
                    approvals,
                    conflicts,
                    discussions,
                    reviewState,
                ]
            )
        if
            hasRefreshFailure,
            derivedOverall == .ready
        {
            overall = .unknown
        } else {
            overall = derivedOverall
        }
    }

    var checks:
        [GitLabMergeRequestReadinessCheck]
    {
        [
            pipeline,
            approvals,
            conflicts,
            discussions,
            reviewState,
        ]
    }

    var accessibilityLabel: String {
        "Merge readiness, \(overall.title)"
    }

    var compactSummary: String {
        let categories: [
            (
                count: Int,
                singular: String,
                plural: String
            )
        ] = [
            (
                checks.count {
                    $0.state == .blocked
                },
                "needs attention",
                "need attention"
            ),
            (
                checks.count {
                    $0.state == .pending
                },
                "in progress",
                "in progress"
            ),
            (
                checks.count {
                    $0.state == .unavailable
                        || $0.state == .unknown
                },
                "unavailable",
                "unavailable"
            ),
        ]
        let active = categories.filter {
            $0.count > 0
        }

        if active.count == 1,
           let category = active.first
        {
            let noun =
                category.count == 1
                ? "check"
                : "checks"
            let phrase =
                category.count == 1
                ? category.singular
                : category.plural
            return "\(category.count) \(noun) \(phrase)"
        }
        if !active.isEmpty {
            return active.map {
                let phrase =
                    $0.count == 1
                    ? $0.singular
                    : $0.plural
                return "\($0.count) \(phrase)"
            }
            .joined(separator: " · ")
        }

        switch overall {
        case .ready:
            return "All checks clear"
        case .blocked:
            return "Requirements need attention"
        case .pending:
            return "GitLab is checking"
        case .unknown:
            return "Details unavailable"
        }
    }

    private static func overallState(
        mergeRequestState:
            GitLabMergeRequestStateKind,
        detailedStatus: String?,
        checks:
            [GitLabMergeRequestReadinessCheck]
    ) -> GitLabMergeRequestReadinessOverall {
        switch mergeRequestState {
        case .opened:
            break
        case .closed, .merged, .locked:
            return .blocked
        case .unknown:
            return .unknown
        }
        if
            detailedStatus.map(
                blockingDetailedStatuses
                    .contains
            ) == true
                || checks.contains(
                    where: {
                        $0.state == .blocked
                    }
                )
        {
            return .blocked
        }
        if
            detailedStatus.map(
                pendingDetailedStatuses
                    .contains
            ) == true
                || checks.contains(
                    where: {
                        $0.state == .pending
                    }
                )
        {
            return .pending
        }
        guard detailedStatus == "mergeable" else {
            return .unknown
        }
        guard
            !checks.contains(
                where: {
                    $0.state == .unknown
                        || $0.state
                            == .unavailable
                }
            )
        else {
            return .unknown
        }
        return .ready
    }

    private static func pipelineCheck(
        _ pipeline:
            GitLabMergeRequestHeadPipeline?
    ) -> GitLabMergeRequestReadinessCheck {
        guard let pipeline else {
            return check(
                kind: .pipeline,
                state: .notRequired,
                title: "No visible pipeline",
                detail:
                    "GitLab did not return a head pipeline."
            )
        }

        let status = normalized(
            pipeline.status
        )
        switch status {
        case "success":
            return check(
                kind: .pipeline,
                state: .satisfied,
                title: "Passed",
                detail:
                    "The head pipeline succeeded.",
                destination:
                    pipeline.safeWebURL
            )
        case "skipped":
            return check(
                kind: .pipeline,
                state: .satisfied,
                title: "Skipped",
                detail:
                    "The head pipeline was skipped.",
                destination:
                    pipeline.safeWebURL
            )
        case "created":
            return pendingPipelineCheck(
                title: "Created",
                pipeline: pipeline
            )
        case "waiting_for_resource":
            return pendingPipelineCheck(
                title: "Waiting for resources",
                pipeline: pipeline
            )
        case "preparing":
            return pendingPipelineCheck(
                title: "Preparing",
                pipeline: pipeline
            )
        case "pending":
            return pendingPipelineCheck(
                title: "Pending",
                pipeline: pipeline
            )
        case "running":
            return pendingPipelineCheck(
                title: "Running",
                pipeline: pipeline
            )
        case "scheduled":
            return pendingPipelineCheck(
                title: "Scheduled",
                pipeline: pipeline
            )
        case "manual":
            return pendingPipelineCheck(
                title: "Manual action",
                pipeline: pipeline
            )
        case "failed":
            return blockedPipelineCheck(
                title: "Failed",
                pipeline: pipeline
            )
        case "canceled":
            return blockedPipelineCheck(
                title: "Canceled",
                pipeline: pipeline
            )
        case "canceling":
            return blockedPipelineCheck(
                title: "Canceling",
                pipeline: pipeline
            )
        default:
            return check(
                kind: .pipeline,
                state: .unknown,
                title:
                    "Unknown pipeline status",
                detail:
                    "This GitLab version returned an unfamiliar pipeline status.",
                destination:
                    pipeline.safeWebURL
            )
        }
    }

    private static func approvalCheck(
        _ state:
            GitLabResourceDetailState<
                GitLabMergeRequestApprovalAvailability
            >
    ) -> GitLabMergeRequestReadinessCheck {
        switch state {
        case .idle, .loading:
            return check(
                kind: .approvals,
                state: .pending,
                title: "Loading approvals",
                detail:
                    "Checking GitLab approval requirements."
            )
        case .failed:
            return unavailableApprovalCheck()
        case .loaded(.unavailable):
            return unavailableApprovalCheck()
        case let .loaded(.available(summary)):
            return approvalCheck(summary)
        }
    }

    private static func approvalCheck(
        _ summary:
            GitLabMergeRequestApprovalSummary
    ) -> GitLabMergeRequestReadinessCheck {
        if summary.approvalsRequired == 0 {
            return check(
                kind: .approvals,
                state: .notRequired,
                title:
                    "No approval required",
                detail:
                    "GitLab reports no required approvals."
            )
        }
        if
            summary.approved == true
                || (
                    summary.approvalsRequired
                        .map { $0 > 0 }
                        == true
                    && summary.approvalsLeft == 0
                )
        {
            let count =
                summary.approvedBy.count
            let detail =
                if count == 0 {
                    "GitLab reports approval requirements are satisfied."
                } else if count == 1 {
                    "Approved by 1 person."
                } else {
                    "Approved by \(count) people."
                }
            return check(
                kind: .approvals,
                state: .satisfied,
                title: "Approvals complete",
                detail: detail
            )
        }
        if
            let remaining =
                summary.approvalsLeft,
            remaining > 0
        {
            return check(
                kind: .approvals,
                state: .blocked,
                title:
                    remaining == 1
                    ? "1 approval remaining"
                    : "\(remaining) approvals remaining",
                detail:
                    "Required approvals are not complete."
            )
        }
        return check(
            kind: .approvals,
            state: .unknown,
            title: "Approval status unknown",
            detail:
                "GitLab returned incomplete approval information."
        )
    }

    private static func conflictCheck(
        _ hasConflicts: Bool?,
        detailedStatus: String?
    ) -> GitLabMergeRequestReadinessCheck {
        if
            hasConflicts == true
                || detailedStatus == "conflict"
        {
            return check(
                kind: .conflicts,
                state: .blocked,
                title: "Conflicts",
                detail:
                    "The source branch conflicts with the target branch."
            )
        }
        if
            detailedStatus.map(
                conflictPendingStatuses
                    .contains
            ) == true
        {
            return check(
                kind: .conflicts,
                state: .pending,
                title: "Checking conflicts",
                detail:
                    "GitLab is still checking mergeability."
            )
        }
        guard hasConflicts == false else {
            return check(
                kind: .conflicts,
                state: .unknown,
                title:
                    "Conflict status unavailable",
                detail:
                    "GitLab did not return conflict information."
            )
        }
        return check(
            kind: .conflicts,
            state: .satisfied,
            title: "No conflicts",
            detail:
                "GitLab reports no merge conflicts."
        )
    }

    private static func discussionCheck(
        _ resolved: Bool?,
        detailedStatus: String?
    ) -> GitLabMergeRequestReadinessCheck {
        if
            resolved == false
                || detailedStatus
                    == "discussions_not_resolved"
        {
            return check(
                kind: .discussions,
                state: .blocked,
                title:
                    "Unresolved discussions",
                detail:
                    "At least one blocking thread remains unresolved."
            )
        }
        guard resolved == true else {
            return check(
                kind: .discussions,
                state: .unknown,
                title:
                    "Discussion status unavailable",
                detail:
                    "GitLab did not return the blocking discussion state."
            )
        }
        return check(
            kind: .discussions,
            state: .satisfied,
            title:
                "Discussions resolved",
            detail:
                "All blocking discussions are resolved."
        )
    }

    private static func reviewStateCheck(
        draft: Bool?,
        legacyWorkInProgress: Bool?
    ) -> GitLabMergeRequestReadinessCheck {
        guard
            let isDraft =
                draft
                ?? legacyWorkInProgress
        else {
            return check(
                kind: .reviewState,
                state: .unknown,
                title:
                    "Review state unavailable",
                detail:
                    "GitLab did not return a draft state."
            )
        }
        if isDraft {
            return check(
                kind: .reviewState,
                state: .blocked,
                title: "Draft",
                detail:
                    "Mark this merge request ready before merging."
            )
        }
        return check(
            kind: .reviewState,
            state: .satisfied,
            title: "Ready for review",
            detail:
                "This merge request is not a draft."
        )
    }

    private static func pendingPipelineCheck(
        title: String,
        pipeline:
            GitLabMergeRequestHeadPipeline
    ) -> GitLabMergeRequestReadinessCheck {
        check(
            kind: .pipeline,
            state: .pending,
            title: title,
            detail:
                "The head pipeline has not finished.",
            destination:
                pipeline.safeWebURL
        )
    }

    private static func blockedPipelineCheck(
        title: String,
        pipeline:
            GitLabMergeRequestHeadPipeline
    ) -> GitLabMergeRequestReadinessCheck {
        check(
            kind: .pipeline,
            state: .blocked,
            title: title,
            detail:
                "The head pipeline did not succeed.",
            destination:
                pipeline.safeWebURL
        )
    }

    private static func unavailableApprovalCheck()
        -> GitLabMergeRequestReadinessCheck
    {
        check(
            kind: .approvals,
            state: .unavailable,
            title: "Approvals unavailable",
            detail:
                "This GitLab instance or account did not provide approval status."
        )
    }

    private static func check(
        kind:
            GitLabMergeRequestReadinessCheckKind,
        state:
            GitLabMergeRequestReadinessCheckState,
        title: String,
        detail: String,
        destination: URL? = nil
    ) -> GitLabMergeRequestReadinessCheck {
        GitLabMergeRequestReadinessCheck(
            kind: kind,
            state: state,
            title: title,
            detail: detail,
            destination: destination
        )
    }

    private static func normalized(
        _ value: String?
    ) -> String? {
        let normalized = value?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
        return normalized?.isEmpty == false
            ? normalized
            : nil
    }

    private static let pendingDetailedStatuses:
        Set<String> = [
            "approvals_syncing",
            "checking",
            "ci_still_running",
            "preparing",
            "unchecked",
        ]

    private static let conflictPendingStatuses:
        Set<String> = [
            "checking",
            "preparing",
            "unchecked",
        ]

    private static let blockingDetailedStatuses:
        Set<String> = [
            "ci_must_pass",
            "commits_status",
            "conflict",
            "discussions_not_resolved",
            "draft_status",
            "jira_association_missing",
            "merge_request_blocked",
            "merge_time",
            "need_rebase",
            "not_approved",
            "not_open",
            "requested_changes",
            "security_policy_pipeline_check",
            "security_policy_violations",
            "status_checks_must_pass",
            "locked_paths",
            "locked_lfs_files",
            "title_regex",
        ]
}
