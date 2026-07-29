import SwiftUI

struct GitLabDiscussionSection: View {
    let model: GitLabDiscussionsModel
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let apiAccess: GitLabAPIAccess
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let resolutionModel:
        GitLabDiscussionResolutionModel?
    let appSession: AppSession
    let launchComposer:
        (GitLabDiscussionComposerTarget) -> Void

    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer

    var body: some View {
        GitLabDetailSection(title: "Discussion") {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                content
            }
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
        let presentation =
            GitLabDiscussionPresentation(
                discussions:
                    model.discussions
            )

        return VStack(
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

            if
                !presentation
                    .activityNotes
                    .isEmpty
            {
                GitLabActivityStrip(
                    notes:
                        presentation
                            .activityNotes
                )
            }

            ForEach(
                presentation.conversations
            ) {
                discussion in
                GitLabDiscussionCard(
                    discussion: discussion,
                    resource: resource,
                    accountID: accountID,
                    webURL: webURL,
                    markdownRenderer:
                        markdownRenderer,
                    apiAccess: apiAccess,
                    reactionService:
                        reactionService,
                    resolutionModel:
                        resolutionModel,
                    appSession: appSession,
                    reply: replyAction(
                        for: discussion
                    )
                )
            }

            if
                let paginationAnchor =
                    presentation
                        .paginationAnchor
            {
                ZStack {
                    Color.clear
                        .id(model.contentRevision)
                        .onScrollVisibilityChange(
                            threshold: 0.01
                        ) { isVisible in
                            guard isVisible else {
                                return
                            }
                            Task {
                                await model
                                    .loadNextPageIfNeeded(
                                        after:
                                            paginationAnchor
                                    )
                            }
                        }
                }
                .frame(height: 1)
                .id("discussion.pagination.anchor")
                .accessibilityHidden(true)
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
            launchComposer(
                .reply(
                    discussionID:
                        discussion.id
                )
            )
        }
    }
}

private struct GitLabActivityStrip: View {
    let notes: [GitLabDiscussionNote]

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            Button {
                toggleExpanded()
            } label: {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "bolt.horizontal.circle.fill"
                    )
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                    Text("Activity")
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    Text(
                        "\(notes.count) "
                            + (notes.count == 1
                                ? "event"
                                : "events")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Image(
                        systemName:
                            "chevron.down"
                    )
                    .font(
                        .caption.weight(.bold)
                    )
                    .foregroundStyle(.secondary)
                    .rotationEffect(
                        .degrees(
                            isExpanded
                                ? 180
                                : 0
                        )
                    )
                    .accessibilityHidden(true)
                }
                .contentShape(.rect)
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Activity, \(notes.count) "
                    + (notes.count == 1
                        ? "event"
                        : "events")
            )
            .accessibilityValue(
                isExpanded
                    ? "Expanded"
                    : "Collapsed"
            )
            .accessibilityHint(
                isExpanded
                    ? "Collapses activity."
                    : "Expands activity."
            )
            .accessibilityIdentifier(
                "discussion.activity"
            )

            if isExpanded {
                Divider()
                    .padding(.leading, 44)

                VStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(
                        Array(
                            notes.enumerated()
                        ),
                        id: \.element.id
                    ) { index, note in
                        if index > 0 {
                            Divider()
                                .padding(
                                    .leading,
                                    44
                                )
                        }

                        GitLabActivityEventRow(
                            note: note
                        )
                    }
                }
            }
        }
        .background(
            Color(
                uiColor:
                    .secondarySystemGroupedBackground
            ),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16
            )
            .stroke(
                Color.primary.opacity(0.08),
                lineWidth: 1
            )
        }
    }

    private func toggleExpanded() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(
                .snappy(duration: 0.24)
            ) {
                isExpanded.toggle()
            }
        }
    }
}

