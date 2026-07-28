import SwiftUI

struct GitLabDiscussionSection: View {
    let model: GitLabDiscussionsModel
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let apiAccess: GitLabAPIAccess
    let mutator: any GitLabDiscussionMutating
    let appSession: AppSession

    @State private var composerTarget:
        GitLabDiscussionComposerTarget?

    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer

    var body: some View {
        GitLabDetailSection(title: "Discussion") {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                mutationControl
                content
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
                onSuccess: reconcile
            )
            .presentationDragIndicator(
                .visible
            )
        }
    }

    @ViewBuilder
    private var mutationControl: some View {
        if apiAccess.canWrite {
            Button {
                composerTarget =
                    .newDiscussion
            } label: {
                Label(
                    "Add comment",
                    systemImage:
                        "bubble.left.and.text.bubble.right"
                )
            }
            .buttonStyle(.glassProminent)
            .tint(.orange)
            .accessibilityIdentifier(
                "discussion.addComment"
            )
            .accessibilityHint(
                "Opens a Markdown comment editor."
            )
        } else {
            Label {
                Text(
                    "Read-only access. The api scope is required to comment."
                )
                .font(.footnote)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .foregroundStyle(.orange)
            .padding(12)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background(
                Color.orange.opacity(0.1),
                in: .rect(cornerRadius: 12)
            )
            .accessibilityIdentifier(
                "discussion.readOnlyMessage"
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if
            model.isLoadingInitial,
            model.discussions.isEmpty
        {
            GitLabDiscussionSkeleton()
        } else if
            model.discussions.isEmpty,
            let error = model.loadError
        {
            GitLabDiscussionRetryCard(
                title: "Couldn’t load discussion",
                error: error,
                accessibilityIdentifier:
                    "discussion.initialError"
            ) {
                Task {
                    await model.refresh()
                }
            }
        } else if
            model.discussions.isEmpty,
            model.hasLoaded
        {
            GitLabDiscussionEmptyState()
        } else {
            loadedContent
        }
    }

    private var loadedContent: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 14
        ) {
            if model.isRefreshing {
                Label(
                    "Refreshing discussion…",
                    systemImage: "arrow.clockwise"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    "discussion.refreshing"
                )
            }

            if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabDiscussionRetryCard(
                    title:
                        "Couldn’t refresh discussion",
                    error: error,
                    accessibilityIdentifier:
                        "discussion.refreshError"
                ) {
                    Task {
                        await model.refresh()
                    }
                }
            }

            ForEach(model.discussions) {
                discussion in
                GitLabDiscussionCard(
                    discussion: discussion,
                    resource: resource,
                    accountID: accountID,
                    webURL: webURL,
                    markdownRenderer:
                        markdownRenderer,
                    reply: replyAction(
                        for: discussion
                    )
                )
                .task(id: model.contentRevision) {
                    guard
                        model.discussions.last?.id
                            == discussion.id
                    else {
                        return
                    }
                    await model
                        .loadNextPageIfNeeded(
                            after: discussion
                        )
                }
            }

            if model.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more…")
                        .font(.footnote)
                    Spacer()
                }
                .accessibilityIdentifier(
                    "discussion.nextPageLoading"
                )
            } else if
                model.didFailNextPage,
                let error = model.loadError
            {
                GitLabDiscussionRetryCard(
                    title:
                        "Couldn’t load more discussion",
                    error: error,
                    accessibilityIdentifier:
                        "discussion.nextPageError"
                ) {
                    Task {
                        await model.retryNextPage()
                    }
                }
            }
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

    private func reconcile(
        _ result:
            GitLabDiscussionComposerResult
    ) {
        switch result {
        case let .discussion(discussion):
            model.reconcileCreatedDiscussion(
                discussion
            )
        case let .reply(
            note,
            discussionID
        ):
            model.reconcileCreatedReply(
                note,
                discussionID:
                    discussionID
            )
        }
    }
}

private struct GitLabDiscussionCard: View {
    let discussion: GitLabDiscussion
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let markdownRenderer:
        any GitLabMarkdownRendering
    let reply: (() -> Void)?

    var body: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 0
        ) {
            if discussion.notes.isEmpty {
                Label(
                    "This discussion has no visible notes.",
                    systemImage: "bubble.left"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(14)
            } else {
                ForEach(
                    Array(
                        discussion.notes.enumerated()
                    ),
                    id: \.element.id
                ) { index, note in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 46)
                    }

                    GitLabDiscussionNoteView(
                        note: note,
                        replyIndex: index,
                        replyCount:
                            discussion.notes.count,
                        resource: resource,
                        accountID: accountID,
                        webURL: webURL,
                        markdownRenderer:
                            markdownRenderer
                    )
                }
            }

            if let reply {
                Divider()
                    .padding(.leading, 46)

                Button(
                    "Reply",
                    systemImage:
                        "arrowshape.turn.up.left"
                ) {
                    reply()
                }
                .buttonStyle(.glass)
                .padding(12)
                .accessibilityIdentifier(
                    "discussion.reply.\(discussion.id)"
                )
                .accessibilityHint(
                    "Opens a Markdown reply editor."
                )
            }
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .accessibilityIdentifier(
            "discussion.card.\(discussion.id)"
        )
    }
}

