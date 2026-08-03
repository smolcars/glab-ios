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
                        .font(.glabCallout.weight(.semibold))
                    Text(presentation.message)
                        .font(.glabCaption)
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
            .font(.glabCaption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(Color.glabAccent)
            .background(
                Color.glabAccent.opacity(0.12),
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
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                Text(user.displayName)
                    .font(.glabBody.weight(.medium))
                Text("@\(user.username)")
                    .font(.glabCaption)
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
                .font(.glabHeadline)

            content
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
    }
}

struct GitLabDetailScrollContent<Content: View>: View {
    let bottomPadding: CGFloat
    let content: Content

    init(
        bottomPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 22
        ) {
            content
        }
        .padding(20)
        .padding(.bottom, bottomPadding)
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
                        .glabSubheadline
                            .weight(.semibold)
                    )

                GitLabLogoMark()
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

struct GitLabResourceDetailToolbarActions:
    ToolbarContent
{
    let destination: URL?
    let openInGitLabAccessibilityIdentifier:
        String
    let canEdit: Bool
    let canComment: Bool
    let edit: () -> Void
    let editMetadata: () -> Void
    let stateEvent:
        GitLabResourceStateEvent?
    let changeState:
        (GitLabResourceStateEvent) -> Void
    let addComment: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(
            placement: .topBarTrailing
        ) {
            if let destination {
                Link(
                    destination:
                        destination
                ) {
                    GitLabLogoMark()
                }
                .accessibilityLabel(
                    "Open in GitLab"
                )
                .accessibilityIdentifier(
                    openInGitLabAccessibilityIdentifier
                )
            }

            Menu {
                Button {
                    edit()
                } label: {
                    Label(
                        "Title & description",
                        systemImage:
                            "doc.text"
                    )
                }

                Button {
                    editMetadata()
                } label: {
                    Label(
                        "Labels & people",
                        systemImage:
                            "person.2"
                    )
                }

                if let stateEvent {
                    Divider()

                    Button(
                        role:
                            stateEvent == .close
                            ? .destructive
                            : nil
                    ) {
                        changeState(
                            stateEvent
                        )
                    } label: {
                        Label(
                            stateEvent == .close
                                ? "Close"
                                : "Reopen",
                            systemImage:
                                stateEvent == .close
                                ? "xmark.circle"
                                : "arrow.uturn.backward.circle"
                        )
                    }
                }
            } label: {
                Label(
                    "Edit",
                    systemImage: "pencil"
                )
            }
            .disabled(!canEdit)
            .accessibilityIdentifier(
                "resource.edit"
            )
            .accessibilityHint(
                canEdit
                    ? "Shows compact editing actions."
                    : "Wait for the current task update to finish."
            )

            Button {
                addComment()
            } label: {
                Label(
                    "Add comment",
                    systemImage:
                        "square.and.pencil"
                )
            }
            .accessibilityIdentifier(
                "discussion.addComment"
            )
            .accessibilityHint(
                canComment
                    ? "Opens a Markdown comment editor."
                    : "Explains why commenting is unavailable."
            )
        }
    }
}

struct GitLabLogoMark: View {
    var body: some View {
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
}
