import SwiftUI

struct GitLabIssueStatusControl: View {
    let model: GitLabIssueStatusModel
    let isExternallyDisabled: Bool
    let actionDidFinish: () -> Void

    var body: some View {
        if
            case let .supported(
                snapshot,
                isStale
            ) = model.state
        {
            if model.requiresDeliveryCheck {
                checkGitLabButton
            } else if
                model.apiAccess.canWrite,
                snapshot.canUpdate
            {
                statusMenu(
                    snapshot: snapshot,
                    isStale: isStale
                )
            } else {
                statusLabel(
                    snapshot: snapshot,
                    isStale: isStale
                )
            }
        }
    }

    private func statusMenu(
        snapshot:
            GitLabIssueStatusSnapshot,
        isStale: Bool
    ) -> some View {
        Menu {
            ForEach(
                snapshot.allowedStatuses
            ) { status in
                Button {
                    Task {
                        await model.select(
                            status
                        )
                        actionDidFinish()
                    }
                } label: {
                    Label(
                        status.name,
                        systemImage:
                            GitLabIssueStatusPresentation(
                                status: status,
                                isStale: false
                            )
                            .systemImage
                    )

                    if
                        status.id
                            == snapshot
                                .currentStatus?
                                .id
                    {
                        Image(
                            systemName:
                                "checkmark"
                        )
                    }
                }
                .disabled(
                    status.id
                        == snapshot
                            .currentStatus?
                            .id
                )
                .accessibilityHint(
                    status.description
                        ?? ""
                )
            }
        } label: {
            statusLabel(
                snapshot: snapshot,
                isStale: isStale,
                interactionHint:
                    isStale
                    ? "Selects an allowed status after checking GitLab for the latest value."
                    : "Shows statuses allowed by this issue’s lifecycle."
            )
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(
            isExternallyDisabled
                || model.isBusy
        )
        .accessibilityIdentifier(
            "issues.status.menu"
        )
    }

    private func statusLabel(
        snapshot:
            GitLabIssueStatusSnapshot,
        isStale: Bool,
        interactionHint: String =
            "Status is read-only."
    ) -> some View {
        let presentation =
            GitLabIssueStatusPresentation(
                status:
                    snapshot
                        .currentStatus,
                isStale: isStale
            )

        return HStack(spacing: 6) {
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(
                    systemName:
                        presentation
                            .systemImage
                )
            }

            Text(presentation.title)
                .lineLimit(1)

            if isStale {
                Image(
                    systemName:
                        "exclamationmark.triangle.fill"
                )
                .font(.caption2)
            }
        }
        .font(
            .subheadline.weight(.semibold)
        )
        .foregroundStyle(
            color(for: presentation.tone)
        )
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            presentation
                .accessibilityLabel
        )
        .accessibilityHint(
            [
                presentation
                    .accessibilityHint,
                interactionHint,
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        )
    }

    private var checkGitLabButton:
        some View
    {
        Button {
            Task {
                await model.checkGitLab()
                actionDidFinish()
            }
        } label: {
            if model.isCheckingGitLab {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(
                    systemName:
                        "arrow.triangle.2.circlepath"
                )
            }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(
            isExternallyDisabled
                || model.isBusy
        )
        .accessibilityLabel(
            "Check work item status on GitLab"
        )
        .accessibilityHint(
            "Verifies whether the previous status change was applied."
        )
        .accessibilityIdentifier(
            "issues.status.checkGitLab"
        )
    }

    private func color(
        for tone:
            GitLabIssueStatusTone
    ) -> Color {
        switch tone {
        case .secondary:
            .secondary
        case .active:
            .blue
        case .complete:
            .green
        case .canceled:
            .purple
        }
    }
}
