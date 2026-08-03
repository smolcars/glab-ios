import SwiftUI

nonisolated enum GitLabIcon:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case alertManagement = "alert-management"
    case commit
    case epic
    case group
    case issueClosed = "issue-closed"
    case job
    case merged = "merge"
    case mergeRequest = "merge-request"
    case mergeRequestClosed = "merge-request-close"
    case mergeRequestOpen = "merge-request-open"
    case pipeline
    case project
    case pipelineCanceled = "status_canceled"
    case pipelineCreated = "status_created"
    case pipelineFailed = "status_failed"
    case pipelineManual = "status_manual"
    case pipelinePending = "status_pending"
    case pipelinePreparing = "status_preparing"
    case pipelineRunning = "status_running"
    case pipelineScheduled = "status_scheduled"
    case pipelineSkipped = "status_skipped"
    case pipelineSuccess = "status_success"
    case todoAdd = "todo-add"
    case todoDone = "todo-done"
    case workItemIssue = "work-item-issue"

    var assetName: String {
        rawValue
    }

    var designedPointSize: CGFloat {
        switch self {
        case .pipelineCanceled,
             .pipelineCreated,
             .pipelineFailed,
             .pipelineManual,
             .pipelinePending,
             .pipelinePreparing,
             .pipelineRunning,
             .pipelineScheduled,
             .pipelineSkipped,
             .pipelineSuccess:
            14
        default:
            16
        }
    }
}

struct GitLabIconView: View {
    let icon: GitLabIcon
    let pointSize: CGFloat

    init(
        _ icon: GitLabIcon,
        pointSize: CGFloat? = nil
    ) {
        self.icon = icon
        self.pointSize =
            pointSize ?? icon.designedPointSize
    }

    var body: some View {
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(
                width: pointSize,
                height: pointSize
            )
            .accessibilityHidden(true)
    }
}
