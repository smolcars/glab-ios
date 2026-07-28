import SwiftUI

nonisolated struct GitLabDiffLineSelection:
    Identifiable,
    Sendable
{
    let position: GitLabDiffLinePosition

    var id: GitLabDiffLinePosition {
        position
    }
}

struct GitLabDiffLineDiscussionSheet: View {
    let selection: GitLabDiffLineSelection
    let discussions: [GitLabDiscussion]
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let apiAccess: GitLabAPIAccess
    let mutator: any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let appSession: AppSession
    let onSuccess:
        @MainActor (
            GitLabDiscussionComposerResult
        ) -> Void

    var body: some View {
        GitLabDiffDiscussionSheet(
            title:
                "Line \(selection.position.displayLine)",
            location:
                selection.position.newPath,
            entries:
                discussions.map {
                    GitLabDiffDiscussionSheetEntry(
                        discussion: $0,
                        status: .current
                    )
                },
            newPosition:
                selection.position,
            resource: resource,
            accountID: accountID,
            webURL: webURL,
            apiAccess: apiAccess,
            mutator: mutator,
            reactionService:
                reactionService,
            appSession: appSession,
            onSuccess: onSuccess
        )
    }
}

struct GitLabOtherDiffDiscussionsSheet: View {
    let index: GitLabDiffDiscussionIndex
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let apiAccess: GitLabAPIAccess
    let mutator: any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let appSession: AppSession
    let onSuccess:
        @MainActor (
            GitLabDiscussionComposerResult
        ) -> Void

    var body: some View {
        GitLabDiffDiscussionSheet(
            title: "Other Diff Discussions",
            location:
                "These threads cannot be attached to a current visible line.",
            entries: entries,
            newPosition: nil,
            resource: resource,
            accountID: accountID,
            webURL: webURL,
            apiAccess: apiAccess,
            mutator: mutator,
            reactionService:
                reactionService,
            appSession: appSession,
            onSuccess: onSuccess
        )
    }

    private var entries:
        [GitLabDiffDiscussionSheetEntry]
    {
        index.outdatedDiscussions.map {
            GitLabDiffDiscussionSheetEntry(
                discussion: $0,
                status: .outdated
            )
        }
        + index.unmappedDiscussions.map {
            GitLabDiffDiscussionSheetEntry(
                discussion: $0,
                status: .unmapped
            )
        }
    }
}

private struct GitLabDiffDiscussionSheet:
    View
{
    let title: String
    let location: String
    let entries:
        [GitLabDiffDiscussionSheetEntry]
    let newPosition: GitLabDiffLinePosition?
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let apiAccess: GitLabAPIAccess
    let mutator: any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let appSession: AppSession
    let onSuccess:
        @MainActor (
            GitLabDiscussionComposerResult
        ) -> Void

    @State private var composerTarget:
        GitLabDiscussionComposerTarget?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    Text(location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                    mutationControl

                    if entries.isEmpty {
                        GitLabEmptyStateView(
                            title: "No discussion yet",
                            message:
                                apiAccess.canWrite
                                    ? "Start a Markdown discussion on this exact diff line."
                                    : "This line does not have a discussion.",
                            systemImage:
                                "bubble.left"
                        )
                    } else {
                        ForEach(entries) { entry in
                            GitLabCollapsedDiffDiscussion(
                                entry: entry,
                                resource: resource,
                                accountID:
                                    accountID,
                                webURL: webURL,
                                markdownRenderer:
                                    markdownRenderer,
                                apiAccess:
                                    apiAccess,
                                reactionService:
                                    reactionService,
                                appSession:
                                    appSession,
                                reply:
                                    replyAction(
                                        for:
                                            entry
                                            .discussion
                                    )
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $composerTarget) {
            target in
            GitLabDiscussionComposerView(
                accountID: accountID,
                resource: resource,
                target: target,
                apiAccess: apiAccess,
                mutator: mutator,
                draftStore:
                    appSession
                    .discussionDraftStore,
                appSession: appSession,
                onSuccess: onSuccess
            )
            .presentationDragIndicator(
                .visible
            )
        }
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier(
            "mergeRequestDiffs.discussionSheet"
        )
    }

    @ViewBuilder
    private var mutationControl: some View {
        if
            let newPosition,
            apiAccess.canWrite
        {
            Button {
                composerTarget =
                    .newDiffDiscussion(
                        position: newPosition
                    )
            } label: {
                Label(
                    entries.isEmpty
                        ? "Start discussion"
                        : "Add another discussion",
                    systemImage:
                        "bubble.left.and.text.bubble.right"
                )
            }
            .buttonStyle(.glassProminent)
            .tint(.orange)
            .accessibilityIdentifier(
                "mergeRequestDiffs.addLineDiscussion"
            )
        } else if newPosition != nil {
            Label(
                "Read-only access",
                systemImage: "lock.fill"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }

    private func replyAction(
        for discussion: GitLabDiscussion
    ) -> (() -> Void)? {
        guard
            apiAccess.canWrite,
            !discussion.notes.isEmpty,
            !discussion.isSystemActivity
        else {
            return nil
        }
        return {
            composerTarget = .reply(
                discussionID:
                    discussion.id
            )
        }
    }
}

private struct GitLabCollapsedDiffDiscussion:
    View
{
    let entry:
        GitLabDiffDiscussionSheetEntry
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let markdownRenderer:
        any GitLabMarkdownRendering
    let apiAccess: GitLabAPIAccess
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let appSession: AppSession
    let reply: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            entry.status
                            .systemImage
                    )
                    .foregroundStyle(
                        entry.status.color
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(summary)
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                .primary
                            )
                        Text(entry.status.title)
                            .font(.caption)
                            .foregroundStyle(
                                entry.status.color
                            )
                    }

                    Spacer(minLength: 8)

                    Image(
                        systemName:
                            isExpanded
                                ? "chevron.up"
                                : "chevron.down"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    Color(
                        uiColor:
                            .secondarySystemGroupedBackground
                    ),
                    in: .rect(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                "mergeRequestDiffs.discussionSummary.\(entry.id)"
            )
            .accessibilityValue(
                isExpanded
                    ? "Expanded"
                    : "Collapsed"
            )

            if isExpanded {
                GitLabDiscussionCard(
                    discussion:
                        entry.discussion,
                    resource: resource,
                    accountID: accountID,
                    webURL: webURL,
                    markdownRenderer:
                        markdownRenderer,
                    apiAccess: apiAccess,
                    reactionService:
                        reactionService,
                    appSession: appSession,
                    reply: reply
                )
            }
        }
    }

    private var summary: String {
        let author =
            entry.discussion.notes.first?
            .author.name
            ?? "GitLab user"
        let count =
            entry.discussion.notes.count
        return "\(author) · \(count) "
            + (count == 1 ? "comment" : "comments")
    }
}

private struct GitLabDiffDiscussionSheetEntry:
    Identifiable
{
    let discussion: GitLabDiscussion
    let status: GitLabDiffDiscussionStatus

    var id: String {
        discussion.id
    }
}

private enum GitLabDiffDiscussionStatus {
    case current
    case outdated
    case unmapped

    var title: String {
        switch self {
        case .current:
            "Current diff"
        case .outdated:
            "Outdated diff"
        case .unmapped:
            "Position unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .current:
            "bubble.left.fill"
        case .outdated:
            "clock.arrow.circlepath"
        case .unmapped:
            "questionmark.bubble"
        }
    }

    var color: Color {
        switch self {
        case .current:
            .orange
        case .outdated:
            .secondary
        case .unmapped:
            .yellow
        }
    }
}
