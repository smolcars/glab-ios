import Foundation
import SwiftUI

private struct GitLabDiffRendererEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabDiffRendering =
            GitLabDiffRenderer()
}

extension EnvironmentValues {
    var gitLabDiffRenderer:
        any GitLabDiffRendering
    {
        get {
            self[
                GitLabDiffRendererEnvironmentKey.self
            ]
        }
        set {
            self[
                GitLabDiffRendererEnvironmentKey.self
            ] = newValue
        }
    }
}

struct GitLabMergeRequestDiffListView: View {
    let route: GitLabMergeRequestRoute
    let headSHA: String
    let changesURL: URL?
    let diffVersion:
        GitLabMergeRequestDiffVersionIdentity?
    let discussionModel:
        GitLabDiscussionsModel
    let resolutionModel:
        GitLabDiscussionResolutionModel
    let apiAccess: GitLabAPIAccess
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.gitLabDiffRenderer)
    private var diffRenderer
    @State private var model:
        GitLabMergeRequestDiffsModel
    @State private var discussionIndex:
        GitLabDiffDiscussionIndex?

    init(
        route: GitLabMergeRequestRoute,
        headSHA: String,
        changesURL: URL?,
        diffVersion:
            GitLabMergeRequestDiffVersionIdentity?,
        loader: any GitLabMergeRequestDiffLoading,
        discussionModel:
            GitLabDiscussionsModel,
        resolutionModel:
            GitLabDiscussionResolutionModel,
        apiAccess: GitLabAPIAccess,
        discussionMutator:
            any GitLabDiscussionMutating,
        reactionService:
            any GitLabEmojiReactionLoading
                & GitLabEmojiReactionMutating,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.route = route
        self.headSHA = headSHA
        self.changesURL = changesURL
        self.diffVersion = diffVersion
        self.discussionModel =
            discussionModel
        self.resolutionModel =
            resolutionModel
        self.apiAccess = apiAccess
        self.discussionMutator =
            discussionMutator
        self.reactionService =
            reactionService
        self.accountID = accountID
        self.appSession = appSession
        _discussionIndex = State(
            initialValue:
                diffVersion.map {
                    GitLabDiffDiscussionIndex(
                        discussions:
                            discussionModel
                            .discussions,
                        currentVersion: $0
                    )
                }
        )
        _model = State(
            initialValue:
                GitLabMergeRequestDiffsModel(
                    route: route,
                    headSHA: headSHA,
                    loader: loader
                )
        )
    }

    var body: some View {
        @Bindable var model = model

        content
            .background(
                Color.glabCanvas
            )
            .navigationTitle("Changed Files")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                GitLabSearchField(
                    text: $model.searchText,
                    prompt:
                        "Search loaded file paths",
                    accessibilityIdentifier:
                        "mergeRequestDiffs.search"
                )
            }
            .ignoresSafeArea(
                .keyboard,
                edges: .bottom
            )
            .refreshable {
                await refresh()
            }
            .task {
                await load()
            }
            .onChange(
                of:
                    discussionModel
                    .contentRevision,
                initial: true
            ) { _, _ in
                rebuildDiscussionIndex()
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingInitial {
            ScrollView {
                GitLabLoadingStateView(
                    message: "Loading changed files"
                )
                .padding(20)
            }
        } else if
            model.files.isEmpty,
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
            model.files.isEmpty,
            model.hasLoaded
        {
            GitLabContentStateScrollView {
                GitLabEmptyStateView(
                    title: "No changed files",
                    message:
                        "GitLab did not return any changed files "
                        + "for this merge request revision.",
                    systemImage:
                        "doc.text.magnifyingglass"
                )
            }
        } else {
            fileList
        }
    }

    private var fileList: some View {
        GlabList {
            if model.isRefreshing {
                Label(
                    "Updating changed files…",
                    systemImage: "arrow.clockwise"
                )
                .font(.glabFootnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier(
                    "mergeRequestDiffs.refreshing"
                )
            } else if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t refresh changed files",
                    error: error,
                    accessibilityIdentifier:
                        "mergeRequestDiffs.refreshError"
                ) {
                    Task {
                        await refresh()
                    }
                }
            }

            discussionLoadingState

            if
                model.displayedFiles.isEmpty,
                !model.searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            {
                ContentUnavailableView.search(
                    text: model.searchText
                )
                .listRowBackground(Color.clear)
            } else {
                Section(fileCountTitle) {
                    ForEach(model.displayedFiles) { file in
                        NavigationLink {
                            GitLabMergeRequestDiffFileView(
                                filesModel: model,
                                initialFileID: file.id,
                                route: route,
                                headSHA: headSHA,
                                changesURL: changesURL,
                                diffVersion:
                                    diffVersion,
                                discussionModel:
                                    discussionModel,
                                resolutionModel:
                                    resolutionModel,
                                discussionIndex:
                                    discussionIndex,
                                apiAccess:
                                    apiAccess,
                                discussionMutator:
                                    discussionMutator,
                                reactionService:
                                    reactionService,
                                accountID: accountID,
                                renderer: diffRenderer,
                                appSession:
                                    appSession
                            )
                        } label: {
                            GitLabMergeRequestDiffFileRow(
                                file: file
                            )
                        }
                        .accessibilityIdentifier(
                            file.privacySafeIdentifier
                        )
                        .task {
                            await model
                                .loadNextPageIfNeeded(
                                    after: file
                                )
                            await
                                handleAuthenticationFailure()
                        }
                    }
                }
            }

            if model.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more files…")
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
                        "Couldn’t load more changed files",
                    error: error,
                    accessibilityIdentifier:
                        "mergeRequestDiffs.nextPageError"
                ) {
                    Task {
                        await model.retryNextPage()
                        await
                            handleAuthenticationFailure()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(
            "mergeRequestDiffs.list"
        )
    }

    private var fileCountTitle: String {
        if let total = model.totalItemCount {
            return "\(total) changed "
                + (total == 1 ? "file" : "files")
        }
        return "\(model.files.count) loaded "
            + (model.files.count == 1 ? "file" : "files")
    }

    private func load() async {
        async let files: Void =
            model.loadIfNeeded()
        async let discussions: Void =
            loadAllDiscussions()
        _ = await (files, discussions)
        await handleAuthenticationFailure()
    }

    private func refresh() async {
        async let files: Void =
            model.refresh()
        async let discussions: Void =
            refreshAllDiscussions()
        _ = await (files, discussions)
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure() async {
        guard
            let error =
                model.authenticationFailure
                ?? discussionModel
                    .authenticationFailure
        else {
            return
        }
        await appSession.handleAuthenticationFailure(
            error,
            for: accountID
        )
    }

    private func loadAllDiscussions() async {
        await discussionModel.loadIfNeeded()
        await discussionModel
            .loadAllRemainingPages()
    }

    private func refreshAllDiscussions() async {
        await discussionModel.refresh()
        await discussionModel
            .loadAllRemainingPages()
    }

    private func retryDiscussionLoad() async {
        if discussionModel.didFailNextPage {
            await discussionModel
                .loadAllRemainingPages()
        } else {
            await refreshAllDiscussions()
        }
        await handleAuthenticationFailure()
    }

    @ViewBuilder
    private var discussionLoadingState:
        some View
    {
        if
            discussionModel.isLoadingInitial
                || discussionModel.isRefreshing
                || discussionModel.isLoadingNextPage
        {
            Label(
                "Loading inline discussions…",
                systemImage:
                    "bubble.left.and.text.bubble.right"
            )
            .font(.glabFootnote)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier(
                "mergeRequestDiffs.discussionsLoading"
            )
        } else if
            let error = discussionModel.loadError
        {
            GitLabInlineRetryRow(
                title:
                    "Couldn’t load all inline discussions",
                error: error,
                accessibilityIdentifier:
                    "mergeRequestDiffs.discussionsError"
            ) {
                Task {
                    await retryDiscussionLoad()
                }
            }
        }
    }

    private func rebuildDiscussionIndex() {
        discussionIndex = diffVersion.map {
            GitLabDiffDiscussionIndex(
                discussions:
                    discussionModel.discussions,
                currentVersion: $0
            )
        }
    }
}

private struct GitLabMergeRequestDiffFileRow: View {
    let file: GitLabMergeRequestDiffFile

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kindSystemImage)
                .frame(width: 22)
                .foregroundStyle(kindColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(file.newPath)
                    .font(.glabBody.weight(.medium))
                    .lineLimit(2)

                if file.kind == .renamed {
                    Text("From \(file.oldPath)")
                        .font(.glabCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    GitLabDiffBadge(
                        title: kindTitle,
                        color: kindColor
                    )

                    if file.isGeneratedFile {
                        GitLabDiffBadge(
                            title: "Generated",
                            color: .secondary
                        )
                    }
                    if file.isCollapsed {
                        GitLabDiffBadge(
                            title: "Collapsed",
                            color: .orange
                        )
                    }
                    if file.isTooLarge {
                        GitLabDiffBadge(
                            title: "Too large",
                            color: .red
                        )
                    } else if
                        file.availability == .missingText
                    {
                        GitLabDiffBadge(
                            title: "No patch",
                            color: .secondary
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [
            file.newPath,
            kindTitle,
        ]
        if file.kind == .renamed {
            parts.append("Renamed from \(file.oldPath)")
        }
        if file.isGeneratedFile {
            parts.append("Generated file")
        }
        switch file.availability {
        case .available:
            break
        case .collapsed:
            parts.append("Diff collapsed by GitLab")
        case .tooLarge:
            parts.append("Diff too large to display")
        case .missingText:
            parts.append("No patch text available")
        }
        return parts.joined(separator: ", ")
    }

    private var kindTitle: String {
        switch file.kind {
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

    private var kindSystemImage: String {
        switch file.kind {
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

    private var kindColor: Color {
        switch file.kind {
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

private struct GitLabDiffBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.glabCaption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                color.opacity(0.12),
                in: .capsule
            )
    }
}

private struct GitLabMergeRequestDiffFileView: View {
    let filesModel: GitLabMergeRequestDiffsModel
    let route: GitLabMergeRequestRoute
    let headSHA: String
    let changesURL: URL?
    let diffVersion:
        GitLabMergeRequestDiffVersionIdentity?
    let discussionModel:
        GitLabDiscussionsModel
    let resolutionModel:
        GitLabDiscussionResolutionModel
    let discussionIndex:
        GitLabDiffDiscussionIndex?
    let apiAccess: GitLabAPIAccess
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let accountID: GitLabAccountID
    let appSession: AppSession

    @State private var selectedFileID:
        GitLabMergeRequestDiffFileID
    @State private var model: GitLabDiffModel
    @State private var selectedHunkJump:
        GitLabDiffHunkJump?
    @State private var selectedLine:
        GitLabDiffLineSelection?
    @State private var showsAllDiscussions =
        false

    init(
        filesModel: GitLabMergeRequestDiffsModel,
        initialFileID:
            GitLabMergeRequestDiffFileID,
        route: GitLabMergeRequestRoute,
        headSHA: String,
        changesURL: URL?,
        diffVersion:
            GitLabMergeRequestDiffVersionIdentity?,
        discussionModel:
            GitLabDiscussionsModel,
        resolutionModel:
            GitLabDiscussionResolutionModel,
        discussionIndex:
            GitLabDiffDiscussionIndex?,
        apiAccess: GitLabAPIAccess,
        discussionMutator:
            any GitLabDiscussionMutating,
        reactionService:
            any GitLabEmojiReactionLoading
                & GitLabEmojiReactionMutating,
        accountID: GitLabAccountID,
        renderer: any GitLabDiffRendering,
        appSession: AppSession
    ) {
        self.filesModel = filesModel
        self.route = route
        self.headSHA = headSHA
        self.changesURL = changesURL
        self.diffVersion = diffVersion
        self.discussionModel =
            discussionModel
        self.resolutionModel =
            resolutionModel
        self.discussionIndex =
            discussionIndex
        self.apiAccess = apiAccess
        self.discussionMutator =
            discussionMutator
        self.reactionService =
            reactionService
        self.accountID = accountID
        self.appSession = appSession
        _selectedFileID = State(
            initialValue: initialFileID
        )
        _model = State(
            initialValue:
                GitLabDiffModel(
                    renderer: renderer
                )
        )
    }

    var body: some View {
        Group {
            if let file = selectedFile {
                VStack(spacing: 0) {
                    fileHeader(file)
                    Divider()
                    fileContent(file)
                }
            } else {
                GitLabContentStateScrollView {
                    GitLabEmptyStateView(
                        title: "File no longer loaded",
                        message:
                            "Return to the changed-file list "
                            + "and select this file again.",
                        systemImage: "doc.questionmark"
                    )
                }
            }
        }
        .background(
            Color.glabSurface
        )
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            fileNavigationToolbar
        }
        .sheet(item: $selectedLine) {
            selection in
            GitLabDiffLineDiscussionSheet(
                selection: selection,
                discussions:
                    discussionIndex?
                    .discussions(
                        at:
                            selection
                            .position
                    )
                    ?? [],
                resource:
                    .mergeRequest(route),
                accountID: accountID,
                webURL:
                    mergeRequestWebURL,
                apiAccess: apiAccess,
                model: discussionModel,
                mutator:
                    discussionMutator,
                resolutionModel:
                    resolutionModel,
                reactionService:
                    reactionService,
                appSession: appSession,
                onSuccess: reconcile
            )
        }
        .sheet(
            isPresented:
                $showsAllDiscussions
        ) {
            if let discussionIndex {
                GitLabAllDiffDiscussionsSheet(
                    index: discussionIndex,
                    resource:
                        .mergeRequest(route),
                    accountID: accountID,
                    webURL:
                        mergeRequestWebURL,
                    apiAccess: apiAccess,
                    model: discussionModel,
                    mutator:
                        discussionMutator,
                    resolutionModel:
                        resolutionModel,
                    reactionService:
                        reactionService,
                    appSession: appSession,
                    onSuccess: reconcile
                )
            }
        }
        .task(id: selectedDocumentID) {
            selectedHunkJump = nil
            model.reset()
            guard
                let file = selectedFile,
                file.availability == .available
            else {
                return
            }

            await model.load(
                GitLabDiffRequest(
                    accountID: accountID,
                    route: route,
                    headSHA: headSHA,
                    oldPath: file.oldPath,
                    newPath: file.newPath,
                    source: file.diff
                )
            )
        }
        .accessibilityIdentifier(
            "mergeRequestDiffs.file"
        )
    }

    @ViewBuilder
    private func fileContent(
        _ file: GitLabMergeRequestDiffFile
    ) -> some View {
        switch file.availability {
        case .available:
            renderedContent
        case .collapsed:
            unavailableContent(
                title: "Diff collapsed by GitLab",
                message:
                    "This file exceeds GitLab’s configured "
                    + "display limits. Open the merge request "
                    + "in GitLab to inspect it."
            )
        case .tooLarge:
            unavailableContent(
                title: "Diff too large to display",
                message:
                    "GitLab did not provide patch text for "
                    + "this file because it is too large."
            )
        case .missingText:
            unavailableContent(
                title: "No patch available",
                message:
                    "GitLab did not provide text for this file. "
                    + "It may be binary, generated, or unchanged "
                    + "in this diff."
            )
        }
    }

    @ViewBuilder
    private var renderedContent: some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                GitLabLoadingStateView(
                    message: "Preparing file diff"
                )
                .padding(20)
            }
        case let .loaded(document):
            if document.items.isEmpty {
                unavailableContent(
                    title: "No patch available",
                    message:
                        "GitLab returned an empty patch "
                        + "for this file."
                )
            } else if let selectedDocumentID {
                GitLabDiffDocumentView(
                    document: document,
                    documentID:
                        selectedDocumentID,
                    selectedHunkJump:
                        selectedHunkJump,
                    discussionContext:
                        discussionContext,
                    onSelectDiscussion: {
                        selectedLine =
                            GitLabDiffLineSelection(
                                position: $0
                            )
                    }
                )
            } else {
                unavailableContent(
                    title: "File no longer loaded",
                    message:
                        "Return to the changed-file list "
                        + "and select this file again."
                )
            }
        case let .failed(message):
            unavailableContent(
                title: "Couldn’t display this diff",
                message: message
            )
        }
    }

    private func unavailableContent(
        title: String,
        message: String
    ) -> some View {
        GitLabContentStateScrollView {
            VStack(spacing: 6) {
                GitLabEmptyStateView(
                    title: title,
                    message: message,
                    systemImage:
                        "doc.text.magnifyingglass"
                )

                if let changesURL {
                    GitLabOpenInGitLabLink(
                        destination: changesURL,
                        accessibilityIdentifier:
                            "mergeRequestDiffs.openInGitLab"
                    )
                }
            }
        }
    }

    private func fileHeader(
        _ file: GitLabMergeRequestDiffFile
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(file.newPath)
                .font(.glabSubheadline.weight(.semibold))
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            if file.kind == .renamed {
                Text("Renamed from \(file.oldPath)")
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                GitLabDiffBadge(
                    title: fileKindTitle(file),
                    color: fileKindColor(file)
                )
                if file.isGeneratedFile {
                    GitLabDiffBadge(
                        title: "Generated",
                        color: .secondary
                    )
                }

                Spacer(minLength: 8)

                Text(filePosition)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if allDiscussionCount > 0 {
                Button {
                    showsAllDiscussions = true
                } label: {
                    Label(
                        "\(allDiscussionCount) diff "
                            + (
                                allDiscussionCount == 1
                                    ? "discussion"
                                    : "discussions"
                            ),
                        systemImage:
                            "bubble.left.and.exclamationmark.bubble.right"
                    )
                    .font(.glabCaption.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier(
                    "mergeRequestDiffs.otherDiscussions"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ToolbarContentBuilder
    private var fileNavigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                selectFile(offset: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!hasPreviousFile)
            .accessibilityLabel("Previous changed file")

            Button {
                selectFile(offset: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(!hasNextFile)
            .accessibilityLabel("Next changed file")

            Menu {
                if let document = model.document {
                    ForEach(document.hunks, id: \.ordinal) {
                        hunk in
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
                    systemName: "list.bullet.rectangle"
                )
            }
            .disabled(model.document?.hunks.isEmpty != false)
            .accessibilityLabel("Jump to hunk")
        }
    }

    private var selectedFile:
        GitLabMergeRequestDiffFile?
    {
        filesModel.files.first {
            $0.id == selectedFileID
        }
    }

    private var selectedDocumentID:
        GitLabDiffDocumentID?
    {
        guard let selectedFile else {
            return nil
        }
        return GitLabDiffDocumentID(
            accountID: accountID,
            route: route,
            headSHA: headSHA,
            fileID: selectedFileID,
            sourceDigest:
                selectedFile.diffSourceDigest
        )
    }

    private var selectedFileIndex: Int? {
        filesModel.files.firstIndex {
            $0.id == selectedFileID
        }
    }

    private var discussionContext:
        GitLabDiffDiscussionContext?
    {
        guard
            let diffVersion,
            let discussionIndex,
            let selectedFile
        else {
            return nil
        }
        return GitLabDiffDiscussionContext(
            version: diffVersion,
            oldPath: selectedFile.oldPath,
            newPath: selectedFile.newPath,
            index: discussionIndex,
            revision:
                discussionModel.contentRevision,
            allowsCommenting:
                apiAccess.canWrite
        )
    }

    private var allDiscussionCount: Int {
        discussionIndex?
            .positionedDiscussionCount
            ?? 0
    }

    private var mergeRequestWebURL: URL? {
        changesURL?
            .deletingLastPathComponent()
    }

    private var hasPreviousFile: Bool {
        guard let selectedFileIndex else {
            return false
        }
        return selectedFileIndex > 0
    }

    private var hasNextFile: Bool {
        guard let selectedFileIndex else {
            return false
        }
        return selectedFileIndex
            < filesModel.files.count - 1
    }

    private var filePosition: String {
        guard let selectedFileIndex else {
            return "Unknown position"
        }
        return "\(selectedFileIndex + 1) of "
            + "\(filesModel.files.count) loaded"
    }

    private var navigationTitle: String {
        guard let selectedFile else {
            return "File Diff"
        }
        return selectedFile.newPath
            .split(separator: "/")
            .last
            .map(String.init)
            ?? selectedFile.newPath
    }

    private func selectFile(offset: Int) {
        guard let selectedFileIndex else {
            return
        }
        let destination = selectedFileIndex + offset
        guard
            filesModel.files.indices
                .contains(destination)
        else {
            return
        }
        selectedFileID =
            filesModel.files[destination].id
    }

    private func reconcile(
        _ result:
            GitLabDiscussionComposerResult
    ) {
        switch result {
        case let .discussion(discussion):
            discussionModel
                .reconcileCreatedDiscussion(
                    discussion
                )
        case let .reply(
            note,
            discussionID
        ):
            discussionModel
                .reconcileCreatedReply(
                    note,
                    discussionID:
                        discussionID
                )
        }
    }

    private func fileKindTitle(
        _ file: GitLabMergeRequestDiffFile
    ) -> String {
        switch file.kind {
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

    private func fileKindColor(
        _ file: GitLabMergeRequestDiffFile
    ) -> Color {
        switch file.kind {
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

struct GitLabDiffHunkJump: Equatable {
    let id = UUID()
    let ordinal: Int
}

struct GitLabDiffDocumentView: View {
    let document: GitLabParsedDiffDocument
    let documentID: GitLabDiffDocumentID
    let selectedHunkJump: GitLabDiffHunkJump?
    let discussionContext:
        GitLabDiffDiscussionContext?
    let accessibilityIdentifier: String
    let onSelectDiscussion:
        @MainActor (
            GitLabDiffLinePosition
        ) -> Void

    @ScaledMetric(relativeTo: .caption)
    private var rowHeight: CGFloat =
        GitLabDiffLayoutMetrics.baseRowHeight

    init(
        document: GitLabParsedDiffDocument,
        documentID: GitLabDiffDocumentID,
        selectedHunkJump:
            GitLabDiffHunkJump?,
        discussionContext:
            GitLabDiffDiscussionContext?,
        accessibilityIdentifier: String =
            "mergeRequestDiffs.document",
        onSelectDiscussion:
            @escaping @MainActor (
                GitLabDiffLinePosition
            ) -> Void
    ) {
        self.document = document
        self.documentID = documentID
        self.selectedHunkJump =
            selectedHunkJump
        self.discussionContext =
            discussionContext
        self.accessibilityIdentifier =
            accessibilityIdentifier
        self.onSelectDiscussion =
            onSelectDiscussion
    }

    var body: some View {
        GitLabDiffCollectionView(
            document: document,
            documentID: documentID,
            selectedHunkJump: selectedHunkJump,
            rowHeight: rowHeight,
            contentWidth: minimumContentWidth,
            discussionContext:
                discussionContext,
            accessibilityIdentifier:
                accessibilityIdentifier,
            onSelectDiscussion:
                onSelectDiscussion
        )
    }

    private var minimumContentWidth: CGFloat {
        GitLabDiffLayoutMetrics.contentWidth(
            maximumColumnCount:
                document.maximumRenderedColumnCount,
            rowHeight: rowHeight
        )
    }
}
