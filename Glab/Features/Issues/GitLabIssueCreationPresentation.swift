import Foundation

nonisolated enum GitLabIssueCreationRecoveryAction:
    Equatable,
    Sendable
{
    case retryDraftStorage
    case retryProjectVerification
    case confirmCheckedGitLab
}

nonisolated struct GitLabIssueCreationFailurePresentation:
    Equatable,
    Sendable
{
    let title: String
    let message: String
    let systemImage: String
    let action: GitLabIssueCreationRecoveryAction?

    init(
        failure: GitLabIssueCreationFailure
    ) {
        switch failure {
        case let .validation(error):
            title = "Check the issue"
            message = error.description
            systemImage =
                "exclamationmark.triangle.fill"
            action = nil
        case .restoredProjectUnavailable:
            title = "Choose another project"
            message =
                "The saved project no longer exists or this account cannot access it. The rest of your draft is unchanged."
            systemImage = "folder.badge.questionmark"
            action = nil
        case let .projectVerification(error):
            title = "Couldn’t verify project"
            message =
                GitLabRecoveryPresentation(
                    error: error
                ).message
            systemImage =
                "wifi.exclamationmark"
            action =
                .retryProjectVerification
        case .readOnly:
            title = "Read-only account"
            message =
                "This account cannot create issues. Your draft remains on this device."
            systemImage = "eye.fill"
            action = nil
        case .draftStorage:
            title = "Draft not saved"
            message =
                "Glab could not protect this draft on this device. Try again before closing or creating the issue."
            systemImage =
                "externaldrive.badge.exclamationmark"
            action = .retryDraftStorage
        case let .mutation(error, certainty):
            switch certainty {
            case .rejected:
                title = "Issue not created"
                message =
                    GitLabRecoveryPresentation(
                        error: error
                    ).message
                systemImage =
                    "exclamationmark.triangle.fill"
                action = nil
            case .deliveryUnknown:
                self = Self.unknownDelivery
            }
        case .invalidAuthoritativeResponse,
             .deliveryCheckRequired:
            self = Self.unknownDelivery
        }
    }

    private static var unknownDelivery: Self {
        Self(
            title: "Creation status unknown",
            message:
                "GitLab may already have created this issue. Check the project before allowing another attempt.",
            systemImage: "questionmark.circle.fill",
            action: .confirmCheckedGitLab
        )
    }

    private init(
        title: String,
        message: String,
        systemImage: String,
        action: GitLabIssueCreationRecoveryAction?
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
    }
}

nonisolated enum GitLabIssueCreationDateBridge {
    static func dueDate(
        from date: Date,
        calendar: Calendar = .current
    ) -> GitLabIssueDueDate {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return GitLabIssueDueDate(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    static func date(
        from dueDate: GitLabIssueDueDate,
        calendar: Calendar = .current
    ) -> Date? {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: dueDate.year,
                month: dueDate.month,
                day: dueDate.day
            )
        )
    }
}
