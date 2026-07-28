import Foundation

nonisolated enum GitLabDiscussionResolutionAction:
    Equatable,
    Sendable
{
    case toggle
    case checkGitLab
    case retry
}

nonisolated struct
    GitLabDiscussionResolutionPresentation:
    Equatable,
    Sendable
{
    let action:
        GitLabDiscussionResolutionAction?
    let actionTitle: String
    let statusTitle: String?
    let failureMessage: String?
    let showsProgress: Bool
    let isActionEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let accessibilityIdentifier: String

    init(
        status:
            GitLabDiscussionResolutionStatus,
        apiAccess: GitLabAPIAccess,
        discussionID: String
    ) {
        accessibilityIdentifier =
            "discussion.resolution."
            + discussionID

        guard apiAccess.canWrite else {
            action = nil
            actionTitle = "Read-only"
            statusTitle =
                Self.authoritativeStatus(
                    status
                )
            failureMessage =
                "This account has read-only API access."
            showsProgress = false
            isActionEnabled = false
            accessibilityLabel =
                "Thread resolution unavailable"
            accessibilityValue =
                status.isResolved
                    ? "Resolved"
                    : "Unresolved"
            accessibilityHint =
                "Sign in with write access to change this discussion."
            return
        }

        failureMessage =
            Self.failureMessage(
                status.failure
            )
        switch status.phase {
        case .idle:
            action = .toggle
            actionTitle =
                status.isResolved
                    ? "Reopen"
                    : "Resolve"
            statusTitle =
                Self.authoritativeStatus(
                    status
                )
            showsProgress = false
            isActionEnabled = true
            accessibilityLabel =
                status.isResolved
                    ? "Reopen thread"
                    : "Resolve thread"
            accessibilityValue =
                status.isResolved
                    ? "Resolved"
                    : "Unresolved"
            accessibilityHint =
                status.isResolved
                    ? "Reopens this discussion on GitLab."
                    : "Resolves this discussion on GitLab."
        case .pending:
            let resolving =
                status.desiredResolved
                    != false
            action = nil
            actionTitle =
                resolving
                    ? "Resolving…"
                    : "Reopening…"
            statusTitle =
                resolving
                    ? "Resolution pending"
                    : "Reopen pending"
            showsProgress = true
            isActionEnabled = false
            accessibilityLabel =
                resolving
                    ? "Resolving thread"
                    : "Reopening thread"
            accessibilityValue =
                statusTitle ?? ""
            accessibilityHint =
                "Waits for GitLab to confirm the change."
        case .deliveryUnknown:
            let resolving =
                status.desiredResolved
                    != false
            action = .checkGitLab
            actionTitle = "Check GitLab"
            statusTitle =
                resolving
                    ? "Resolution not confirmed"
                    : "Reopen not confirmed"
            showsProgress = false
            isActionEnabled = true
            accessibilityLabel =
                "Check thread resolution on GitLab"
            accessibilityValue =
                statusTitle ?? ""
            accessibilityHint =
                "Checks GitLab without sending another change."
        case .checkingGitLab:
            let resolving =
                status.desiredResolved
                    != false
            action = nil
            actionTitle =
                "Checking GitLab…"
            statusTitle =
                resolving
                    ? "Resolution not confirmed"
                    : "Reopen not confirmed"
            showsProgress = true
            isActionEnabled = false
            accessibilityLabel =
                "Checking thread resolution on GitLab"
            accessibilityValue =
                statusTitle ?? ""
            accessibilityHint =
                "Waits for GitLab to report the current state."
        case .retryAvailable:
            let resolving =
                status.desiredResolved
                    != false
            action = .retry
            actionTitle =
                resolving
                    ? "Retry resolve"
                    : "Retry reopen"
            statusTitle =
                resolving
                    ? "Still unresolved"
                    : "Still resolved"
            showsProgress = false
            isActionEnabled = true
            accessibilityLabel =
                resolving
                    ? "Retry resolving thread"
                    : "Retry reopening thread"
            accessibilityValue =
                statusTitle ?? ""
            accessibilityHint =
                "Sends one new change to GitLab."
        case .rejected:
            action = .toggle
            actionTitle =
                status.isResolved
                    ? "Reopen"
                    : "Resolve"
            statusTitle =
                Self.authoritativeStatus(
                    status
                )
            showsProgress = false
            isActionEnabled = true
            accessibilityLabel =
                status.isResolved
                    ? "Reopen thread"
                    : "Resolve thread"
            accessibilityValue =
                status.isResolved
                    ? "Resolved"
                    : "Unresolved"
            accessibilityHint =
                status.isResolved
                    ? "Retries reopening this discussion on GitLab."
                    : "Retries resolving this discussion on GitLab."
        }
    }

    private static func authoritativeStatus(
        _ status:
            GitLabDiscussionResolutionStatus
    ) -> String? {
        guard status.isResolved else {
            return nil
        }
        guard
            let resolvedBy =
                status.resolvedBy
        else {
            return "Resolved"
        }
        return "Resolved by "
            + resolvedBy.displayName
    }

    private static func failureMessage(
        _ failure:
            GitLabDiscussionResolutionFailure?
    ) -> String? {
        guard let failure else {
            return nil
        }
        switch failure {
        case .readOnly:
            return "This account has read-only API access."
        case .inactiveAccount:
            return "This GitLab account is no longer active."
        case .mutation(
            .request(.api(.forbidden)),
            _
        ):
            return "GitLab did not allow this thread change."
        case let .mutation(
            error,
            certainty
        ):
            if certainty == .deliveryUnknown {
                return "GitLab may have received the change. Check before retrying."
            }
            return error.description
        case let .reconciliation(error):
            return "Glab could not confirm the thread state. "
                + error.description
        }
    }
}
