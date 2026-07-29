import Foundation

nonisolated enum GitLabMergeRequestMergeAction:
    Equatable,
    Sendable
{
    case mergeNow
    case autoMerge

    var title: String {
        switch self {
        case .mergeNow:
            "Merge"
        case .autoMerge:
            "Set auto-merge"
        }
    }
}

nonisolated enum
    GitLabMergeRequestMergeBlockReason:
    Equatable,
    Hashable,
    Sendable
{
    case readOnly
    case permissionDenied
    case notOpen
    case draft
    case missingHeadSHA
    case conflict
    case unresolvedDiscussions
    case approvals
    case pipeline
    case serverRequirement
}

nonisolated enum
    GitLabMergeRequestMergeEligibility:
    Equatable,
    Sendable
{
    case mergeNow
    case autoMerge
    case alreadyAutoMerging
    case blocked(
        [GitLabMergeRequestMergeBlockReason]
    )
    case checking
    case unavailable

    init(
        mergeRequest: GitLabMergeRequest,
        readiness:
            GitLabMergeRequestReadiness,
        apiAccess: GitLabAPIAccess
    ) {
        guard apiAccess.canWrite else {
            self = .blocked([.readOnly])
            return
        }

        var blockers:
            [GitLabMergeRequestMergeBlockReason] =
            []
        if
            mergeRequest.userPermissions?
                .canMerge == false
        {
            blockers.append(
                .permissionDenied
            )
        }
        if
            mergeRequest.stateKind
                != .opened
        {
            blockers.append(.notOpen)
        }

        guard
            let isDraft =
                mergeRequest.draft
                ?? mergeRequest
                    .legacyWorkInProgress
        else {
            self = blockers.isEmpty
                ? .unavailable
                : .blocked(blockers)
            return
        }
        if isDraft {
            blockers.append(.draft)
        }
        if mergeRequest.diffHeadSHA == nil {
            blockers.append(.missingHeadSHA)
        }
        if
            mergeRequest.hasConflicts
                == true
                || readiness.conflicts.state
                    == .blocked
        {
            blockers.append(.conflict)
        }
        if
            mergeRequest
                .blockingDiscussionsResolved
                == false
                || readiness.discussions.state
                    == .blocked
        {
            blockers.append(
                .unresolvedDiscussions
            )
        }
        if readiness.approvals.state == .blocked {
            blockers.append(.approvals)
        }
        if readiness.pipeline.state == .blocked {
            blockers.append(.pipeline)
        }

        if !blockers.isEmpty {
            self = .blocked(
                Self.uniqued(blockers)
            )
            return
        }

        if
            mergeRequest
                .mergeWhenPipelineSucceeds
                == true
        {
            self = .alreadyAutoMerging
            return
        }

        guard
            let status =
                Self.normalized(
                    mergeRequest
                        .detailedMergeStatus
                )
        else {
            self = .unavailable
            return
        }
        if
            Self.checkingStatuses
                .contains(status)
        {
            self = .checking
            return
        }
        guard
            Self.hardChecksAreKnown(
                readiness
            )
        else {
            self = .unavailable
            return
        }
        if
            status == "mergeable",
            readiness.overall == .ready
        {
            self = .mergeNow
            return
        }
        if
            status == "ci_still_running",
            readiness.pipeline.state
                == .pending,
            Self.isRecognizedPendingPipeline(
                mergeRequest.headPipeline
            ),
            Self.nonPipelineChecksAllowMerge(
                readiness
            )
        {
            self = .autoMerge
            return
        }
        if Self.blockingStatuses.contains(status) {
            self = .blocked(
                Self.blockers(
                    from: readiness
                )
            )
            return
        }
        self = .unavailable
    }
}

private nonisolated extension
    GitLabMergeRequestMergeEligibility
{
    static func hardChecksAreKnown(
        _ readiness:
            GitLabMergeRequestReadiness
    ) -> Bool {
        [
            readiness.approvals,
            readiness.conflicts,
            readiness.discussions,
            readiness.reviewState,
        ].allSatisfy {
            $0.state != .unknown
                && $0.state != .unavailable
                && $0.state != .pending
        }
    }

    static func nonPipelineChecksAllowMerge(
        _ readiness:
            GitLabMergeRequestReadiness
    ) -> Bool {
        [
            readiness.approvals,
            readiness.conflicts,
            readiness.discussions,
            readiness.reviewState,
        ].allSatisfy {
            $0.state == .satisfied
                || $0.state == .notRequired
        }
    }

    static func isRecognizedPendingPipeline(
        _ pipeline:
            GitLabMergeRequestHeadPipeline?
    ) -> Bool {
        guard
            let status =
                normalized(
                    pipeline?.status
                )
        else {
            return false
        }
        return pendingPipelineStatuses
            .contains(status)
    }

    static func blockers(
        from readiness:
            GitLabMergeRequestReadiness
    ) -> [
        GitLabMergeRequestMergeBlockReason
    ] {
        var blockers:
            [GitLabMergeRequestMergeBlockReason] =
            []
        if readiness.pipeline.state == .blocked {
            blockers.append(.pipeline)
        }
        if readiness.approvals.state == .blocked {
            blockers.append(.approvals)
        }
        if readiness.conflicts.state == .blocked {
            blockers.append(.conflict)
        }
        if readiness.discussions.state == .blocked {
            blockers.append(
                .unresolvedDiscussions
            )
        }
        if readiness.reviewState.state == .blocked {
            blockers.append(.draft)
        }
        if blockers.isEmpty {
            blockers.append(
                .serverRequirement
            )
        }
        return uniqued(blockers)
    }

    static func uniqued(
        _ reasons:
            [GitLabMergeRequestMergeBlockReason]
    ) -> [
        GitLabMergeRequestMergeBlockReason
    ] {
        var seen:
            Set<
                GitLabMergeRequestMergeBlockReason
            > = []
        return reasons.filter {
            seen.insert($0).inserted
        }
    }

    static func normalized(
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

    static let checkingStatuses:
        Set<String> = [
            "approvals_syncing",
            "checking",
            "preparing",
            "unchecked",
        ]

    static let pendingPipelineStatuses:
        Set<String> = [
            "created",
            "waiting_for_resource",
            "preparing",
            "pending",
            "running",
            "scheduled",
            "manual",
        ]

    static let blockingStatuses:
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
