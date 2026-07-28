import SwiftUI

struct GitLabMergeRequestReadinessView: View {
    let readiness:
        GitLabMergeRequestReadiness
    let approvalError:
        GitLabSessionClientError?
    let retryApproval: () -> Void

    var body: some View {
        GitLabDetailSection(
            title: "Merge readiness"
        ) {
            VStack(spacing: 0) {
                overallRow

                ForEach(readiness.checks) {
                    check in
                    Divider()
                        .padding(.leading, 52)

                    checkRow(check)
                }
            }
            .background(
                Color(
                    uiColor:
                        .secondarySystemGroupedBackground
                ),
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
        .accessibilityIdentifier(
            "mergeRequests.readiness"
        )
    }

    private var overallRow: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            Image(
                systemName:
                    readiness.overall.systemImage
            )
            .font(.title3)
            .foregroundStyle(
                readiness.overall.tint
            )
            .frame(width: 24)
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(readiness.overall.title)
                    .font(
                        .body.weight(.semibold)
                    )

                Text(readiness.overall.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(16)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            readiness.accessibilityLabel
        )
        .accessibilityValue(
            readiness.overall.detail
        )
        .accessibilityIdentifier(
            "mergeRequests.readiness.overall"
        )
    }

    private func checkRow(
        _ check:
            GitLabMergeRequestReadinessCheck
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: 12
        ) {
            HStack(
                alignment: .top,
                spacing: 12
            ) {
                Image(
                    systemName:
                        check.state.systemImage
                )
                .font(.body)
                .foregroundStyle(
                    check.state.tint
                )
                .frame(width: 24)
                .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(check.kind.title)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                    Text(check.title)
                        .font(
                            .body.weight(
                                .semibold
                            )
                        )

                    Text(check.detail)
                        .font(.subheadline)
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

            if let destination =
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
                    .font(
                        .callout.weight(
                            .semibold
                        )
                    )
                    .frame(
                        width: 28,
                        height: 28
                    )
                }
                .buttonStyle(.glass)
                .accessibilityLabel(
                    "Open \(check.kind.title.lowercased()) in GitLab"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
