import SwiftUI

struct GitLabMergeRequestReadinessView: View {
    let readiness:
        GitLabMergeRequestReadiness
    let approvalError:
        GitLabSessionClientError?
    let mergeModel:
        GitLabMergeRequestMergeModel
    let retryApproval: () -> Void
    let openPipelines: () -> Void
    @State private var isExpanded = false

    var body: some View {
        GitLabDetailSection(
            title: "Merge readiness"
        ) {
            VStack(spacing: 0) {
                summaryControl

                if isExpanded {
                    ForEach(readiness.checks) {
                        check in
                        Divider()
                            .padding(
                                .leading,
                                44
                            )

                        checkRow(check)
                    }
                }
            }
            .background(
                Color.glabRaisedSurface,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

            if let approvalError {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t update approvals",
                    error: approvalError,
                    accessibilityIdentifier:
                        "mergeRequests.readiness.approvalError",
                    retry: retryApproval
                )
                .padding(.top, 10)
            }
        }
    }

    private var summaryControl: some View {
        HStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            readiness.overall
                            .systemImage
                    )
                    .font(.glabBody)
                    .foregroundStyle(
                        readiness.overall.tint
                    )
                    .frame(width: 22)
                    .accessibilityHidden(true)

                    VStack(
                        alignment: .leading,
                        spacing: 1
                    ) {
                        Text(
                            readiness.overall.title
                        )
                        .font(
                            .glabCallout.weight(
                                .semibold
                            )
                        )

                        Text(
                            readiness.compactSummary
                        )
                        .font(.glabCaption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                    Image(
                        systemName:
                            isExpanded
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(
                        .glabCaption.weight(.semibold)
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(
                children: .ignore
            )
            .accessibilityLabel(
                readiness.accessibilityLabel
            )
            .accessibilityValue(
                readiness.compactSummary
                    + (isExpanded
                        ? ", expanded"
                        : ", collapsed")
            )
            .accessibilityHint(
                isExpanded
                    ? "Collapses merge readiness details."
                    : "Expands merge readiness details."
            )
            .accessibilityIdentifier(
                "mergeRequests.readiness.overall"
            )

            mergeActionControl
                .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var mergeActionControl:
        some View
    {
        if mergeModel.isBusy {
            ProgressView()
                .controlSize(.small)
                .frame(width: 44, height: 44)
                .accessibilityLabel(
                    "Checking merge request"
                )
        } else {
            switch mergeModel.eligibility {
            case .mergeNow:
                mergeButton(for: .mergeNow)
            case .autoMerge:
                mergeButton(for: .autoMerge)
            case .alreadyAutoMerging:
                Image(
                    systemName:
                        "clock.badge.checkmark"
                )
                .font(.glabBody)
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
                .accessibilityLabel(
                    "Auto-merge is enabled"
                )
            case .blocked,
                 .checking,
                 .unavailable:
                EmptyView()
            }
        }
    }

    private func mergeButton(
        for action:
            GitLabMergeRequestMergeAction
    ) -> some View {
        Button {
            Task {
                await mergeModel
                    .request(action)
            }
        } label: {
            Image(
                systemName:
                    action == .mergeNow
                    ? "arrow.triangle.merge"
                    : "clock.arrow.circlepath"
            )
            .font(.glabCallout.weight(.semibold))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .accessibilityLabel(action.title)
        .accessibilityHint(
            action == .mergeNow
                ? "Checks the latest state before asking for confirmation."
                : "Checks the latest state before asking to merge after all checks pass."
        )
        .accessibilityIdentifier(
            "mergeRequests.merge.action"
        )
    }

    private func checkRow(
        _ check:
            GitLabMergeRequestReadinessCheck
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: 10
        ) {
            HStack(
                alignment: .top,
                spacing: 10
            ) {
                Image(
                    systemName:
                        check.state.systemImage
                )
                .font(.glabCallout)
                .foregroundStyle(
                    check.state.tint
                )
                .frame(width: 22)
                .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(check.kind.title)
                        .font(.glabCaption)
                        .foregroundStyle(
                            .secondary
                        )

                    Text(check.title)
                        .font(
                            .glabCallout.weight(
                                .semibold
                            )
                        )

                    Text(check.detail)
                        .font(.glabCaption)
                        .foregroundStyle(
                            .secondary
                        )
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .accessibilityElement(
                children: .ignore
            )
            .accessibilityLabel(
                check.accessibilityLabel
            )

            if check.kind == .pipeline {
                Button(
                    action: openPipelines
                ) {
                    Image(
                        systemName:
                            "arrow.right"
                    )
                    .font(
                        .glabCaption
                            .weight(.semibold)
                    )
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .frame(
                    width: 44,
                    height: 44
                )
                .contentShape(.rect)
                .accessibilityLabel(
                    "View merge request pipelines"
                )
                .accessibilityHint(
                    "Opens pipeline history in the app."
                )
                .accessibilityIdentifier(
                    "mergeRequests.readiness.openPipelines"
                )
            } else if let destination =
                check.destination
            {
                Link(
                    destination:
                        destination
                ) {
                    Image(
                        systemName:
                            "arrow.up.right"
                    )
                    .font(.glabCaption.weight(.semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .frame(
                    width: 44,
                    height: 44
                )
                .contentShape(.rect)
                .accessibilityLabel(
                    "Open \(check.kind.title.lowercased()) in GitLab"
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityIdentifier(
            "mergeRequests.readiness."
                + check.kind
                .accessibilityIdentifierSuffix
        )
    }
}

private extension
    GitLabMergeRequestReadinessOverall
{
    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.seal.fill"
        case .blocked:
            "exclamationmark.triangle.fill"
        case .pending:
            "clock.fill"
        case .unknown:
            "questionmark.diamond.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            .green
        case .blocked:
            .orange
        case .pending:
            .blue
        case .unknown:
            .secondary
        }
    }

    var detail: String {
        switch self {
        case .ready:
            "GitLab reports this merge request can be merged."
        case .blocked:
            "One or more merge requirements need attention."
        case .pending:
            "GitLab is still calculating mergeability."
        case .unknown:
            "GitLab did not provide enough information for a verdict."
        }
    }
}

private extension
    GitLabMergeRequestReadinessCheckState
{
    var systemImage: String {
        switch self {
        case .satisfied:
            "checkmark.circle.fill"
        case .blocked:
            "exclamationmark.circle.fill"
        case .pending:
            "clock.fill"
        case .notRequired:
            "minus.circle.fill"
        case .unavailable:
            "eye.slash.circle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .satisfied:
            .green
        case .blocked:
            .orange
        case .pending:
            .blue
        case .notRequired,
             .unavailable,
             .unknown:
            .secondary
        }
    }
}

private extension
    GitLabMergeRequestReadinessCheckKind
{
    var accessibilityIdentifierSuffix: String {
        switch self {
        case .pipeline:
            "pipeline"
        case .approvals:
            "approvals"
        case .conflicts:
            "conflicts"
        case .discussions:
            "discussions"
        case .reviewState:
            "reviewState"
        }
    }
}
