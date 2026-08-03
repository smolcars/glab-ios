import SwiftUI

private struct
    GitLabJobTraceLoaderEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabJobTraceLoading =
            UnavailableGitLabJobTraceLoader()
}

extension EnvironmentValues {
    var gitLabJobTraceLoader:
        any GitLabJobTraceLoading
    {
        get {
            self[
                GitLabJobTraceLoaderEnvironmentKey
                    .self
            ]
        }
        set {
            self[
                GitLabJobTraceLoaderEnvironmentKey
                    .self
            ] = newValue
        }
    }
}

nonisolated struct
    UnavailableGitLabJobTraceLoader:
    GitLabJobTraceLoading
{
    func cachedDescriptor(
        for key: GitLabJobTraceKey
    ) async -> GitLabJobTraceDescriptor? {
        nil
    }

    func loadTrace(
        for key: GitLabJobTraceKey
    ) async throws(GitLabJobTraceLoadError)
        -> GitLabJobTraceDescriptor
    {
        throw .storage
    }
}

nonisolated struct GitLabJobTraceJump:
    Equatable,
    Sendable
{
    let id: UUID
    let lineIndex: Int

    init(lineIndex: Int) {
        id = UUID()
        self.lineIndex = lineIndex
    }
}

nonisolated struct
    GitLabJobTraceStatusPresentation:
    Equatable,
    Sendable
{
    let text: String?
    let isWarning: Bool

    init(
        refreshError:
            GitLabJobTraceLoadError?,
        searchError:
            GitLabJobTraceDocumentError?,
        isSearching: Bool,
        searchText: String,
        searchResult:
            GitLabJobTraceSearchResult,
        longLineCount: Int?
    ) {
        if let refreshError {
            text =
                refreshError == .noTrace
                ? "Cached log kept · GitLab no longer returned a log"
                : "Cached log kept · \(refreshError.description)"
            isWarning = true
            return
        }
        if let searchError {
            text =
                "Search unavailable · \(searchError.description)"
            isWarning = true
            return
        }
        if isSearching {
            text = "Searching…"
            isWarning = false
            return
        }
        if
            !searchText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
        {
            let suffix =
                searchResult
                .hasAdditionalMatches
                ? "+"
                : ""
            text =
                "\(searchResult.lineIndexes.count.formatted())\(suffix) matches"
            isWarning = false
            return
        }
        if
            let longLineCount,
            longLineCount > 0
        {
            text =
                "\(longLineCount.formatted()) long lines truncated for display"
            isWarning = false
            return
        }
        text = nil
        isWarning = false
    }
}

struct GitLabJobTraceView: View {
    let accountID: GitLabAccountID
    let appSession: AppSession

    @State private var model:
        GitLabJobTraceModel
    @State private var searchText = ""
    @State private var isSearchPresented =
        false
    @State private var jump:
        GitLabJobTraceJump?
    @FocusState private var
        isSearchFieldFocused: Bool