private struct GitLabActivityEventRow: View {
    let note: GitLabDiscussionNote

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        Button {
            toggleExpanded()
        } label: {
            HStack(
                alignment: .top,
                spacing: 10
            ) {
                Image(
                    systemName:
                        "bolt.horizontal"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    HStack(
                        alignment:
                            .firstTextBaseline,
                        spacing: 8
                    ) {
                        Text(
                            note.author
                                .displayName
                        )
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                        .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(
                            GitLabRelativeTimeFormatter
                                .string(
                                    from:
                                        note.createdAt
                                )
                        )
                        .font(
                            .caption2
                                .monospacedDigit()
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Text(
                        note.activityText
                            ?? "Activity details unavailable"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(
                        isExpanded
                            ? nil
                            : 2
                    )
                    .multilineTextAlignment(
                        .leading
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }

                Image(
                    systemName:
                        "chevron.down"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(
                    .degrees(
                        isExpanded ? 180 : 0
                    )
                )
                .padding(.top, 5)
                .accessibilityHidden(true)
            }
            .contentShape(.rect)
            .padding(14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            [
                note.author.displayName,
                note.activityText
                    ?? "Activity details unavailable",
                GitLabRelativeTimeFormatter
                    .string(
                        from: note.createdAt
                    ),
            ]
            .joined(separator: ", ")
        )
        .accessibilityValue(
            isExpanded
                ? "Expanded"
                : "Collapsed"
        )
        .accessibilityHint(
            isExpanded
                ? "Collapses this activity event."
                : "Expands this activity event."
        )
        .accessibilityIdentifier(
            "discussion.activity.note.\(note.id)"
        )
    }

    private func toggleExpanded() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(
                .snappy(duration: 0.2)
            ) {
                isExpanded.toggle()
            }
        }
    }
}

struct GitLabDiscussionCard: View {
    let discussion: GitLabDiscussion
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let webURL: URL?
    let markdownRenderer:
        any GitLabMarkdownRendering
    let apiAccess: GitLabAPIAccess
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let resolutionModel:
        GitLabDiscussionResolutionModel?
    let appSession: AppSession
    let reply: (() -> Void)?

    var body: some View {
        VStack(
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
                            markdownRenderer,
                        apiAccess: apiAccess,
                        reactionService:
                            reactionService,
                        reply:
                            note.isSystem
                            ? nil
                            : reply,
                        replyAccessibilityIdentifier:
                            "discussion.reply.\(discussion.id).note.\(note.id)",
                        showsResolvedBadge:
                            resolutionModel
                                == nil,
                        appSession:
                            appSession
                    )
                }
            }

            if
                resolutionModel?
                    .status(
                        for: discussion
                    ) != nil
            {
                Divider()
                    .padding(.leading, 46)

                GitLabDiscussionThreadFooter(
                    discussion: discussion,
                    resolutionModel:
                        resolutionModel,
                    apiAccess: apiAccess
                )
                .padding(12)
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
    let apiAccess: GitLabAPIAccess
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let reply: (() -> Void)?
    let replyAccessibilityIdentifier:
        String
    let showsResolvedBadge: Bool
    let appSession: AppSession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingView

            VStack(alignment: .leading, spacing: 10) {
                header
                statusBadges
                diffContext
                bodyContent

                GitLabEmojiReactionView(
                    awardable: .note(
                        id: note.id,
                        in: resource
                    ),
                    currentUserID:
                        accountID.userID,
                    apiAccess: apiAccess,
                    loader: reactionService,
                    mutator:
                        reactionService,
                    allowsMutation:
                        !note.isSystem,
                    reply: reply,
                    replyAccessibilityIdentifier:
                        replyAccessibilityIdentifier,
                    accountID: accountID,
                    appSession: appSession
                )
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
                || (
                    showsResolvedBadge
                        && note.isResolved
                )
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
        if
            showsResolvedBadge,
            note.isResolved
        {
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

        if note.isSystem {
            Text(
                note.activityText
                    ?? "Activity details unavailable"
            )
            .font(.body)
            .foregroundStyle(.secondary)
        } else if source.isEmpty {
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
            .foregroundStyle(Color.primary)
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
        if
            showsResolvedBadge,
            note.isResolved
        {
            parts.append("Resolved")
        }
        return parts.joined(separator: ", ")
    }
}

private struct GitLabDiscussionThreadFooter:
    View
{
    let discussion: GitLabDiscussion
    let resolutionModel:
        GitLabDiscussionResolutionModel?
    let apiAccess: GitLabAPIAccess

    private var status:
        GitLabDiscussionResolutionStatus?
    {
        resolutionModel?.status(
            for: discussion
        )
    }

    private var presentation:
        GitLabDiscussionResolutionPresentation?
    {
        status.map {
            GitLabDiscussionResolutionPresentation(
                status: $0,
                apiAccess: apiAccess,
                discussionID:
                    discussion.id
            )
        }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Spacer(minLength: 0)
                resolutionControl
            }

            resolutionDetails
        }
    }

    @ViewBuilder
    private var resolutionControl:
        some View
    {
        if let presentation {
            if
                presentation
                    .showsUnavailableAccessLabel
            {
                Label(
                    presentation
                        .actionTitle,
                    systemImage: "lock.fill"
                )
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .accessibilityLabel(
                    presentation
                        .accessibilityLabel
                )
                .accessibilityValue(
                    presentation
                        .accessibilityValue
                )
                .accessibilityHint(
                    presentation
                        .accessibilityHint
                )
                .accessibilityIdentifier(
                    presentation
                        .accessibilityIdentifier
                )
            } else {
                Button {
                    perform(
                        presentation.action
                    )
                } label: {
                    HStack(spacing: 7) {
                        if
                            presentation
                                .showsProgress
                        {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(
                                systemName:
                                    presentation
                                    .action
                                    == .checkGitLab
                                    ? "arrow.triangle.2.circlepath"
                                    : status?
                                        .isResolved
                                        == true
                                        ? "arrow.uturn.backward.circle"
                                        : "checkmark.circle"
                            )
                        }

                        Text(
                            presentation
                                .actionTitle
                        )
                    }
                    .font(
                        .callout
                            .weight(.semibold)
                    )
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(.orange)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .disabled(
                    !presentation
                        .isActionEnabled
                )
                .accessibilityLabel(
                    presentation
                        .accessibilityLabel
                )
                .accessibilityValue(
                    presentation
                        .accessibilityValue
                )
                .accessibilityHint(
                    presentation
                        .accessibilityHint
                )
                .accessibilityIdentifier(
                    presentation
                        .accessibilityIdentifier
                )
            }
        }
    }

    @ViewBuilder
    private var resolutionDetails:
        some View
    {
        if
            let presentation,
            presentation.statusTitle != nil
                || presentation
                    .failureMessage != nil
        {
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                if
                    let statusTitle =
                        presentation
                            .statusTitle
                {
                    HStack(
                        spacing: 5
                    ) {
                        Image(
                            systemName:
                                status?
                                    .isResolved
                                    == true
                                ? "checkmark.circle.fill"
                                : "info.circle"
                        )
                        Text(statusTitle)

                        if
                            let resolvedAt =
                                status?
                                .resolvedAt
                        {
                            Text("•")
                            Text(
                                GitLabRelativeTimeFormatter
                                    .string(
                                        from:
                                            resolvedAt
                                    )
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                if
                    let failureMessage =
                        presentation
                            .failureMessage
                {
                    Text(failureMessage)
                        .font(.caption)
                        .foregroundStyle(
                            presentation
                                .showsUnavailableAccessLabel
                                    ? Color.secondary
                                    : presentation
                                        .action
                                        == .checkGitLab
                                            ? Color.orange
                                            : Color.red
                        )
                }
            }
            .accessibilityElement(
                children: .combine
            )
        }
    }

    private func perform(
        _ action:
            GitLabDiscussionResolutionAction?
    ) {
        guard
            let resolutionModel,
            let action
        else {
            return
        }
        Task {
            switch action {
            case .toggle:
                await resolutionModel
                    .toggle(discussion)
            case .checkGitLab:
                await resolutionModel
                    .checkGitLab(
                        discussionID:
                            discussion.id
                    )
            case .retry:
                await resolutionModel
                    .retry(
                        discussionID:
                            discussion.id
                    )
            }
        }
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
