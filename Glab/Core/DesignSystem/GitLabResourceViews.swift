import SwiftUI

struct GitLabInlineRetryRow: View {
    let title: String
    let presentation: GitLabRecoveryPresentation
    let accessibilityIdentifier: String
    let retry: () -> Void

    init(
        title: String,
        error: GitLabSessionClientError,
        accessibilityIdentifier: String,
        retry: @escaping () -> Void
    ) {
        self.title = title
        presentation = GitLabRecoveryPresentation(
            error: error
        )
        self.accessibilityIdentifier =
            accessibilityIdentifier
        self.retry = retry
    }

    var body: some View {
        GitLabRetryControl(
            availability:
                presentation.retryAvailability,
            action: retry
        ) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(presentation.message)
                        .font(.caption)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            } icon: {
                Image(
                    systemName: presentation.systemImage
                )
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .listRowBackground(Color.red.opacity(0.1))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct GitLabLabelPill: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(.orange)
            .background(
                Color.orange.opacity(0.12),
                in: .capsule
            )
    }
}

struct GitLabAPIUserRow: View {
    let user: GitLabAPIUser
    let role: String

    var body: some View {
        HStack(spacing: 12) {
            GitLabUserAvatar(
                user: user.summary,
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(user.displayName)
                    .font(.body.weight(.medium))
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct GitLabDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
    }
}

struct GitLabOpenInGitLabLink: View {
    let destination: URL
    let accessibilityIdentifier: String

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            GitLabOpenInGitLabControl(
                destination: destination,
                accessibilityIdentifier:
                    accessibilityIdentifier
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

struct GitLabOpenInGitLabControl: View {
    let destination: URL
    let accessibilityIdentifier: String

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 8) {
                Text("Open in")
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                Image("GitLabLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: 26,
                        height: 26
                    )
                    .scaleEffect(2.5)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .dynamicTypeSize(
            ...DynamicTypeSize.accessibility1
        )
        .accessibilityLabel("Open in GitLab")
        .accessibilityIdentifier(
                accessibilityIdentifier
        )
    }
}
