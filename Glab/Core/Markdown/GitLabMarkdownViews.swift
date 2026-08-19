import AVKit
import SwiftUI
import UIKit

private struct GitLabMarkdownRendererEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabMarkdownRendering =
            GitLabMarkdownRenderer(
                rendererVersion: 3
            )
}

extension EnvironmentValues {
    var gitLabMarkdownRenderer:
        any GitLabMarkdownRendering
    {
        get {
            self[
                GitLabMarkdownRendererEnvironmentKey.self
            ]
        }
        set {
            self[
                GitLabMarkdownRendererEnvironmentKey.self
            ] = newValue
        }
    }
}

private struct
    GitLabMarkdownMediaLoaderEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabMarkdownMediaLoading =
            UnavailableGitLabMarkdownMediaLoader()
}

extension EnvironmentValues {
    var gitLabMarkdownMediaLoader:
        any GitLabMarkdownMediaLoading
    {
        get {
            self[
                GitLabMarkdownMediaLoaderEnvironmentKey
                    .self
            ]
        }
        set {
            self[
                GitLabMarkdownMediaLoaderEnvironmentKey
                    .self
            ] = newValue
        }
    }
}

private struct
    GitLabReadOnlyMarkdownRendererEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabMarkdownRendering =
            GitLabMarkdownRenderer(
                rendererVersion: 3,
                parser:
                    GitLabReadOnlyMarkdownParser.parse
            )
}

extension EnvironmentValues {
    var gitLabReadOnlyMarkdownRenderer:
        any GitLabMarkdownRendering
    {
        get {
            self[
                GitLabReadOnlyMarkdownRendererEnvironmentKey
                    .self
            ]
        }
        set {
            self[
                GitLabReadOnlyMarkdownRendererEnvironmentKey
                    .self
            ] = newValue
        }
    }
}

private struct
    GitLabMarkdownImageLoaderEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabMarkdownImageLoading =
            UnavailableGitLabMarkdownImageLoader()
}

extension EnvironmentValues {
    var gitLabMarkdownImageLoader:
        any GitLabMarkdownImageLoading
    {
        get {
            self[
                GitLabMarkdownImageLoaderEnvironmentKey
                    .self
            ]
        }
        set {
            self[
                GitLabMarkdownImageLoaderEnvironmentKey
                    .self
            ] = newValue
        }
    }
}

struct GitLabMarkdownLinkHandler: Sendable {
    private let action:
        @MainActor @Sendable (URL) -> Bool

    init(
        _ action:
            @escaping @MainActor @Sendable
            (URL) -> Bool
    ) {
        self.action = action
    }

    @MainActor
    func handle(_ url: URL) -> Bool {
        action(url)
    }

    static let system = Self { _ in
        false
    }
}

private struct
    GitLabMarkdownLinkHandlerEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue =
        GitLabMarkdownLinkHandler.system
}

extension EnvironmentValues {
    var gitLabMarkdownLinkHandler:
        GitLabMarkdownLinkHandler
    {
        get {
            self[
                GitLabMarkdownLinkHandlerEnvironmentKey
                    .self
            ]
        }
        set {
            self[
                GitLabMarkdownLinkHandlerEnvironmentKey
                    .self
            ] = newValue
        }
    }
}

nonisolated enum GitLabMarkdownContentKind:
    Sendable
{
    case description
    case comment
    case repositoryFile

    var formattingMessage: String {
        switch self {
        case .description:
            "Formatting description…"
        case .comment:
            "Formatting comment…"
        case .repositoryFile:
            "Formatting Markdown…"
        }
    }

    var failureTitle: String {
        switch self {
        case .description:
            "Couldn’t format this description"
        case .comment:
            "Couldn’t format this comment"
        case .repositoryFile:
            "Couldn’t format this file"
        }
    }

    var unformattedAccessibilityLabel: String {
        switch self {
        case .description:
            "Unformatted description"
        case .comment:
            "Unformatted comment"
        case .repositoryFile:
            "Unformatted Markdown file"
        }
    }
}

@MainActor
struct GitLabMarkdownTaskInteraction {
    let model:
        GitLabDescriptionTaskToggleModel
    let snapshot:
        GitLabResourceEditSnapshot
    var isExternallyDisabled = false
    let openEditor: () -> Void
}

struct GitLabMarkdownContentView: View {
    private struct LoadIdentity: Hashable {
        let request: GitLabMarkdownRequest
        let revision: Date
    }

    let request: GitLabMarkdownRequest
    let revision: Date
    let kind: GitLabMarkdownContentKind
    let taskInteraction:
        GitLabMarkdownTaskInteraction?

    @Environment(\.gitLabMarkdownLinkHandler)
    private var linkHandler
    @State private var model: GitLabMarkdownModel

    init(
        request: GitLabMarkdownRequest,
        revision: Date,
        kind: GitLabMarkdownContentKind,
        renderer: any GitLabMarkdownRendering,
        taskInteraction:
            GitLabMarkdownTaskInteraction? = nil
    ) {
        self.request = request
        self.revision = revision
        self.kind = kind
        self.taskInteraction =
            taskInteraction
        _model = State(
            initialValue:
                GitLabMarkdownModel(
                    renderer: renderer
                )
        )
    }

