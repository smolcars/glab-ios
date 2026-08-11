import SwiftUI
import UIKit

private struct GitLabMarkdownRendererEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabMarkdownRendering =
            GitLabMarkdownRenderer()
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
    GitLabReadOnlyMarkdownRendererEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabMarkdownRendering =
            GitLabMarkdownRenderer(
                rendererVersion: 2,
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
            GitLabMarkdownImageView(
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
                Text(code.text)
                    .font(.system(.callout, design: .monospaced))
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
    }
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
            GitLabMarkdownImageView(
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
                    GitLabMarkdownImageView(
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

private struct GitLabMarkdownImageView: View {
    enum Presentation {
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
        let url: URL
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
    @State private var retry: UInt64 = 0

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
                maxWidth:
                    presentation == .compact
                        ? 180
                        : .infinity,
                alignment: .leading
            )
            .onGeometryChange(
                for: Int.self
            ) { proxy in
                max(
                    1,
                    Int(
                        (
                            proxy.size.width
                                * currentDisplayScale
                        ).rounded(.up)
                    )
                )
            } action: { newValue in
                targetPixelWidth = newValue
            }
            .task(id: loadIdentity) {
                await load()
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
                presentation == .compact
                    ? 48
                    : 420
        )
        .clipShape(
            .rect(
                cornerRadius:
                    presentation == .compact
                        ? 4
                        : 12
            )
        )

        if let linkURL = image.linkURL {
            Button {
                openURL(linkURL)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                "Opens the linked page"
            )
        } else {
            content
        }
    }

    @Environment(\.openURL)
    private var openURL

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
            url: image.url,
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
        let request = GitLabMarkdownImageLoadRequest(
            accountID: image.accountID,
            url: image.url,
            targetPixelWidth: targetPixelWidth
        )
        let previousPhase = phase
        let canPreserveVisibleImage: Bool
        if
            case let .loaded(
                previousRequest,
                _
            ) = previousPhase,
            previousRequest.accountID
                == request.accountID,
            previousRequest.url == request.url
        {
            canPreserveVisibleImage = true
            // Preserve a visible image while a size change is
            // resolved from the memory cache.
        } else {
            canPreserveVisibleImage = false
            phase = .loading
        }

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
        } catch is CancellationError {
            guard !Task.isCancelled else {
                return
            }
            phase = previousPhase
        } catch {
            guard !Task.isCancelled else {
                return
            }
            if canPreserveVisibleImage {
                phase = previousPhase
            } else {
                phase = .failed(
                    error.localizedDescription
                )
            }
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
