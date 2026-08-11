import SwiftUI
import UIKit

struct GitLabRepositoryView: View {
    let project: GitLabProject
    let loader: any GitLabRepositoryLoading
    let accountID: GitLabAccountID
    let appSession: AppSession

    @State private var selectedRef: String
    @State private var isBranchPickerPresented =
        false

    init(
        project: GitLabProject,
        loader: any GitLabRepositoryLoading,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.project = project
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        _selectedRef = State(
            initialValue:
                project.defaultBranch ?? "HEAD"
        )
    }

    var body: some View {
        GitLabRepositoryDirectoryView(
            project: project,
            ref: selectedRef,
            path: "",
            isRoot: true,
            loader: loader,
            accountID: accountID,
            appSession: appSession
        ) {
            isBranchPickerPresented = true
        }
        .id(selectedRef)
        .sheet(
            isPresented:
                $isBranchPickerPresented
        ) {
            NavigationStack {
                GitLabRepositoryBranchPickerView(
                    projectID: project.id,
                    defaultBranchName:
                        project.defaultBranch,
                    selectedRef: selectedRef,
                    loader: loader,
                    accountID: accountID,
                    appSession: appSession
                ) { branch in
                    selectedRef = branch.name
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct GitLabRepositoryDirectoryView:
    View
{
    let project: GitLabProject
    let ref: String
    let path: String
    let isRoot: Bool
    let loader: any GitLabRepositoryLoading
    let accountID: GitLabAccountID
    let appSession: AppSession
    let changeBranch: () -> Void

    @State private var model:
        GitLabRepositoryDirectoryModel
    @State private var searchModel:
        GitLabRepositorySearchModel
    @State private var searchText = ""

    init(
        project: GitLabProject,
        ref: String,
        path: String,
        isRoot: Bool,
        loader: any GitLabRepositoryLoading,
        accountID: GitLabAccountID,
        appSession: AppSession,
        changeBranch: @escaping () -> Void
    ) {
        self.project = project
        self.ref = ref
        self.path = path
        self.isRoot = isRoot
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        self.changeBranch = changeBranch
        _model = State(
            initialValue:
                GitLabRepositoryDirectoryModel(
                    projectID: project.id,
                    ref: ref,
                    path: path,
                    loader: loader
                )
        )
        _searchModel = State(
            initialValue:
                GitLabRepositorySearchModel(
                    projectID: project.id,
                    ref: ref,
                    loader: loader
                )
        )
    }

    var body: some View {
        content
            .accessibilityIdentifier(
                isRoot
                    ? "repository.root"
                    : "repository.directory"
            )
            .scrollDismissesKeyboard(
                .interactively
            )
            .background(Color.glabCanvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                GitLabSearchField(
                    text: $searchText,
                    prompt: "Search repository",
                    accessibilityIdentifier:
                        "repository.search"
                )
            }
            .ignoresSafeArea(
                .keyboard,
                edges: .bottom
            )
            .toolbar {
                if isRoot {
                    ToolbarItem(
                        placement: .topBarTrailing
                    ) {
                        Button(action: changeBranch) {
                            Label(
                                ref,
                                systemImage:
                                    "arrow.triangle.branch"
                            )
                            .lineLimit(1)
                        }
                        .accessibilityLabel(
                            "Change branch, current branch \(ref)"
                        )
                        .accessibilityIdentifier(
                            "repository.branchButton"
                        )
                    }
                }
            }
            .refreshable {
                if trimmedSearchText.isEmpty {
                    await model.refresh()
                } else {
                    await searchModel.retry()
                }
                await handleAuthenticationFailure()
            }
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
            .task(id: searchText) {
                await updateSearch()
            }
            .onChange(
                of: model.authenticationFailure
            ) { _, error in
                handleAuthenticationFailure(error)
            }
            .onChange(
                of:
                    searchModel
                    .authenticationFailure
            ) { _, error in
                handleAuthenticationFailure(error)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !trimmedSearchText.isEmpty {
            searchContent
        } else if model.isLoadingInitial {
            ScrollView {
                GitLabLoadingStateView(
                    message: "Loading files"
                )
                .padding(20)
            }
        } else if
            model.items.isEmpty,
            let error = model.loadError
        {
            GitLabContentStateScrollView {
                GitLabRetryStateView(error: error) {
                    Task {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                }
            }
        } else if
            model.items.isEmpty,
            model.hasLoaded
        {
            GitLabContentStateScrollView {
                GitLabEmptyStateView(
                    title: "No files",
                    message: path.isEmpty
                        ? "This branch is empty."
                        : "This folder is empty.",
                    systemImage: "folder"
                )
            }
        } else {
            directoryList
        }
    }

    private var directoryList: some View {
        GlabList {
            if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title: "Couldn’t refresh files",
                    error: error,
                    accessibilityIdentifier:
                        "repository.refreshError"
                ) {
                    Task {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                }
            }

            ForEach(model.sortedRepositoryEntries) {
                entry in
                repositoryEntryRow(entry)
                    .task {
                        await model
                            .loadNextPageIfNeeded(
                                after: entry
                            )
                        await handleAuthenticationFailure()
                    }
            }

            paginationRow
        }
        .listStyle(.plain)
        .accessibilityIdentifier(
            "repository.directoryList"
        )
    }

    @ViewBuilder
    private func repositoryEntryRow(
        _ entry: GitLabRepositoryEntry
    ) -> some View {
        if entry.isDirectory {
            NavigationLink {
                GitLabRepositoryDirectoryView(
                    project: project,
                    ref: ref,
                    path: entry.path,
                    isRoot: false,
                    loader: loader,
                    accountID: accountID,
                    appSession: appSession,
                    changeBranch: changeBranch
                )
            } label: {
                GitLabRepositoryEntryLabel(
                    name: entry.name,
                    detail: nil,
                    systemImage: entry.systemImage,
                    isDirectory: true
                )
            }
            .accessibilityHint("Opens this folder.")
        } else if entry.isFile {
            NavigationLink {
                fileView(
                    path: entry.path,
                    ref: ref,
                    blobID: entry.id
                )
            } label: {
                GitLabRepositoryEntryLabel(
                    name: entry.name,
                    detail: nil,
                    systemImage: entry.systemImage,
                    isDirectory: false
                )
            }
            .accessibilityHint("Opens this file.")
        } else {
            GitLabRepositoryEntryLabel(
                name: entry.name,
                detail: entry.isSubmodule
                    ? "Git submodule"
                    : "Unsupported entry",
                systemImage: entry.systemImage,
                isDirectory: false
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var paginationRow: some View {
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
                title: "Couldn’t load more files",
                error: error,
                accessibilityIdentifier:
                    "repository.nextPageError"
            ) {
                Task {
                    await model.retryNextPage()
                    await handleAuthenticationFailure()
                }
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if
            searchModel.isSearching,
            searchModel.results.isEmpty
        {
            ScrollView {
                GitLabLoadingStateView(
                    message: "Searching files"
                )
                .padding(20)
            }
        } else if
            searchModel.results.isEmpty,
            let error = searchModel.error
        {
            GitLabContentStateScrollView {
                GitLabRetryStateView(error: error) {
                    Task {
                        await searchModel.retry()
                        await handleAuthenticationFailure()
                    }
                }
            }
        } else if
            searchModel.results.isEmpty,
            searchModel.didSearch
        {
            ContentUnavailableView.search(
                text: trimmedSearchText
            )
        } else {
            searchResultsList
        }
    }

    private var searchResultsList: some View {
        GlabList {
            ForEach(searchModel.results) { result in
                NavigationLink {
                    fileView(
                        path: result.path,
                        ref: result.ref.isEmpty
                            ? ref
                            : result.ref,
                        blobID: result.blobID
                    )
                } label: {
                    GitLabRepositoryEntryLabel(
                        name: result.displayName,
                        detail: result.parentPath,
                        systemImage: "doc.text",
                        isDirectory: false
                    )
                }
                .task {
                    await searchModel
                        .loadNextPageIfNeeded(
                            after: result
                        )
                    await handleAuthenticationFailure()
                }
            }

            if searchModel.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more…")
                        .font(.glabFootnote)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let error = searchModel.error {
                GitLabInlineRetryRow(
                    title: "Couldn’t load more results",
                    error: error,
                    accessibilityIdentifier:
                        "repository.searchNextPageError"
                ) {
                    Task {
                        guard
                            let last = searchModel
                                .results.last
                        else {
                            await searchModel.retry()
                            return
                        }
                        await searchModel
                            .loadNextPageIfNeeded(
                                after: last
                            )
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier(
            "repository.searchResults"
        )
    }

    private func fileView(
        path: String,
        ref: String,
        blobID: String?
    ) -> some View {
        GitLabRepositoryFileView(
            route: GitLabRepositoryFileRoute(
                projectID: project.id,
                projectWebURL: project.webURL,
                ref: ref,
                path: path,
                blobID: blobID
            ),
            loader: loader,
            accountID: accountID,
            appSession: appSession
        )
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var title: String {
        guard !path.isEmpty else {
            return "Code"
        }
        return URL(filePath: path)
            .lastPathComponent
    }

    private func updateSearch() async {
        let query = trimmedSearchText
        guard !query.isEmpty else {
            await searchModel.search("")
            return
        }

        do {
            try await Task.sleep(
                for: .milliseconds(300)
            )
        } catch {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        await searchModel.search(query)
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error = model.authenticationFailure
                ?? searchModel
                    .authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }

    private func handleAuthenticationFailure(
        _ error: GitLabSessionClientError?
    ) {
        guard let error else {
            return
        }
        Task {
            await appSession
                .handleAuthenticationFailure(
                    error,
                    for: accountID
                )
        }
    }
}

private struct GitLabRepositoryEntryLabel: View {
    let name: String
    let detail: String?
    let systemImage: String
    let isDirectory: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.glabBody)
                .foregroundStyle(
                    isDirectory
                        ? Color.glabAccent
                        : Color.secondary
                )
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(name)
                    .font(.glabBody)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.glabCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(minHeight: 38)
        .accessibilityElement(children: .combine)
    }
}

private struct GitLabRepositoryBranchPickerView:
    View
{
    let projectID: Int
    let defaultBranchName: String?
    let selectedRef: String
    let loader: any GitLabRepositoryBrowsing
    let accountID: GitLabAccountID
    let appSession: AppSession
    let select: (GitLabRepositoryBranch) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model:
        GitLabRepositoryBranchesModel
    @State private var searchModel:
        GitLabRepositoryBranchesModel?
    @State private var searchText = ""

    init(
        projectID: Int,
        defaultBranchName: String?,
        selectedRef: String,
        loader: any GitLabRepositoryBrowsing,
        accountID: GitLabAccountID,
        appSession: AppSession,
        select:
            @escaping (GitLabRepositoryBranch) -> Void
    ) {
        self.projectID = projectID
        self.defaultBranchName = defaultBranchName
        self.selectedRef = selectedRef
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        self.select = select
        _model = State(
            initialValue:
                GitLabRepositoryBranchesModel(
                    projectID: projectID,
                    defaultBranchName:
                        defaultBranchName,
                    loader: loader
                )
        )
    }

    var body: some View {
        content
            .scrollDismissesKeyboard(
                .interactively
            )
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                GitLabSearchField(
                    text: $searchText,
                    prompt: "Find a branch",
                    accessibilityIdentifier:
                        "repository.branchSearch"
                )
            }
            .ignoresSafeArea(
                .keyboard,
                edges: .bottom
            )
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
            .task(id: searchText) {
                await updateSearch()
            }
            .background(Color.glabCanvas)
    }

    @ViewBuilder
    private var content: some View {
        if activeModel.isLoadingInitial {
            GitLabContentStateScrollView {
                GitLabLoadingStateView(
                    message: "Loading branches"
                )
            }
        } else if
            activeModel.items.isEmpty,
            let error = activeModel.loadError
        {
            GitLabContentStateScrollView {
                GitLabRetryStateView(error: error) {
                    Task {
                        await activeModel.refresh()
                        await handleAuthenticationFailure()
                    }
                }
            }
        } else {
            branchList
        }
    }

    private var branchList: some View {
        GlabList {
            if
                activeModel.items.isEmpty,
                !trimmedSearchText.isEmpty
            {
                ContentUnavailableView.search(
                    text: trimmedSearchText
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(
                    activeModel
                        .sortedRepositoryBranches
                ) {
                    branch in
                    Button {
                        select(branch)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName:
                                    "arrow.triangle.branch"
                            )
                            .foregroundStyle(
                                Color.glabAccent
                            )
                            .accessibilityHidden(true)

                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(branch.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if branch.isDefault {
                                    Text("Default")
                                        .font(.glabCaption)
                                        .foregroundStyle(.secondary)
                                } else if branch.isProtected {
                                    Text("Protected")
                                        .font(.glabCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 8)

                            if branch.name == selectedRef {
                                Image(systemName: "checkmark")
                                    .font(.glabBody.bold())
                                    .foregroundStyle(
                                        Color.glabAccent
                                    )
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .task {
                        await activeModel
                            .loadNextPageIfNeeded(
                                after: branch
                            )
                        await handleAuthenticationFailure()
                    }
                }
            }

            if activeModel.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more…")
                        .font(.glabFootnote)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if
                activeModel.didFailNextPage,
                let error = activeModel.loadError
            {
                GitLabInlineRetryRow(
                    title: "Couldn’t load more branches",
                    error: error,
                    accessibilityIdentifier:
                        "repository.branchesNextPageError"
                ) {
                    Task {
                        await activeModel.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier(
            "repository.branches"
        )
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error = searchModel?
                .authenticationFailure
                ?? model.authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }

    private var activeModel:
        GitLabRepositoryBranchesModel
    {
        searchModel ?? model
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func updateSearch() async {
        let query = trimmedSearchText
        guard !query.isEmpty else {
            searchModel = nil
            return
        }
        do {
            try await Task.sleep(
                for: .milliseconds(250)
            )
        } catch {
            return
        }
        guard !Task.isCancelled else {
            return
        }

        let model = GitLabRepositoryBranchesModel(
            projectID: projectID,
            defaultBranchName:
                defaultBranchName,
            search: query,
            loader: loader
        )
        searchModel = model
        await model.loadIfNeeded()
        guard
            !Task.isCancelled,
            query == trimmedSearchText
        else {
            return
        }
        await handleAuthenticationFailure()
    }
}

struct GitLabRepositoryFileView: View {
    let route: GitLabRepositoryFileRoute
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer
    @State private var model:
        GitLabRepositoryFileModel
    @State private var presentation:
        GitLabRepositoryFilePresentation

    init(
        route: GitLabRepositoryFileRoute,
        loader: any GitLabRepositorySourceLoading,
        accountID: GitLabAccountID,
        appSession: AppSession,
        initialPresentation:
            GitLabRepositoryFilePresentation =
                .rendered
    ) {
        self.route = route
        self.accountID = accountID
        self.appSession = appSession
        _presentation = State(
            initialValue: initialPresentation
        )
        _model = State(
            initialValue:
                GitLabRepositoryFileModel(
                    route: route,
                    loader: loader
                )
        )
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(route.fileName)
                            .font(.glabHeadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(fileSubtitle)
                            .font(.glabCaption2)
                            .foregroundStyle(
                                .white.opacity(0.72)
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityElement(
                        children: .combine
                    )
                }

                ToolbarItemGroup(
                    placement: .topBarTrailing
                ) {
                    if let destination = route.safeWebURL {
                        Link(destination: destination) {
                            GitLabLogoMark()
                        }
                        .accessibilityLabel(
                            "Open file in GitLab"
                        )
                    }

                    Menu {
                        Button {
                            UIPasteboard.general.string =
                                route.path
                        } label: {
                            Label(
                                "Copy Path",
                                systemImage: "doc.on.doc"
                            )
                        }

                        if
                            case let .loaded(document) =
                                model.state
                        {
                            presentationAction(
                                for: document
                            )

                            Button {
                                UIPasteboard.general.string =
                                    document.source
                            } label: {
                                Label(
                                    "Copy Contents",
                                    systemImage:
                                        "text.page"
                                )
                            }

                            ShareLink(
                                item: document.source,
                                subject: Text(
                                    route.fileName
                                )
                            ) {
                                Label(
                                    "Share Contents",
                                    systemImage:
                                        "square.and.arrow.up"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("File actions")
                }
            }
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
            .onChange(
                of: model.authenticationFailure
            ) { _, error in
                guard let error else {
                    return
                }
                Task {
                    await appSession
                        .handleAuthenticationFailure(
                            error,
                            for: accountID
                        )
                }
            }
            .accessibilityIdentifier(
                "repository.file"
            )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading file…")
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(Color.glabCanvas)
        case let .loaded(document):
            if
                presentation == .rendered,
                GitLabRepositoryFilePresentation
                    .supportsRenderedMarkdown(
                        document
                    )
            {
                renderedMarkdown(document)
            } else {
                rawSource(document)
            }
        case let .failed(error):
            ContentUnavailableView {
                Label(
                    "File unavailable",
                    systemImage:
                        error == .binary
                        ? "doc.richtext"
                        : "exclamationmark.triangle"
                )
            } description: {
                Text(error.description)
            } actions: {
                if error.canRetry {
                    Button("Try Again") {
                        Task {
                            await model.retry()
                            await handleAuthenticationFailure()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .background(Color.glabCanvas)
        }
    }

    private func renderedMarkdown(
        _ document: GitLabSourceDocument
    ) -> some View {
        ScrollView {
            GitLabRepositoryMarkdownContentView(
                route: route,
                document: document,
                accountID: accountID,
                renderer: markdownRenderer
            )
            .padding(16)
        }
        .background(Color.glabCanvas)
        .accessibilityIdentifier(
            "repository.markdown"
        )
    }

    private func rawSource(
        _ document: GitLabSourceDocument
    ) -> some View {
        GitLabSourceCollectionView(
            document: document
        )
        .background(Color.glabSurface)
        .safeAreaInset(
            edge: .bottom,
            spacing: 0
        ) {
            if document.truncatedLineCount > 0 {
                Text(
                    "\(document.truncatedLineCount.formatted()) long lines truncated for display"
                )
                .font(.glabCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    Color.glabRaisedSurface
                )
            }
        }
    }

    @ViewBuilder
    private func presentationAction(
        for document: GitLabSourceDocument
    ) -> some View {
        if
            GitLabRepositoryFilePresentation
                .supportsRenderedMarkdown(document)
        {
            Button {
                presentation =
                    presentation == .rendered
                    ? .raw
                    : .rendered
            } label: {
                Label(
                    presentation == .rendered
                        ? "View Raw"
                        : "View Rendered",
                    systemImage:
                        presentation == .rendered
                        ? "text.page"
                        : "doc.richtext"
                )
            }
            .accessibilityIdentifier(
                "repository.file.presentationToggle"
            )
        } else if document.language == .markdown {
            Label(
                "Rendered view unavailable for files over 1 MB",
                systemImage: "info.circle"
            )
        }
    }

    private var fileSubtitle: String {
        route.parentPath.isEmpty
            ? route.ref
            : route.parentPath
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error = model.authenticationFailure
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

struct GitLabRepositoryMarkdownContentView: View {
    let route: GitLabRepositoryFileRoute
    let document: GitLabSourceDocument
    let accountID: GitLabAccountID
    let renderer: any GitLabMarkdownRendering

    var body: some View {
        GitLabMarkdownContentView(
            request: GitLabMarkdownRequest(
                accountID: accountID,
                resource: route.markdownResourceID,
                source: document.source,
                webURL: route.safeWebURL
            ),
            revision: .distantPast,
            kind: .repositoryFile,
            renderer: renderer
        )
    }
}