    var body: some View {
        content
            .environment(
                \.openURL,
                OpenURLAction { url in
                    linkHandler.handle(url)
                        ? .handled
                        : .systemAction
                }
            )
            .task(
                id: LoadIdentity(
                    request: request,
                    revision: revision
                )
            ) {
                await model.load(request)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(kind.formattingMessage)
                    .foregroundStyle(.secondary)
            }
            .font(.glabCallout)
            .accessibilityElement(children: .combine)
        case let .loaded(document):
            if let failureMessage =
                model.failureMessage
            {
                GitLabMarkdownFailureNotice(
                    message: failureMessage,
                    kind: kind
                ) {
                    Task {
                        await model.load(request)
                    }
                }
            }

            if
                let taskInteraction,
                document
                    .hasMappedMutableTask
            {
                GitLabMarkdownTaskStatusView(
                    interaction:
                        taskInteraction
                )
            }

            GitLabMarkdownDocumentView(
                document: document,
                taskInteraction:
                    taskInteraction
            )
        case let .failed(message):
            GitLabMarkdownFailureNotice(
                message: message,
                kind: kind
            ) {
                Task {
                    await model.load(request)
                }
            }

            Text(request.source)
                .font(.glabBody)
                .textSelection(.enabled)
                .accessibilityLabel(
                    kind.unformattedAccessibilityLabel
                        + ", "
                        + request.source
                )
        }
    }
}

private struct GitLabMarkdownFailureNotice: View {
    let message: String
    let kind: GitLabMarkdownContentKind
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                kind.failureTitle,
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .font(.glabCallout.weight(.semibold))
            .foregroundStyle(.orange)

            Text(message)
                .font(.glabCaption)
                .foregroundStyle(.secondary)

            Button("Try Again", action: retry)
                .font(.glabCallout.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .orange.opacity(0.08),
            in: .rect(cornerRadius: 12)
        )
    }
}

