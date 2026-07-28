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
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.gitLabDiffRenderer)
    private var diffRenderer
    @State private var model:
        GitLabMergeRequestDiffsModel

    init(
        route: GitLabMergeRequestRoute,
        headSHA: String,
        changesURL: URL?,
        loader: any GitLabMergeRequestDiffLoading,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.route = route
        self.headSHA = headSHA
        self.changesURL = changesURL
        self.accountID = accountID
        self.appSession = appSession
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
                Color(uiColor: .systemGroupedBackground)
            )
            .navigationTitle("Changed Files")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.searchText,
                placement:
                    .navigationBarDrawer(
                        displayMode: .always
                    ),
                prompt: "Search loaded file paths"
            )
            .refreshable {
                await refresh()
            }
            .task {
                await load()
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
        List {
            if model.isRefreshing {
                Label(
                    "Updating changed files…",
                    systemImage: "arrow.clockwise"
                )
                .font(.footnote)
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
                                accountID: accountID,
                                renderer: diffRenderer
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
                        .font(.footnote)
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
        await model.loadIfNeeded()
        await handleAuthenticationFailure()
    }

    private func refresh() async {
        await model.refresh()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure() async {
        guard
            let error = model.authenticationFailure
        else {
            return
        }
        await appSession.handleAuthenticationFailure(
            error,
            for: accountID
        )
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
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                if file.kind == .renamed {
                    Text("From \(file.oldPath)")
                        .font(.caption)
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
            .font(.caption2.weight(.semibold))
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
    let accountID: GitLabAccountID

    @State private var selectedFileID:
        GitLabMergeRequestDiffFileID
    @State private var model: GitLabDiffModel
    @State private var selectedHunkJump:
        GitLabDiffHunkJump?

    init(
        filesModel: GitLabMergeRequestDiffsModel,
        initialFileID:
            GitLabMergeRequestDiffFileID,
        route: GitLabMergeRequestRoute,
        headSHA: String,
        changesURL: URL?,
        accountID: GitLabAccountID,
        renderer: any GitLabDiffRendering
    ) {
        self.filesModel = filesModel
        self.route = route
        self.headSHA = headSHA
        self.changesURL = changesURL
        self.accountID = accountID
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
            Color(uiColor: .systemBackground)
        )
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            fileNavigationToolbar
        }
        .task(id: selectedFileID) {
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
            } else {
                GitLabDiffDocumentView(
                    document: document,
                    selectedHunkJump:
                        selectedHunkJump
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
                .font(.subheadline.weight(.semibold))
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            if file.kind == .renamed {
                Text("Renamed from \(file.oldPath)")
                    .font(.caption)
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

    private var selectedFileIndex: Int? {
        filesModel.files.firstIndex {
            $0.id == selectedFileID
        }
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

private struct GitLabDiffHunkJump: Equatable {
    let id = UUID()
    let ordinal: Int
}

private struct GitLabDiffDocumentView: View {
    let document: GitLabParsedDiffDocument
    let selectedHunkJump: GitLabDiffHunkJump?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(
                        document.items.indices,
                        id: \.self
                    ) { index in
                        GitLabDiffRenderItemView(
                            item: document.items[index]
                        )
                        .id(itemID(index))
                    }
                }
                .frame(
                    minWidth: minimumContentWidth,
                    alignment: .leading
                )
                .textSelection(.enabled)
            }
            .onChange(
                of: selectedHunkJump
            ) { _, jump in
                guard let jump else {
                    return
                }
                withAnimation {
                    proxy.scrollTo(
                        "hunk.\(jump.ordinal)",
                        anchor: .top
                    )
                }
            }
        }
        .accessibilityIdentifier(
            "mergeRequestDiffs.document"
        )
    }

    private var minimumContentWidth: CGFloat {
        let estimated =
            CGFloat(
                document.maximumRenderedLineLength
            ) * 8 + 116
        return min(
            max(estimated, 520),
            8_000
        )
    }

    private func itemID(_ index: Int) -> String {
        guard
            case let .hunkHeader(ordinal, _) =
                document.items[index]
        else {
            return "diff.item.\(index)"
        }
        return "hunk.\(ordinal)"
    }
}

private struct GitLabDiffRenderItemView: View {
    let item: GitLabDiffRenderItem

    var body: some View {
        switch item {
        case let .hunkHeader(_, text):
            specialRow(
                text,
                color: .blue,
                accessibilityLabel:
                    "Diff hunk, \(text)"
            )
        case let .context(line):
            codeRow(
                line,
                prefix: " ",
                color: .clear
            )
        case let .addition(line):
            codeRow(
                line,
                prefix: "+",
                color: .green
            )
        case let .deletion(line):
            codeRow(
                line,
                prefix: "-",
                color: .red
            )
        case let .noNewlineMarker(text):
            specialRow(
                text,
                color: .secondary,
                accessibilityLabel: text
            )
        case let .fileMetadata(text):
            specialRow(
                text,
                color: .secondary,
                accessibilityLabel:
                    "File metadata, \(text)"
            )
        }
    }

    private func codeRow(
        _ line: GitLabDiffLine,
        prefix: String,
        color: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)

            Text(prefix + line.text)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .fixedSize(
                    horizontal: true,
                    vertical: false
                )
                .padding(.leading, 8)
                .padding(.trailing, 16)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityLabel(line)
        )
    }

    private func lineNumber(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .frame(width: 50, alignment: .trailing)
            .padding(.trailing, 7)
            .background(
                Color.secondary.opacity(0.05)
            )
    }

    private func specialRow(
        _ text: String,
        color: Color,
        accessibilityLabel: String
    ) -> some View {
        Text(text)
            .font(
                .system(
                    .caption,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                color
            )
            .fixedSize(
                horizontal: true,
                vertical: false
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .accessibilityLabel(accessibilityLabel)
    }

    private func accessibilityLabel(
        _ line: GitLabDiffLine
    ) -> String {
        switch line.kind {
        case .context:
            return "Context, old line "
                + "\(line.oldLineNumber ?? 0), new line "
                + "\(line.newLineNumber ?? 0), \(line.text)"
        case .addition:
            return "Added line "
                + "\(line.newLineNumber ?? 0), \(line.text)"
        case .deletion:
            return "Deleted line "
                + "\(line.oldLineNumber ?? 0), \(line.text)"
        }
    }
}
