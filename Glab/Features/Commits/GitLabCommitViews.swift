import SwiftUI
import UIKit

struct GitLabProjectCommitsView: View {
    let project: GitLabProject
    let loader: any GitLabCommitLoading
    let accountID: GitLabAccountID
    let appSession: AppSession

    @State private var model:
        GitLabCommitsModel

    init(
        project: GitLabProject,
        loader: any GitLabCommitLoading,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.project = project
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabCommitsModel(
                    projectID: project.id,
                    refName:
                        project.defaultBranch,
                    loader: loader
                )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            branchHeader
            Divider()
            content
        }
        .background(
            Color.glabCanvas
        )
        .navigationTitle("Commits")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refresh()
        }
        .task(id: ObjectIdentifier(model)) {
            await model.loadIfNeeded()
            await handleAuthenticationFailure()
        }
        .accessibilityIdentifier(
            "commits.history"
        )
    }

    private var branchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(branchTitle)
                .font(
                    .subheadline
                        .weight(.semibold)
                        .monospaced()
                )
                .lineLimit(1)

            Spacer(minLength: 12)

            Text("Default branch")
                .font(.glabCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(
            Color.glabSurface
        )
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            "Default branch, \(branchTitle)"
        )
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingInitial {
            ScrollView {
                GitLabLoadingStateView(
                    message: "Loading commits"
                )
                .padding(20)
            }
        } else if
            model.commits.isEmpty,
            let error = model.loadError
        {
            GitLabContentStateScrollView {
                GitLabRetryStateView(
                    error: error
                ) {
                    Task {
                        await refresh()
                    }
                }
            }
        } else if
            model.commits.isEmpty,
            model.hasLoaded
        {
            GitLabContentStateScrollView {
                GitLabEmptyStateView(
                    title: "No commits",
                    message:
                        "The default branch does not have any commits yet.",
                    systemImage:
                        "point.bottomleft.forward.to.point.topright.scurvepath"
                )
            }
        } else {
            commitList
        }
    }

    private var commitList: some View {
        GlabList {
            if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t refresh commits",
                    error: error,
                    accessibilityIdentifier:
                        "commits.refreshError"
                ) {
                    Task {
                        await refresh()
                    }
                }
            }

            ForEach(
                model.displayedCommits
            ) { commit in
                NavigationLink {
                    GitLabCommitDetailView(
                        project: project,
                        commit: commit,
                        loader: loader,
                        accountID: accountID,
                        appSession: appSession
                    )
                } label: {
                    GitLabCommitRow(
                        commit: commit
                    )
                }
                .listRowInsets(
                    EdgeInsets(
                        top: 7,
                        leading: 16,
                        bottom: 7,
                        trailing: 12
                    )
                )
                .accessibilityIdentifier(
                    "commits.row.\(commit.shortID)"
                )
                .task {
                    await model
                        .loadNextPageIfNeeded(
                            after: commit
                        )
                    await handleAuthenticationFailure()
                }
            }

            if model.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more…")
                        .font(.glabFootnote)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if
                model.didFailNextPage,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t load more commits",
                    error: error,
                    accessibilityIdentifier:
                        "commits.nextPageError"
                ) {
                    Task {
                        await model.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var branchTitle: String {
        project.defaultBranch?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .nilIfEmpty
            ?? "default"
    }

    private func refresh() async {
        await model.refresh()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                model.authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}

private struct GitLabCommitRow: View {
    let commit: GitLabCommit

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            ViewThatFits(
                in: .horizontal
            ) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 12)
                    relativeTime
                }

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    title
                    relativeTime
                }
            }

            HStack(spacing: 7) {
                Text(commit.authorMark)
                    .font(
                        .glabCaption2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(Color.glabAccent)
                    .frame(
                        width: 24,
                        height: 24
                    )
                    .background(
                        Color.glabAccent
                            .opacity(0.13),
                        in: .circle
                    )
                    .accessibilityHidden(true)

                Text(commit.authorName)
                    .font(
                        .glabSubheadline
                            .weight(.semibold)
                    )
                    .lineLimit(
                        dynamicTypeSize
                            .isAccessibilitySize
                            ? nil
                            : 1
                    )

                Text("authored")
                    .font(.glabSubheadline)
                    .foregroundStyle(
                        .secondary
                    )

                Spacer(minLength: 8)

                Text(commit.shortID)
                    .font(
                        .caption
                            .monospaced()
                    )
                    .foregroundStyle(
                        .secondary
                    )
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            "\(commit.title), authored by \(commit.authorName), "
                + commit.authoredDate.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
                + ", commit \(commit.shortID)"
        )
    }

    private var title: some View {
        Text(commit.title)
            .font(.glabBody.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(
                dynamicTypeSize
                    .isAccessibilitySize
                    ? nil
                    : 2
            )
    }

    private var relativeTime: some View {
        Text(
            GitLabRelativeTimeFormatter
                .string(
                    from:
                        commit.authoredDate
                )
        )
        .font(
            .caption.monospacedDigit()
        )
        .foregroundStyle(.secondary)
    }
}