private struct GitLabDiscussionNoteView: View {
    let note: GitLabDiscussionNote
    let replyIndex: Int
    let replyCount: Int
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let markdownRenderer:
        any GitLabMarkdownRendering

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingView

            VStack(alignment: .leading, spacing: 10) {
                header
                statusBadges
                diffContext
                bodyContent
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(14)
        .padding(.leading, replyIndex > 0 ? 12 : 0)
        .overlay(alignment: .leading) {
            if replyIndex > 0 {
                Capsule()
                    .fill(Color.orange.opacity(0.45))
                    .frame(width: 3)
                    .padding(.vertical, 12)
                    .padding(.leading, 7)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(
            "discussion.note.\(note.id)"
        )
    }

    @ViewBuilder
    private var leadingView: some View {
        if note.isSystem {
            Image(systemName: "bolt.horizontal.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
        } else {
            GitLabUserAvatar(
                user: note.author.summary,
                size: 34
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.author.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(
                    GitLabRelativeTimeFormatter.string(
                        from: note.createdAt
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                Text("@\(note.author.username)")
                if note.showsEditedStatus {
                    Text("• Edited")
                }
                if note.isSystem {
                    Text("• Activity")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        if
            note.isInternal
                || note.kind == .diff
                || note.isResolved
        {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    badges
                }
                VStack(alignment: .leading, spacing: 6) {
                    badges
                }
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if note.isInternal {
            GitLabDiscussionBadge(
                title: "Internal",
                systemImage: "lock.fill"
            )
        }
        if note.kind == .diff {
            GitLabDiscussionBadge(
                title: "Code discussion",
                systemImage: "chevron.left.forwardslash.chevron.right"
            )
        }
        if note.isResolved {
            GitLabDiscussionBadge(
                title: "Resolved",
                systemImage: "checkmark.circle.fill"
            )
        }
    }

    @ViewBuilder
    private var diffContext: some View {
        if
            let path = note.position?.displayPath
        {
            Label {
                if let line = note.position?.displayLine {
                    Text("\(path):\(line)")
                } else {
                    Text(path)
                }
            } icon: {
                Image(systemName: "doc.text")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        let source = note.body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if source.isEmpty {
            Text("No note content.")
                .font(.body)
                .foregroundStyle(.secondary)
        } else {
            GitLabMarkdownContentView(
                request: GitLabMarkdownRequest(
                    accountID: accountID,
                    resource:
                        resource.markdownResourceID(
                            noteID: note.id
                        ),
                    source: source,
                    webURL: webURL
                ),
                revision: note.updatedAt,
                kind: .comment,
                renderer: markdownRenderer
            )
            .foregroundStyle(
                note.isSystem
                    ? Color.secondary
                    : Color.primary
            )
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            note.isSystem
                ? "Activity"
                : "Comment by \(note.author.displayName)",
            note.createdAt.formatted(
                date: .abbreviated,
                time: .shortened
            ),
        ]
        if replyIndex > 0 {
            parts.append(
                "Reply \(replyIndex) of \(replyCount - 1)"
            )
        }
        if note.isInternal {
            parts.append("Internal")
        }
        if note.kind == .diff {
            parts.append("Code discussion")
        }
        if note.isResolved {
            parts.append("Resolved")
        }
        return parts.joined(separator: ", ")
    }
}

private struct GitLabDiscussionBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Color.orange.opacity(0.12),
                in: .capsule
            )
    }
}

private struct GitLabDiscussionSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Loading discussion author")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "Loading the discussion content from GitLab."
                    )
                    .font(.body)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(14)
                .background(
                    Color(
                        uiColor:
                            .secondarySystemGroupedBackground
                    ),
                    in: .rect(cornerRadius: 16)
                )
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading discussion")
        .accessibilityIdentifier(
            "discussion.loading"
        )
    }
}

private struct GitLabDiscussionEmptyState: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("No discussion yet")
                    .font(.callout.weight(.semibold))
                Text(
                    "Comments and activity will appear here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "bubble.left")
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            "discussion.empty"
        )
    }
}

private struct GitLabDiscussionRetryCard: View {
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
        presentation =
            GitLabRecoveryPresentation(error: error)
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
            .padding(12)
            .foregroundStyle(.red)
            .background(
                Color.red.opacity(0.1),
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            accessibilityIdentifier
        )
    }
}