    init(
        accountID: GitLabAccountID,
        context: GitLabJobTraceContext,
        loader:
            any GitLabJobTraceLoading,
        appSession: AppSession,
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabJobTraceModel(
                    accountID: accountID,
                    context: context,
                    loader: loader,
                    isAccountCurrent:
                        isAccountCurrent
                )
        )
    }

    var body: some View {
        content
            .navigationTitle(
                model.context.jobName
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                if
                    let destination =
                        model.context.webURL
                {
                    ToolbarItem(
                        placement:
                            .topBarTrailing
                    ) {
                        Link(
                            destination:
                                destination
                        ) {
                            GitLabLogoMark()
                        }
                        .accessibilityLabel(
                            "Open job in GitLab"
                        )
                        .accessibilityIdentifier(
                            "jobTrace.openInGitLab"
                        )
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
            .onChange(
                of:
                    model
                    .authenticationFailure
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
            .onDisappear {
                Task {
                    await model.cancel()
                }
            }
            .safeAreaInset(
                edge: .bottom,
                spacing: 0
            ) {
                if model.document != nil {
                    bottomBar
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading job log…")
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .accessibilityIdentifier(
                    "jobTrace.loading"
                )
        case .noTrace:
            unavailableContent(
                title: "No job log",
                systemImage:
                    "doc.text.magnifyingglass",
                description:
                    "GitLab did not return a log for this job."
            )
        case .tooLarge:
            unavailableContent(
                title: "Job log too large",
                systemImage:
                    "doc.badge.ellipsis",
                description:
                    "This log exceeds the safe local size limit."
            )
        case let .failed(error):
            ContentUnavailableView {
                Label(
                    "Couldn’t load job log",
                    systemImage:
                        "exclamationmark.triangle"
                )
            } description: {
                Text(error.description)
            } actions: {
                Button("Try Again") {
                    Task {
                        await model.retry()
                        await handleAuthenticationFailure()
                    }
                }
                .buttonStyle(.glass)
            }
            .accessibilityIdentifier(
                "jobTrace.loadError"
            )
        case .empty:
            unavailableContent(
                title: "Empty job log",
                systemImage: "doc",
                description:
                    "GitLab returned an empty log for this job."
            )
        case let .ready(
            descriptor,
            _
        ):
            if let document = model.document {
                VStack(spacing: 0) {
                    summaryBar(
                        descriptor:
                            descriptor
                    )
                    Divider()
                    GitLabJobTraceLineSurface(
                        document: document,
                        selectedLineIndex:
                            selectedLineIndex,
                        jump: jump
                    )
                    .id(
                        descriptor
                            .rawContentDigest
                    )
                }
            }
        }
    }

    private func unavailableContent(
        title: String,
        systemImage: String,
        description: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description:
                Text(description)
        )
        .accessibilityIdentifier(
            "jobTrace.unavailable"
        )
    }

    private func summaryBar(
        descriptor:
            GitLabJobTraceDescriptor
    ) -> some View {
        HStack(spacing: 7) {
            GitLabCIStatusIcon(
                status:
                    model.context.status
            )

            Text(
                model.context.status.jobTitle
            )
            .foregroundStyle(
                model.context.status.tint
            )

            Text("·")
                .foregroundStyle(.tertiary)

            Text(
                "\(descriptor.lineCount.formatted()) lines"
            )
            .monospacedDigit()

            if model.source == .cache {
                Text("·")
                    .foregroundStyle(
                        .tertiary
                    )
                Text(
                    "Cached \(GitLabRelativeTimeFormatter.string(from: descriptor.storedAt))"
                )
            }

            Spacer(minLength: 4)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(
                        "Refreshing job log"
                    )
            }
        }
        .font(.glabCaption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityIdentifier(
            "jobTrace.summary"
        )
    }

    private var bottomBar: some View {
        let status = statusPresentation

        return VStack(
            alignment: .trailing,
            spacing: 4
        ) {
            if let text = status.text {
                Text(text)
                    .font(.glabCaption2)
                    .foregroundStyle(
                        status.isWarning
                        ? Color.orange
                        : Color.secondary
                    )
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        .regularMaterial,
                        in: .capsule
                    )
                    .accessibilityIdentifier(
                        "jobTrace.status"
                    )
            }

            if isSearchPresented {
                bottomSearchField
            }

            controlGroup
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .frame(
            maxWidth: .infinity,
            alignment: .trailing
        )
    }

    @ViewBuilder
    private var controlGroup: some View {
        let controls = HStack(spacing: 0) {
            controlButton(
                systemImage:
                    isSearchPresented
                    ? "xmark"
                    : "magnifyingglass",
                label:
                    isSearchPresented
                    ? "Close job log search"
                    : "Search job log",
                identifier:
                    "jobTrace.search"
            ) {
                await toggleSearch()
            }

            if
                !model.searchResult
                .lineIndexes.isEmpty
            {
                controlButton(
                    systemImage:
                        "chevron.up",
                    label:
                        "Previous search match",
                    identifier:
                        "jobTrace.previousMatch"
                ) {
                    await jumpToPreviousMatch()
                }
                controlButton(
                    systemImage:
                        "chevron.down",
                    label: "Next search match",
                    identifier:
                        "jobTrace.nextMatch"
                ) {
                    await jumpToNextMatch()
                }
            }

            if
                let lineIndex =
                    model.descriptor?
                    .firstLikelyFailure?
                    .lineIndex
            {
                controlButton(
                    systemImage:
                        "exclamationmark.triangle",
                    label:
                        "First likely failure",
                    identifier:
                        "jobTrace.firstFailure"
                ) {
                    jump = GitLabJobTraceJump(
                        lineIndex: lineIndex
                    )
                }
            }

            if
                let lastLineIndex =
                    model.descriptor
                    .map({
                        max(
                            0,
                            $0.lineCount - 1
                        )
                    })
            {
                controlButton(
                    systemImage:
                        "arrow.down.to.line",
                    label:
                        "Scroll to end",
                    identifier:
                        "jobTrace.scrollToEnd"
                ) {
                    jump = GitLabJobTraceJump(
                        lineIndex:
                            lastLineIndex
                    )
                }
            }

            if
                !model.context
                .status.isTerminal
            {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(
                            width: 44,
                            height: 44
                        )
                        .accessibilityLabel(
                            "Refreshing job log"
                        )
                } else {
                    controlButton(
                        systemImage:
                            "arrow.clockwise",
                        label:
                            "Refresh job log",
                        identifier:
                            "jobTrace.refresh"
                    ) {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                    .disabled(!model.canRefresh)
                }
            }
        }
        .padding(.horizontal, 4)

        if #available(iOS 26.0, *) {
            controls
                .glassEffect(
                    .regular
                    .interactive(),
                    in: .capsule
                )
        } else {
            controls
                .background(
                    .ultraThinMaterial,
                    in: .capsule
                )
        }
    }

    @ViewBuilder
    private var bottomSearchField:
        some View
    {
        let field = HStack(spacing: 8) {
            Image(
                systemName: "magnifyingglass"
            )
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            TextField(
                "Search job log",
                text: $searchText
            )
            .textInputAutocapitalization(
                .never
            )
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused(
                $isSearchFieldFocused
            )
            .accessibilityIdentifier(
                "jobTrace.searchField"
            )

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFieldFocused =
                        true
                } label: {
                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Clear job log search"
                )
                .accessibilityIdentifier(
                    "jobTrace.clearSearch"
                )
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(
            maxWidth: 420,
            minHeight: 44
        )

        if #available(iOS 26.0, *) {
            field
                .glassEffect(
                    .regular.interactive(),
                    in: .capsule
                )
        } else {
            field
                .background(
                    .ultraThinMaterial,
                    in: .capsule
                )
        }
    }

    private func controlButton(
        systemImage: String,
        label: String,
        identifier: String,
        action:
            @escaping @MainActor () async
            -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(
                systemName: systemImage
            )
            .font(
                .glabBody.weight(.semibold)
            )
            .frame(
                width: 44,
                height: 44
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(
            identifier
        )
    }

    private var selectedLineIndex: Int? {
        guard
            let position =
                model.searchResult
                .selectedMatchPosition,
            model.searchResult
                .lineIndexes.indices
                .contains(position)
        else {
            return nil
        }
        return model.searchResult
            .lineIndexes[position]
    }

    private var statusPresentation:
        GitLabJobTraceStatusPresentation
    {
        GitLabJobTraceStatusPresentation(
            refreshError:
                model.refreshError,
            searchError:
                model.searchError,
            isSearching:
                model.isSearching,
            searchText: searchText,
            searchResult:
                model.searchResult,
            longLineCount:
                model.descriptor?
                .longLineCount
        )
    }

    private func updateSearch() async {
        if !searchText.isEmpty {
            do {
                try await Task.sleep(
                    for:
                        .milliseconds(250)
                )
            } catch {
                return
            }
        }
        await model.search(searchText)
        guard !Task.isCancelled else {
            return
        }
        if
            !searchText.isEmpty,
            let lineIndex =
                await model
                .selectNextMatch()
        {
            jump = GitLabJobTraceJump(
                lineIndex: lineIndex
            )
        }
    }

    private func toggleSearch() async {
        if isSearchPresented {
            isSearchFieldFocused = false
            searchText = ""
            isSearchPresented = false
            return
        }

        isSearchPresented = true
        await Task.yield()
        guard !Task.isCancelled else {
            return
        }
        isSearchFieldFocused = true
    }

    private func jumpToNextMatch() async {
        guard
            let lineIndex =
                await model
                .selectNextMatch()
        else {
            return
        }
        jump = GitLabJobTraceJump(
            lineIndex: lineIndex
        )
    }

    private func jumpToPreviousMatch() async {
        guard
            let lineIndex =
                await model
                .selectPreviousMatch()
        else {
            return
        }
        jump = GitLabJobTraceJump(
            lineIndex: lineIndex
        )
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

struct GitLabJobTraceLineSurface: View {
    let document:
        GitLabJobTraceDocument
    let selectedLineIndex: Int?
    let jump: GitLabJobTraceJump?

    @ScaledMetric(relativeTo: .caption)
    private var rowHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption)
    private var glyphWidth: CGFloat = 7.6

    init(
        document:
            GitLabJobTraceDocument,
        selectedLineIndex: Int?,
        jump: GitLabJobTraceJump?
    ) {
        self.document = document
        self.selectedLineIndex =
            selectedLineIndex
        self.jump = jump
    }

    var body: some View {
        GitLabJobTraceCollectionView(
            document: document,
            selectedLineIndex:
                selectedLineIndex,
            jump: jump,
            rowHeight: rowHeight,
            glyphWidth: glyphWidth
        )
        .accessibilityIdentifier(
            "jobTrace.lines"
        )
    }
}