private enum GitLabCommitDetailSection:
    String,
    CaseIterable,
    Sendable
{
    case changes
    case details

    var title: String {
        rawValue.capitalized
    }
}

struct GitLabCommitDetailView: View {
    let project: GitLabProject
    let commit: GitLabCommit
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.gitLabDiffRenderer)
    private var diffRenderer

    @State private var selectedSection =
        GitLabCommitDetailSection.changes
    @State private var model:
        GitLabCommitDiffModel

    init(
        project: GitLabProject,
        commit: GitLabCommit,
        loader: any GitLabCommitLoading,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.project = project
        self.commit = commit
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabCommitDiffModel(
                    route:
                        GitLabCommitDiffRoute(
                            projectID:
                                project.id,
                            commitSHA:
                                commit.id
                        ),
                    loader: loader
                )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if selectedSection == .changes {
                commitHeader
                Divider()
            }

            switch selectedSection {
            case .changes:
                changesContent
            case .details:
                detailsContent
            }
        }
        .background(
            Color.glabCanvas
        )
        .navigationTitle("Commit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .principal
            ) {
                Picker(
                    "Commit section",
                    selection: $selectedSection
                ) {
                    ForEach(
                        GitLabCommitDetailSection
                            .allCases,
                        id: \.self
                    ) {
                        Text($0.title)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 176)
            }

            ToolbarItem(
                placement: .topBarTrailing
            ) {
                commitMenu
            }
        }
        .task(id: selectedSection) {
            guard
                selectedSection == .changes
            else {
                return
            }
            await model.loadIfNeeded()
            await handleAuthenticationFailure()
        }
        .accessibilityIdentifier(
            "commit.detail"
        )
    }

    private var commitHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 11
        ) {
            HStack(spacing: 9) {
                Text(commit.authorMark)
                    .font(
                        .glabCaption.weight(.bold)
                    )
                    .foregroundStyle(Color.glabAccent)
                    .frame(
                        width: 28,
                        height: 28
                    )
                    .background(
                        Color.glabAccent
                            .opacity(0.13),
                        in: .circle
                    )
                    .accessibilityHidden(true)

                Text(commit.authorName)
                    .font(
                        .glabSubheadline
                            .weight(.semibold)
                    )

                Text("authored")
                    .font(.glabSubheadline)
                    .foregroundStyle(
                        .secondary
                    )

                Spacer(minLength: 8)

                Text(
                    GitLabRelativeTimeFormatter
                        .string(
                            from:
                                commit.authoredDate
                        )
                )
                .font(
                    .caption
                        .monospacedDigit()
                )
                .foregroundStyle(.secondary)
            }

            Text(commit.title)
                .font(
                    .glabHeadline.weight(
                        .semibold
                    )
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Color.glabSurface
        )
    }

    @ViewBuilder
    private var changesContent: some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                GitLabLoadingStateView(
                    message:
                        "Loading commit changes"
                )
                .padding(20)
            }
        case let .failed(error):
            GitLabContentStateScrollView {
                GitLabRetryStateView(
                    error: error
                ) {
                    Task {
                        await retryChanges()
                    }
                }
            }
        case let .loaded(files):
            if files.isEmpty {
                GitLabContentStateScrollView {
                    GitLabEmptyStateView(
                        title: "No file changes",
                        message:
                            "GitLab did not return any changed files for this commit.",
                        systemImage:
                            "doc.text.magnifyingglass"
                    )
                }
            } else {
                changedFilesList(files)
            }
        }
    }

    private func changedFilesList(
        _ files: [GitLabDiffFile]
    ) -> some View {
        let changes = files.lineChanges

        return List {
            Section {
                HStack(spacing: 12) {
                    Label(
                        "\(files.count) "
                            + (
                                files.count == 1
                                    ? "file"
                                    : "files"
                            ),
                        systemImage:
                            "doc.on.doc"
                    )
                    .font(.glabSubheadline.weight(.medium))

                    Spacer(minLength: 10)

                    GitLabLineChangesLabel(
                        changes: changes
                    )
                }
                .accessibilityElement(
                    children: .combine
                )
            }

            Section("Changed files") {
                ForEach(files) { file in
                    NavigationLink {
                        GitLabCommitFileDiffView(
                            projectID:
                                project.id,
                            commit: commit,
                            file: file,
                            accountID:
                                accountID,
                            renderer:
                                diffRenderer
                        )
                    } label: {
                        GitLabCommitDiffFileRow(
                            file: file
                        )
                    }
                    .accessibilityIdentifier(
                        file.privacySafeIdentifier
                    )
                }
            }

            if
                let error =
                    model.refreshError
            {
                Section {
                    GitLabInlineRetryRow(
                        title:
                            "Couldn’t refresh changes",
                        error: error,
                        accessibilityIdentifier:
                            "commit.changes.refreshError"
                    ) {
                        Task {
                            await retryChanges()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await retryChanges()
        }
        .accessibilityIdentifier(
            "commit.changes"
        )
    }

    private var detailsContent: some View {
        GlabList {
            Section("Commit") {
                GitLabCopyableValueRow(
                    title: "SHA",
                    value: commit.id
                )

                LabeledContent(
                    "Authored"
                ) {
                    Text(
                        commit.authoredDate
                            .formatted(
                                date:
                                    .abbreviated,
                                time:
                                    .shortened
                            )
                    )
                }
            }

            Section("Message") {
                Text(commit.message)
                    .textSelection(.enabled)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Section("Contributors") {
                contributorRow(
                    role: "Author",
                    name: commit.authorName,
                    email:
                        commit.authorEmail
                )

                if
                    commit.committerName
                        != commit.authorName
                        || commit.committerEmail
                            != commit.authorEmail
                {
                    contributorRow(
                        role: "Committer",
                        name:
                            commit.committerName,
                        email:
                            commit
                            .committerEmail
                    )
                }
            }

            if !commit.parentIDs.isEmpty {
                Section(
                    commit.parentIDs.count == 1
                        ? "Parent"
                        : "Parents"
                ) {
                    ForEach(
                        commit.parentIDs,
                        id: \.self
                    ) {
                        GitLabCopyableValueRow(
                            title:
                                "Parent commit",
                            value: $0
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(
            "commit.details"
        )
    }

    private func contributorRow(
        role: String,
        name: String,
        email: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.glabTitle3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(name)
                    .font(
                        .glabBody.weight(
                            .medium
                        )
                    )
                Text(email)
                    .font(.glabCaption)
                    .foregroundStyle(
                        .secondary
                    )
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Text(role)
                .font(.glabSubheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(
            children: .combine
        )
    }

    private var commitMenu: some View {
        Menu {
            Button(
                "Copy commit SHA",
                systemImage: "doc.on.doc"
            ) {
                UIPasteboard.general.string =
                    commit.id
            }

            if let webURL = commit.safeWebURL {
                Link(
                    "Open in GitLab",
                    destination: webURL
                )
            }
        } label: {
            Image(
                systemName:
                    "ellipsis"
            )
        }
        .accessibilityLabel(
            "Commit actions"
        )
    }

    private func retryChanges() async {
        await model.retry()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                model.authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}

private struct GitLabCommitDiffFileRow:
    View
{
    let file: GitLabDiffFile

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(
                systemName:
                    file.kind.systemImage
            )
            .foregroundStyle(
                file.kind.color
            )
            .frame(width: 22)
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(file.newPath)
                    .font(
                        .glabBody.weight(
                            .medium
                        )
                    )
                    .lineLimit(2)

                if file.kind == .renamed {
                    Text(
                        "From \(file.oldPath)"
                    )
                    .font(.glabCaption)
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(file.kind.title)
                        .font(
                            .glabCaption2
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            file.kind.color
                        )

                    GitLabLineChangesLabel(
                        changes:
                            file.lineChanges
                    )

                    if
                        file.availability
                            != .available
                    {
                        Text(
                            file.availability
                                .shortTitle
                        )
                        .font(
                            .glabCaption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(
            children: .combine
        )
    }
}

private struct GitLabLineChangesLabel: View {
    let changes: GitLabLineChanges

    var body: some View {
        HStack(spacing: 6) {
            Text("+\(changes.additions)")
                .foregroundStyle(.green)
            Text("−\(changes.deletions)")
                .foregroundStyle(.red)
        }
        .font(
            .glabCaption
                .weight(.semibold)
                .monospacedDigit()
        )
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            "\(changes.additions) "
                + (
                    changes.additions == 1
                        ? "addition"
                        : "additions"
                )
                + ", \(changes.deletions) "
                + (
                    changes.deletions == 1
                        ? "deletion"
                        : "deletions"
                )
        )
    }
}

private struct GitLabCopyableValueRow:
    View
{
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(value)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            Button {
                UIPasteboard.general.string =
                    value
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                "Copy \(title)"
            )
        }
        .accessibilityElement(
            children: .contain
        )
    }
}

private struct GitLabCommitFileDiffView:
    View
{
    let projectID: Int
    let commit: GitLabCommit
    let file: GitLabDiffFile
    let accountID: GitLabAccountID

    @State private var model:
        GitLabDiffModel
    @State private var selectedHunkJump:
        GitLabDiffHunkJump?

    init(
        projectID: Int,
        commit: GitLabCommit,
        file: GitLabDiffFile,
        accountID: GitLabAccountID,
        renderer:
            any GitLabDiffRendering
    ) {
        self.projectID = projectID
        self.commit = commit
        self.file = file
        self.accountID = accountID
        _model = State(
            initialValue:
                GitLabDiffModel(
                    renderer: renderer
                )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            Divider()
            fileContent
        }
        .background(
            Color.glabSurface
        )
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                hunkMenu
            }
        }
        .task(id: file.diffSourceDigest) {
            model.reset()
            guard
                file.availability
                    == .available
            else {
                return
            }

            await model.load(
                GitLabDiffRequest(
                    accountID: accountID,
                    projectID: projectID,
                    commitSHA: commit.id,
                    oldPath: file.oldPath,
                    newPath: file.newPath,
                    source: file.diff
                )
            )
        }
        .accessibilityIdentifier(
            "commitDiff.file"
        )
    }

    private var fileHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            Text(file.newPath)
                .font(
                    .glabSubheadline.weight(
                        .semibold
                    )
                )
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            if file.kind == .renamed {
                Text(
                    "Renamed from \(file.oldPath)"
                )
                .font(.glabCaption)
                .foregroundStyle(
                    .secondary
                )
                .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Label(
                    file.kind.title,
                    systemImage:
                        file.kind.systemImage
                )
                .font(
                    .glabCaption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    file.kind.color
                )

                Spacer(minLength: 8)

                GitLabLineChangesLabel(
                    changes:
                        file.lineChanges
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var fileContent: some View {
        switch file.availability {
        case .available:
            renderedContent
        case .collapsed:
            unavailableContent(
                title:
                    "Diff collapsed by GitLab",
                message:
                    "This file exceeds the GitLab instance’s configured display limits."
            )
        case .tooLarge:
            unavailableContent(
                title:
                    "Diff too large to display",
                message:
                    "GitLab did not provide patch text for this file."
            )
        case .missingText:
            unavailableContent(
                title: "No patch available",
                message:
                    "This file may be binary or have no text diff."
            )
        }
    }

    @ViewBuilder
    private var renderedContent: some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                GitLabLoadingStateView(
                    message:
                        "Preparing file diff"
                )
                .padding(20)
            }
        case let .loaded(document):
            if document.items.isEmpty {
                unavailableContent(
                    title:
                        "No patch available",
                    message:
                        "GitLab returned an empty patch for this file."
                )
            } else {
                GitLabDiffDocumentView(
                    document: document,
                    documentID:
                        documentID,
                    selectedHunkJump:
                        selectedHunkJump,
                    discussionContext: nil,
                    accessibilityIdentifier:
                        "commitDiff.document",
                    onSelectDiscussion: {
                        _ in
                    }
                )
            }
        case let .failed(message):
            unavailableContent(
                title:
                    "Couldn’t display this diff",
                message: message
            )
        }
    }

    private func unavailableContent(
        title: String,
        message: String
    ) -> some View {
        GitLabContentStateScrollView {
            GitLabEmptyStateView(
                title: title,
                message: message,
                systemImage:
                    "doc.text.magnifyingglass"
            )
        }
    }

    private var hunkMenu: some View {
        Menu {
            if let document = model.document {
                ForEach(
                    document.hunks,
                    id: \.ordinal
                ) { hunk in
                    Button(
                        "Hunk \(hunk.ordinal + 1), "
                            + "new line \(hunk.newStart)"
                    ) {
                        selectedHunkJump =
                            GitLabDiffHunkJump(
                                ordinal:
                                    hunk.ordinal
                            )
                    }
                }
            }
        } label: {
            Image(
                systemName:
                    "list.bullet.rectangle"
            )
        }
        .disabled(
            model.document?.hunks
                .isEmpty != false
        )
        .accessibilityLabel("Jump to hunk")
    }

    private var documentID:
        GitLabDiffDocumentID
    {
        GitLabDiffDocumentID(
            accountID: accountID,
            projectID: projectID,
            commitSHA: commit.id,
            fileID: file.id,
            sourceDigest:
                file.diffSourceDigest
        )
    }

    private var navigationTitle: String {
        file.newPath
            .split(separator: "/")
            .last
            .map(String.init)
            ?? file.newPath
    }
}

private extension GitLabDiffFileKind {
    var title: String {
        switch self {
        case .added:
            "Added"
        case .deleted:
            "Deleted"
        case .renamed:
            "Renamed"
        case .modified:
            "Modified"
        }
    }

    var systemImage: String {
        switch self {
        case .added:
            "plus.circle.fill"
        case .deleted:
            "minus.circle.fill"
        case .renamed:
            "arrow.right.circle.fill"
        case .modified:
            "pencil.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added:
            .green
        case .deleted:
            .red
        case .renamed:
            .blue
        case .modified:
            .orange
        }
    }
}

private extension GitLabDiffAvailability {
    var shortTitle: String {
        switch self {
        case .available:
            ""
        case .collapsed:
            "Collapsed"
        case .tooLarge:
            "Too large"
        case .missingText:
            "No patch"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
