import SwiftUI

struct GitLabMergeRequestReadinessView: View {
    let readiness:
        GitLabMergeRequestReadiness
    let approvalError:
        GitLabSessionClientError?
    let retryApproval: () -> Void
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
    }

    private var summaryControl: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName:
                        readiness.overall
                        .systemImage
                )
                .font(.body)
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
                        .callout.weight(
                            .semibold
                        )
                    )

                    Text(
                        readiness.compactSummary
                    )
                    .font(.caption)
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
                    .caption.weight(.semibold)
                )
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
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
                .font(.callout)
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
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                    Text(check.title)
                        .font(
                            .callout.weight(
                                .semibold
                            )
                        )

                    Text(check.detail)
                        .font(.caption)
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
                    .font(.caption.weight(.semibold))
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