struct GitLabMarkdownDocumentView: View {
    let document: GitLabMarkdownDocument
    let taskInteraction:
        GitLabMarkdownTaskInteraction?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(
                Array(document.blocks.enumerated()),
                id: \.offset
            ) { _, block in
                GitLabMarkdownBlockView(
                    block: block,
                    taskInteraction:
                        taskInteraction
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
}

private struct GitLabMarkdownBlockView: View {
    let block: GitLabMarkdownBlock
    let taskInteraction:
        GitLabMarkdownTaskInteraction?

    var body: some View {
        switch block {
        case let .heading(heading):
            Text(heading.content.attributedString)
                .font(font(for: heading.level))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(
                    heading.accessibilityLabel
                )
                .textSelection(.enabled)
        case let .paragraph(paragraph):
            Text(paragraph.attributedString)
                .font(.glabBody)
                .textSelection(.enabled)
        case let .list(list):
            GitLabMarkdownListView(
                list: list,
                taskInteraction:
                    taskInteraction
            )
        case let .quote(quote):
            GitLabMarkdownQuoteView(
                quote: quote,
                taskInteraction:
                    taskInteraction
            )
        case let .code(code):
            GitLabMarkdownCodeView(code: code)
        case let .table(table):
            GitLabMarkdownTableView(table: table)
        case let .image(image):
            GitLabMarkdownMediaView(
                image: image
            )
        case let .imageGroup(group):
            GitLabMarkdownImageGroupView(
                group: group
            )
        case let .richText(richText):
            GitLabMarkdownRichTextView(
                richText: richText
            )
        case .thematicBreak:
            Divider()
                .accessibilityLabel("Section break")
        case let .unsupported(unsupported):
            GitLabMarkdownUnsupportedView(
                unsupported: unsupported
            )
        }
    }

    private func font(
        for level: Int
    ) -> Font {
        switch level {
        case 1:
            .glabTitle2.bold()
        case 2:
            .glabTitle3.bold()
        case 3:
            .glabHeadline
        case 4:
            .glabSubheadline.weight(.semibold)
        case 5:
            .glabCallout.weight(.semibold)
        default:
            .glabCaption.weight(.semibold)
        }
    }
}

private struct GitLabMarkdownListView: View {
    let list: GitLabMarkdownList
    let taskInteraction:
        GitLabMarkdownTaskInteraction?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(
                Array(list.items.enumerated()),
                id: \.offset
            ) { _, item in
                HStack(
                    alignment: .top,
                    spacing: 8
                ) {
                    marker(for: item)
                        .frame(
                            width: 24,
                            alignment: .trailing
                        )
                        .padding(.top, 2)

                    VStack(
                        alignment: .leading,
                        spacing: 9
                    ) {
                        ForEach(
                            Array(
                                item.blocks.enumerated()
                            ),
                            id: \.offset
                        ) { _, block in
                            GitLabMarkdownBlockView(
                                block: block,
                                taskInteraction:
                                    taskInteraction
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func marker(
        for item: GitLabMarkdownListItem
    ) -> some View {
        if
            let task = item.indexedTask,
            task.state != .inapplicable,
            let taskInteraction
        {
            GitLabMarkdownTaskButton(
                task: task,
                itemText:
                    item.taskControlText,
                interaction:
                    taskInteraction
            )
        } else if
            let taskState = item.taskState
        {
            Image(
                systemName:
                    systemImage(for: taskState)
            )
            .font(.glabBody.weight(.semibold))
            .foregroundStyle(
                taskState == .incomplete
                    ? Color.secondary
                    : Color.glabAccent
            )
            .accessibilityLabel(
                taskState.accessibilityTitle
            )
        } else {
            Text(
                list.kind == .ordered
                    ? "\(item.ordinal)."
                    : "•"
            )
            .font(.glabBody.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func systemImage(
        for state: GitLabMarkdownTaskState
    ) -> String {
        switch state {
        case .complete:
            "checkmark.square.fill"
        case .incomplete:
            "square"
        case .inapplicable:
            "minus.square.fill"
        }
    }
}

private struct
    GitLabMarkdownTaskButton:
    View
{
    let task: GitLabMarkdownIndexedTask
    let itemText: String
    let interaction:
        GitLabMarkdownTaskInteraction

    private var displayedState:
        GitLabMarkdownTaskState
    {
        interaction.model.displayedState(
            for: task
        )
    }

    private var isActive: Bool {
        interaction.model
            .activeTaskSourceID
            == task.sourceID
    }

    private var isEnabled: Bool {
        interaction.model.apiAccess.canWrite
            && interaction.model.phase == .idle
            && !interaction
                .isExternallyDisabled
    }

    var body: some View {
        Button {
            Task {
                await interaction.model.toggle(
                    task,
                    in: interaction.snapshot
                )
            }
        } label: {
            Group {
                if
                    isActive,
                    interaction.model.isBusy
                {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(
                        systemName:
                            systemImage(
                                for:
                                    displayedState
                            )
                    )
                    .font(
                        .glabBody.weight(.semibold)
                    )
                    .foregroundStyle(
                        displayedState
                            == .incomplete
                            ? Color.secondary
                            : Color.glabAccent
                    )
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -10)
        .disabled(!isEnabled)
        .accessibilityLabel(
            itemText.isEmpty
                ? "Task checkbox"
                : "Task checkbox for \(itemText)"
        )
        .accessibilityValue(
            accessibilityValue
        )
        .accessibilityHint(
            accessibilityHint
        )
    }

    private var accessibilityValue: String {
        switch displayedState {
        case .complete:
            "Checked"
        case .incomplete:
            "Unchecked"
        case .inapplicable:
            "Inapplicable"
        }
    }

    private var accessibilityHint: String {
        if !interaction.model.apiAccess.canWrite {
            return "This account has read-only API access."
        }
        if interaction.model.phase != .idle {
            return "Another task update must finish first."
        }
        return displayedState == .complete
            ? "Marks this task incomplete."
            : "Marks this task complete."
    }

    private func systemImage(
        for state: GitLabMarkdownTaskState
    ) -> String {
        switch state {
        case .complete:
            "checkmark.square.fill"
        case .incomplete:
            "square"
        case .inapplicable:
            "minus.square.fill"
        }
    }
}

private struct
    GitLabMarkdownTaskStatusView:
    View
{
    private enum Action {
        case checkGitLab
        case retry
        case openEditor
    }

    private struct Presentation {
        let message: String
        let systemImage: String
        let action: Action?
    }

    let interaction:
        GitLabMarkdownTaskInteraction

    @ViewBuilder
    var body: some View {
        if let presentation {
            HStack(
                alignment: .center,
                spacing: 10
            ) {
                if interaction.model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(
                        systemName:
                            presentation
                                .systemImage
                    )
                    .foregroundStyle(.orange)
                }

                Text(presentation.message)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                if let action =
                    presentation.action
                {
                    Button(
                        actionTitle(action)
                    ) {
                        perform(action)
                    }
                    .font(
                        .glabCaption.weight(
                            .semibold
                        )
                    )
                }
            }
            .padding(10)
            .background(
                Color.orange.opacity(0.08),
                in: .rect(cornerRadius: 12)
            )
            .accessibilityIdentifier(
                "markdown.taskStatus"
            )
        }
    }

    private var presentation:
        Presentation?
    {
        switch interaction.model.phase {
        case .rewriting:
            return Presentation(
                message:
                    "Checking this task…",
                systemImage: "checkmark.square",
                action: nil
            )
        case .restoringDraft:
            return Presentation(
                message:
                    "Checking saved edits…",
                systemImage: "checkmark.square",
                action: nil
            )
        case .saving:
            return Presentation(
                message:
                    "Updating this task…",
                systemImage: "checkmark.square",
                action: nil
            )
        case .checkingGitLab:
            return Presentation(
                message:
                    "Checking GitLab…",
                systemImage: "arrow.triangle.2.circlepath",
                action: nil
            )
        case .deliveryUnknown:
            if
                case .editor(.conflict) =
                    interaction.model.failure
            {
                return Presentation(
                    message:
                        "The description changed on GitLab. Review the saved task update before continuing.",
                    systemImage:
                        "exclamationmark.triangle.fill",
                    action: .openEditor
                )
            }
            return Presentation(
                message:
                    "GitLab may have received this task update. Check before retrying.",
                systemImage:
                    "questionmark.circle.fill",
                action: .checkGitLab
            )
        case .retryAvailable:
            return Presentation(
                message:
                    "GitLab did not apply this task update.",
                systemImage:
                    "arrow.clockwise.circle.fill",
                action: .retry
            )
        case .idle:
            break
        }

        guard
            let failure =
                interaction.model.failure
        else {
            if
                !interaction.model
                    .apiAccess.canWrite
            {
                return Presentation(
                    message:
                        "Task lists are read-only for this account.",
                    systemImage: "lock.fill",
                    action: nil
                )
            }
            return nil
        }

        switch failure {
        case .readOnly:
            return Presentation(
                message:
                    "Task lists are read-only for this account.",
                systemImage: "lock.fill",
                action: nil
            )
        case .inapplicable:
            return Presentation(
                message:
                    "Inapplicable tasks cannot be changed.",
                systemImage: "minus.square.fill",
                action: nil
            )
        case .staleDescription:
            return Presentation(
                message:
                    "The description changed. It was refreshed without changing the task.",
                systemImage:
                    "arrow.clockwise.circle.fill",
                action: nil
            )
        case .existingDraft:
            return Presentation(
                message:
                    "Finish or discard the saved description edit before changing a task.",
                systemImage: "doc.text.fill",
                action: .openEditor
            )
        case .rewrite:
            return Presentation(
                message:
                    "This task could not be matched safely to the current description.",
                systemImage:
                    "exclamationmark.triangle.fill",
                action: nil
            )
        case let .editor(failure):
            return Presentation(
                message:
                    editorMessage(failure),
                systemImage:
                    "exclamationmark.triangle.fill",
                action: nil
            )
        }
    }

    private func editorMessage(
        _ failure:
            GitLabResourceEditorFailure
    ) -> String {
        switch failure {
        case .validation:
            "GitLab could not accept this description."
        case .readOnly:
            "Task lists are read-only for this account."
        case .draftStorage:
            "The task update could not be saved safely on this device."
        case .freshness:
            "The latest description could not be checked."
        case .conflict:
            "The description changed on GitLab."
        case .mutation:
            "GitLab could not update this task."
        case .reconciliation:
            "GitLab could not confirm this task update."
        }
    }

    private func actionTitle(
        _ action: Action
    ) -> String {
        switch action {
        case .checkGitLab:
            "Check"
        case .retry:
            "Try Again"
        case .openEditor:
            "Review"
        }
    }

    private func perform(
        _ action: Action
    ) {
        switch action {
        case .checkGitLab:
            Task {
                await interaction.model
                    .checkGitLab()
            }
        case .retry:
            Task {
                await interaction.model.retry()
            }
        case .openEditor:
            interaction.openEditor()
        }
    }
}

private struct GitLabMarkdownQuoteView: View {
    let quote: GitLabMarkdownQuote
    let taskInteraction:
        GitLabMarkdownTaskInteraction?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.glabAccent.opacity(0.72))
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(
                    Array(quote.blocks.enumerated()),
                    id: \.offset
                ) { _, block in
                    GitLabMarkdownBlockView(
                        block: block,
                        taskInteraction:
                            taskInteraction
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 8)
        .accessibilityLabel(
            "Quote, \(quote.plainText)"
        )
    }
}

private struct GitLabMarkdownCodeView: View {
    let code: GitLabMarkdownCodeBlock

    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.gitLabSyntaxHighlighter)
    private var syntaxHighlighter
    @State private var highlightedCode:
        AttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if
                let language = code.language,
                !language.isEmpty
            {
                Text(language.uppercased())
                    .font(.glabCaption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(
                .horizontal,
                showsIndicators: true
            ) {
                Text(
                    highlightedCode
                        ?? AttributedString(code.text)
                )
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(
                        horizontal: true,
                        vertical: false
                    )
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.1),
            in: .rect(cornerRadius: 12)
        )
        .accessibilityLabel(
            "\(code.accessibilityLabel), \(code.text)"
        )
        .task(id: highlightID) {
            highlightedCode = nil
            guard
                let language = GitLabSyntaxLanguage(
                    markdownFence: code.language
                )
            else {
                return
            }
            let result = await syntaxHighlighter
                .highlight(
                    GitLabSyntaxHighlightRequest(
                        source: code.text,
                        language: language,
                        theme: syntaxTheme
                    )
                )
            guard
                !Task.isCancelled,
                let result
            else {
                return
            }
            highlightedCode = AttributedString(
                result.attributedString
            )
        }
    }

    private var syntaxTheme: GitLabSyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }

    private var highlightID:
        GitLabMarkdownCodeHighlightID
    {
        GitLabMarkdownCodeHighlightID(
            source: code.text,
            language: code.language,
            theme: syntaxTheme
        )
    }
}

private struct GitLabMarkdownCodeHighlightID:
    Equatable,
    Hashable
{
    let source: String
    let language: String?
    let theme: GitLabSyntaxTheme
}

private struct GitLabMarkdownTableView: View {
    let table: GitLabMarkdownTable

    var body: some View {
        ScrollView(
            .horizontal,
            showsIndicators: true
        ) {
            VStack(alignment: .leading, spacing: 0) {
                row(
                    table.header,
                    isHeader: true
                )

                Divider()

                ForEach(
                    Array(table.rows.enumerated()),
                    id: \.offset
                ) { index, cells in
                    row(cells, isHeader: false)
                    if index < table.rows.count - 1 {
                        Divider()
                    }
                }
            }
            .background(
                Color.secondary.opacity(0.06),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color.secondary.opacity(0.18)
                    )
            }
        }
        .accessibilityLabel("Markdown table")
    }

    private func row(
        _ cells: [GitLabMarkdownText],
        isHeader: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(
                Array(cells.enumerated()),
                id: \.offset
            ) { index, cell in
                Text(cell.attributedString)
                    .font(
                        isHeader
                            ? .glabCallout.weight(.semibold)
                            : .glabCallout
                    )
                    .multilineTextAlignment(
                        textAlignment(at: index)
                    )
                    .frame(
                        width: columnWidth(at: index),
                        alignment: frameAlignment(
                            at: index
                        )
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(
                        isHeader
                            ? .isHeader
                            : []
                    )
                    .accessibilityLabel(
                        accessibilityLabel(
                            for: cell,
                            column: index,
                            isHeader: isHeader
                        )
                    )
            }
        }
    }

    private func columnWidth(
        at index: Int
    ) -> CGFloat {
        guard
            table.columnCharacterCounts
                .indices.contains(index)
        else {
            return 100
        }
        return min(
            220,
            max(
                90,
                CGFloat(
                    table.columnCharacterCounts[index]
                ) * 8 + 20
            )
        )
    }

    private func textAlignment(
        at index: Int
    ) -> TextAlignment {
        switch alignment(at: index) {
        case .left:
            .leading
        case .center:
            .center
        case .right:
            .trailing
        }
    }

    private func frameAlignment(
        at index: Int
    ) -> Alignment {
        switch alignment(at: index) {
        case .left:
            .leading
        case .center:
            .center
        case .right:
            .trailing
        }
    }

    private func alignment(
        at index: Int
    ) -> GitLabMarkdownTableAlignment {
        guard table.alignments.indices.contains(index) else {
            return .left
        }
        return table.alignments[index]
    }

    private func accessibilityLabel(
        for cell: GitLabMarkdownText,
        column: Int,
        isHeader: Bool
    ) -> String {
        if isHeader {
            return "Column header, \(cell.plainText)"
        }
        let header = table.header.indices.contains(column)
            ? table.header[column].plainText
            : "Column \(column + 1)"
        return "\(header), \(cell.plainText)"
    }
}

private struct GitLabMarkdownImageGroupView: View {
    let group: GitLabMarkdownImageGroup

    @ViewBuilder
    var body: some View {
        if group.images.count == 1,
           let image = group.images.first
        {
            GitLabMarkdownMediaView(
                image: image,
                presentation: .document
            )
            .frame(
                maxWidth: .infinity,
                alignment:
                    group.alignment == .center
                        ? .center
                        : .leading
            )
        } else {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 96,
                            maximum: 180
                        ),
                        spacing: 8
                    ),
                ],
                alignment:
                    group.alignment == .center
                        ? .center
                        : .leading,
                spacing: 8
            ) {
                ForEach(
                    Array(group.images.enumerated()),
                    id: \.offset
                ) { _, image in
                    GitLabMarkdownMediaView(
                        image: image,
                        presentation: .compact
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment:
                    group.alignment == .center
                        ? .center
                        : .leading
            )
        }
    }
}

private struct GitLabMarkdownMediaView: View {
    let image: GitLabMarkdownImage
    let presentation:
        GitLabMarkdownImageView.Presentation

    init(
        image: GitLabMarkdownImage,
        presentation:
            GitLabMarkdownImageView.Presentation = .document
    ) {
        self.image = image
        self.presentation = presentation
    }

    @ViewBuilder
    var body: some View {
        switch image.kind {
        case .image:
            GitLabMarkdownImageView(
                image: image,
                presentation: presentation
            )
        case .video, .audio:
            GitLabMarkdownPlayableMediaView(
                media: image,
                presentation: presentation
            )
        }
    }
}

private struct GitLabMarkdownImageView: View {
    fileprivate enum Presentation {
        case document
        case compact
    }

    private enum Phase {
        case idle
        case loading
        case loaded(
            GitLabMarkdownImageLoadRequest,
            GitLabMarkdownDecodedImage
        )
        case failed(String)
    }

    private struct LoadIdentity: Hashable {
        let accountID: GitLabAccountID
        let urls: [URL]
        let targetPixelWidth: Int
        let retry: UInt64
    }

    let image: GitLabMarkdownImage
    let presentation: Presentation

    @Environment(\.displayScale)
    private var displayScale
    @Environment(\.gitLabMarkdownImageLoader)
    private var imageLoader
    @State private var phase = Phase.idle
    @State private var targetPixelWidth = 0
    @State private var containerWidth: CGFloat = 0
    @State private var retry: UInt64 = 0
    @State private var isViewerPresented = false

    init(
        image: GitLabMarkdownImage,
        presentation: Presentation = .document
    ) {
        self.image = image
        self.presentation = presentation
    }

    var body: some View {
        let currentDisplayScale = displayScale

        content
            .frame(
                width: displayWidth,
                alignment: .leading
            )
            .frame(
                maxWidth:
                    presentation == .compact
                        ? 180
                        : .infinity,
                alignment: .leading
            )
            .onGeometryChange(
                for: CGSize.self
            ) { proxy in
                proxy.size
            } action: { newValue in
                containerWidth = newValue.width
                targetPixelWidth = max(
                    1,
                    Int(
                        (
                            resolvedWidth(
                                availableWidth:
                                    newValue.width
                            )
                                * currentDisplayScale
                        ).rounded(.up)
                    )
                )
            }
            .task(id: loadIdentity) {
                await load()
            }
            .fullScreenCover(
                isPresented: $isViewerPresented
            ) {
                if case let .loaded(_, decodedImage) = phase {
                    GitLabMarkdownImageViewer(
                        image: image,
                        previewImage: decodedImage
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            placeholder
        case let .loaded(_, decodedImage):
            loadedImage(decodedImage)
        case let .failed(message):
            failureView(message: message)
        }
    }

    @ViewBuilder
    private func loadedImage(
        _ decodedImage: GitLabMarkdownDecodedImage
    ) -> some View {
        let content = Image(
            decodedImage.cgImage,
            scale: displayScale,
            label: Text(
                image.accessibilityLabel
            )
        )
        .resizable()
        .scaledToFit()
        .frame(
            maxWidth:
                presentation == .compact
                    ? 180
                    : .infinity,
            maxHeight:
                resolvedHeight
        )
        .clipShape(
            .rect(
                cornerRadius:
                    presentation == .compact
                        ? 4
                        : 12
            )
        )

        Button {
            isViewerPresented = true
        } label: {
            content
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens image viewer")
    }

    @ViewBuilder
    private var placeholder: some View {
        if presentation == .compact {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)

                if !image.altText.isEmpty {
                    Text(image.altText)
                        .font(.glabCaption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(
                maxWidth: 180,
                minHeight: 32
            )
            .background(
                Color.secondary.opacity(0.08),
                in: .rect(cornerRadius: 6)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Loading image, "
                    + image.accessibilityLabel
            )
        } else {
        VStack(spacing: 10) {
            ProgressView()

            Text(image.accessibilityLabel)
                .font(.glabCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            minHeight: 140
        )
        .background(
            Color.secondary.opacity(0.08),
            in: .rect(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Loading image, "
                + image.accessibilityLabel
        )
        }
    }

    @ViewBuilder
    private func failureView(
        message: String
    ) -> some View {
        if presentation == .compact {
            HStack(spacing: 6) {
                Image(
                    systemName:
                        "photo.badge.exclamationmark"
                )
                .foregroundStyle(.secondary)

                Text(image.accessibilityLabel)
                    .font(.glabCaption2)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    retry &+= 1
                } label: {
                    Image(
                        systemName: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Try Again")
            }
            .padding(.horizontal, 8)
            .frame(
                maxWidth: 180,
                minHeight: 32
            )
            .background(
                Color.secondary.opacity(0.08),
                in: .rect(cornerRadius: 6)
            )
            .accessibilityElement(
                children: .contain
            )
            .accessibilityLabel(
                "Image failed to load, "
                    + image.accessibilityLabel
                    + ". "
                    + message
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    image.accessibilityLabel,
                    systemImage:
                        "photo.badge.exclamationmark"
                )
                .font(.glabCallout.weight(.semibold))

                Text(message)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)

                Button("Try Again") {
                    retry &+= 1
                }
                .font(.glabCallout.weight(.semibold))
            }
            .padding(12)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background(
                Color.secondary.opacity(0.08),
                in: .rect(cornerRadius: 12)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Image failed to load, "
                    + image.accessibilityLabel
            )
        }
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            accountID: image.accountID,
            urls: image.candidateURLs,
            targetPixelWidth:
                GitLabMarkdownImageLoadRequest
                    .normalizedTargetPixelWidth(
                        targetPixelWidth
                    ),
            retry: retry
        )
    }

    private func load() async {
        guard targetPixelWidth > 0 else {
            return
        }
        let previousPhase = phase
        let canPreserveVisibleImage: Bool
        if
            case let .loaded(
                previousRequest,
                _
            ) = previousPhase,
            previousRequest.accountID
                == image.accountID,
            image.candidateURLs.contains(
                previousRequest.url
            )
        {
            canPreserveVisibleImage = true
            // Preserve a visible image while a size change is
            // resolved from the memory cache.
        } else {
            canPreserveVisibleImage = false
            phase = .loading
        }

        var lastError: (any Error)?
        for url in image.candidateURLs {
            let request = GitLabMarkdownImageLoadRequest(
                accountID: image.accountID,
                url: url,
                targetPixelWidth: targetPixelWidth
            )
            do {
                let decodedImage =
                    try await imageLoader.image(request)
                guard !Task.isCancelled else {
                    return
                }
                phase = .loaded(
                    request,
                    decodedImage
                )
                return
            } catch is CancellationError {
                guard !Task.isCancelled else {
                    return
                }
                phase = previousPhase
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                lastError = error
            }
        }
        if canPreserveVisibleImage {
            phase = previousPhase
        } else {
            phase = .failed(
                lastError?.localizedDescription
                    ?? "The image could not be loaded."
            )
        }
    }

    private var displayWidth: CGFloat? {
        guard
            presentation == .document,
            containerWidth > 0,
            let width = image.dimensions?.width
        else {
            return nil
        }
        return resolved(
            width,
            relativeTo: containerWidth
        )
    }

    private var resolvedHeight: CGFloat {
        guard
            presentation == .document,
            let height = image.dimensions?.height
        else {
            return presentation == .compact ? 48 : 420
        }
        return min(
            420,
            resolved(height, relativeTo: 420)
        )
    }

    private func resolvedWidth(
        availableWidth: CGFloat
    ) -> CGFloat {
        guard
            presentation == .document,
            let width = image.dimensions?.width
        else {
            return min(
                availableWidth,
                presentation == .compact ? 180 : availableWidth
            )
        }
        return resolved(
            width,
            relativeTo: availableWidth
        )
    }

    private func resolved(
        _ dimension: GitLabMarkdownMediaDimension,
        relativeTo available: CGFloat
    ) -> CGFloat {
        switch dimension.unit {
        case .pixels:
            min(available, CGFloat(dimension.value))
        case .percent:
            available * CGFloat(dimension.value / 100)
        }
    }
}

private struct GitLabMarkdownImageViewer: View {
    let image: GitLabMarkdownImage
    let previewImage: GitLabMarkdownDecodedImage

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.openURL)
    private var openURL
    @Environment(\.gitLabMarkdownImageLoader)
    private var imageLoader
    @State private var fullResolutionImage:
        GitLabMarkdownDecodedImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GitLabMarkdownZoomableImageView(
                decodedImage:
                    fullResolutionImage ?? previewImage
            )
            .accessibilityLabel(
                image.accessibilityLabel
            )

            VStack {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        if let linkURL = image.linkURL {
                            Button {
                                openURL(linkURL)
                            } label: {
                                Image(
                                    systemName:
                                        "arrow.up.right"
                                )
                                .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel(
                                "Open linked page"
                            )
                        }

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Close")
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .trailing
                )

                Spacer()
            }
            .padding(.horizontal, 16)
            .safeAreaPadding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .task {
            await loadFullResolutionImage()
        }
    }

    private func loadFullResolutionImage() async {
        for url in image.candidateURLs {
            do {
                let decodedImage = try await imageLoader.image(
                    GitLabMarkdownImageLoadRequest(
                        accountID: image.accountID,
                        url: url,
                        targetPixelWidth: 2_048
                    )
                )
                try Task.checkCancellation()
                fullResolutionImage = decodedImage
                return
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
    }
}

private struct GitLabMarkdownZoomableImageView:
    UIViewRepresentable
{
    let decodedImage: GitLabMarkdownDecodedImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor
            ),
            imageView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor
            ),
            imageView.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor
            ),
            imageView.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor
            ),
            imageView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ),
            imageView.heightAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.heightAnchor
            ),
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleTapped(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(
        _ scrollView: UIScrollView,
        context: Context
    ) {
        context.coordinator.imageView.image = UIImage(
            cgImage: decodedImage.cgImage
        )
    }

    final class Coordinator:
        NSObject,
        UIScrollViewDelegate
    {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?

        func viewForZooming(
            in scrollView: UIScrollView
        ) -> UIView? {
            imageView
        }

        @objc
        func doubleTapped(
            _ recognizer: UITapGestureRecognizer
        ) {
            guard let scrollView else {
                return
            }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(
                    in: imageView
                )
                let size = CGSize(
                    width: scrollView.bounds.width / 2.5,
                    height: scrollView.bounds.height / 2.5
                )
                scrollView.zoom(
                    to: CGRect(
                        x: point.x - size.width / 2,
                        y: point.y - size.height / 2,
                        width: size.width,
                        height: size.height
                    ),
                    animated: true
                )
            }
        }
    }
}

private struct GitLabMarkdownPlayableMediaView: View {
    let media: GitLabMarkdownImage
    let presentation:
        GitLabMarkdownImageView.Presentation

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: media.kind == .video
                    ? "play.rectangle.fill"
                    : "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)

                Text(media.accessibilityLabel)
                    .font(.glabCallout.weight(.semibold))
                    .lineLimit(
                        presentation == .compact ? 1 : 2
                    )

                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(
                maxWidth:
                    presentation == .compact
                        ? 180
                        : .infinity,
                minHeight: 44,
                alignment: .leading
            )
            .background(
                Color.secondary.opacity(0.08),
                in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            media.kind == .video
                ? "Opens video player"
                : "Opens audio player"
        )
        .fullScreenCover(isPresented: $isPresented) {
            GitLabMarkdownMediaPlayerView(media: media)
        }
    }
}

private struct GitLabMarkdownMediaPlayerView: View {
    private enum Phase {
        case loading
        case loaded(URL, AVPlayer)
        case failed(String)
    }

    let media: GitLabMarkdownImage

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.gitLabMarkdownMediaLoader)
    private var mediaLoader
    @State private var phase = Phase.loading
    @State private var retry: UInt64 = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content

            VStack {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            UIApplication.shared.open(
                                media.linkURL
                                    ?? media.browserURL
                                    ?? media.url
                            )
                        } label: {
                            Image(
                                systemName: "safari"
                            )
                            .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(
                            "Open in browser"
                        )

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Close")
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .trailing
                )

                Spacer()
            }
            .padding(.horizontal, 16)
            .safeAreaPadding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .task(id: retry) {
            await load()
        }
        .onDisappear {
            cleanUp()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading media…")
                    .font(.glabCallout)
                    .foregroundStyle(.secondary)
            }
        case let .loaded(_, player):
            VStack(spacing: 20) {
                if media.kind == .audio {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.tint)
                    Text(media.accessibilityLabel)
                        .font(.glabHeadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VideoPlayer(player: player)
                    .frame(
                        maxHeight:
                            media.kind == .audio
                                ? 120
                                : .infinity
                    )
                    .onAppear {
                        player.play()
                    }
            }
            .padding(.vertical, 80)
        case let .failed(message):
            ContentUnavailableView {
                Label(
                    "Couldn’t Load Media",
                    systemImage:
                        "play.slash.fill"
                )
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    retry &+= 1
                }
                .buttonStyle(.glassProminent)
            }
            .foregroundStyle(.white)
        }
    }

    private func load() async {
        phase = .loading
        do {
            let url = try await mediaLoader.file(
                for: GitLabMarkdownMediaLoadRequest(
                    accountID: media.accountID,
                    urls: media.candidateURLs,
                    kind: media.kind,
                    preferredFileExtension:
                        media.browserURL?.pathExtension
                )
            )
            do {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else {
                    throw GitLabMarkdownMediaError
                        .invalidContentType
                }
                try Task.checkCancellation()
                phase = .loaded(
                    url,
                    AVPlayer(
                        playerItem: AVPlayerItem(
                            asset: asset
                        )
                    )
                )
            } catch {
                await mediaLoader.removeFile(at: url)
                throw error
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(
                error.localizedDescription
            )
        }
    }

    private func cleanUp() {
        guard case let .loaded(url, player) = phase else {
            return
        }
        player.pause()
        Task {
            await mediaLoader.removeFile(at: url)
        }
    }
}

private struct GitLabMarkdownRichTextView:
    UIViewRepresentable
{
    let richText: GitLabMarkdownRichText

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.tintColor,
            .underlineStyle:
                NSUnderlineStyle.single.rawValue,
        ]
        textView.textColor = .label
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(
        _ textView: UITextView,
        context: Context
    ) {
        let displayText = NSMutableAttributedString(
            attributedString:
                richText.attributedString
        )
        displayText.addAttribute(
            .foregroundColor,
            value: UIColor.label,
            range: NSRange(
                location: 0,
                length: displayText.length
            )
        )
        textView.attributedText = displayText
        context.coordinator.openURL =
            context.environment.openURL
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard
            let width = proposal.width,
            width > 0
        else {
            return nil
        }
        let size = uiView.sizeThatFits(
            CGSize(
                width: width,
                height: .greatestFiniteMagnitude
            )
        )
        return CGSize(
            width: width,
            height: ceil(size.height)
        )
    }

    final class Coordinator:
        NSObject,
        UITextViewDelegate
    {
        var openURL: OpenURLAction?

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard
                case let .link(url) =
                    textItem.content
            else {
                return defaultAction
            }
            return UIAction { [openURL] _ in
                openURL?(url)
            }
        }
    }
}

private struct GitLabMarkdownUnsupportedView: View {
    let unsupported: GitLabMarkdownUnsupported

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "View in GitLab for full rendering",
                systemImage: "safari"
            )
            .font(.glabCallout.weight(.semibold))
            .foregroundStyle(.orange)

            if !unsupported.source.isEmpty {
                Text(unsupported.source)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.08),
            in: .rect(cornerRadius: 12)
        )
        .accessibilityLabel(
            unsupported.accessibilityLabel
        )
    }
}
