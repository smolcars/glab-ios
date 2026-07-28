import SwiftUI

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

struct GitLabMarkdownDescriptionView: View {
    let request: GitLabMarkdownRequest
    let revision: Date

    @State private var model: GitLabMarkdownModel

    init(
        request: GitLabMarkdownRequest,
        revision: Date,
        renderer: any GitLabMarkdownRendering
    ) {
        self.request = request
        self.revision = revision
        _model = State(
            initialValue:
                GitLabMarkdownModel(
                    renderer: renderer
                )
        )
    }

    var body: some View {
        content
            .task(id: revision) {
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
                Text("Formatting description…")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        case let .loaded(document):
            if let failureMessage =
                model.failureMessage
            {
                GitLabMarkdownFailureNotice(
                    message: failureMessage
                ) {
                    Task {
                        await model.load(request)
                    }
                }
            }

            GitLabMarkdownDocumentView(
                document: document
            )
        case let .failed(message):
            GitLabMarkdownFailureNotice(
                message: message
            ) {
                Task {
                    await model.load(request)
                }
            }

            Text(request.source)
                .font(.body)
                .textSelection(.enabled)
                .accessibilityLabel(
                    "Unformatted description, "
                        + request.source
                )
        }
    }
}

private struct GitLabMarkdownFailureNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Couldn’t format this description",
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Try Again", action: retry)
                .font(.callout.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .orange.opacity(0.08),
            in: .rect(cornerRadius: 12)
        )
    }
}

private struct GitLabMarkdownDocumentView: View {
    let document: GitLabMarkdownDocument

    var body: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(
                Array(document.blocks.enumerated()),
                id: \.offset
            ) { _, block in
                GitLabMarkdownBlockView(
                    block: block
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
                .font(.body)
                .textSelection(.enabled)
        case let .list(list):
            GitLabMarkdownListView(list: list)
        case let .quote(quote):
            GitLabMarkdownQuoteView(quote: quote)
        case let .code(code):
            GitLabMarkdownCodeView(code: code)
        case let .table(table):
            GitLabMarkdownTableView(table: table)
        case let .image(image):
            GitLabMarkdownImageView(
                image: image
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
            .title2.bold()
        case 2:
            .title3.bold()
        case 3:
            .headline
        case 4:
            .subheadline.weight(.semibold)
        case 5:
            .callout.weight(.semibold)
        default:
            .caption.weight(.semibold)
        }
    }
}

private struct GitLabMarkdownListView: View {
    let list: GitLabMarkdownList

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

                    LazyVStack(
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
                                block: block
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }
                .accessibilityLabel(
                    item.accessibilityLabel
                )
            }
        }
    }

    @ViewBuilder
    private func marker(
        for item: GitLabMarkdownListItem
    ) -> some View {
        if let taskState = item.taskState {
            Image(
                systemName:
                    systemImage(for: taskState)
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(
                taskState == .incomplete
                    ? Color.secondary
                    : Color.orange
            )
            .accessibilityHidden(true)
        } else {
            Text(
                list.kind == .ordered
                    ? "\(item.ordinal)."
                    : "•"
            )
            .font(.body.weight(.medium))
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

private struct GitLabMarkdownQuoteView: View {
    let quote: GitLabMarkdownQuote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.orange.opacity(0.72))
                .frame(width: 4)
                .accessibilityHidden(true)

            LazyVStack(
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(
                    Array(quote.blocks.enumerated()),
                    id: \.offset
                ) { _, block in
                    GitLabMarkdownBlockView(
                        block: block
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
                    .font(.caption2.weight(.bold))
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
                            ? .callout.weight(.semibold)
                            : .callout
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

private struct GitLabMarkdownImageView: View {
    private enum Phase {
        case idle
        case loading
        case loaded(GitLabMarkdownDecodedImage)
        case failed(String)
    }

    private struct LoadIdentity: Hashable {
        let url: URL
        let targetPixelWidth: Int
        let retry: UInt64
    }

    let image: GitLabMarkdownImage

    @Environment(\.displayScale)
    private var displayScale
    @Environment(\.gitLabMarkdownImageLoader)
    private var imageLoader
    @State private var phase = Phase.idle
    @State private var targetPixelWidth = 0
    @State private var retry: UInt64 = 0

    var body: some View {
        let currentDisplayScale = displayScale

        content
            .frame(
                maxWidth: .infinity,
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
        case let .loaded(decodedImage):
            Image(
                decodedImage.cgImage,
                scale: displayScale,
                label: Text(
                    image.accessibilityLabel
                )
            )
            .resizable()
            .scaledToFit()
            .frame(
                maxWidth: .infinity,
                maxHeight: 420
            )
            .clipShape(
                .rect(cornerRadius: 12)
            )
        case let .failed(message):
            failureView(message: message)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            ProgressView()

            Text(image.accessibilityLabel)
                .font(.callout)
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

    private func failureView(
        message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                image.accessibilityLabel,
                systemImage:
                    "photo.badge.exclamationmark"
            )
            .font(.callout.weight(.semibold))

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                retry &+= 1
            }
            .font(.callout.weight(.semibold))
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

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            url: image.url,
            targetPixelWidth:
                targetPixelWidth,
            retry: retry
        )
    }

    private func load() async {
        guard targetPixelWidth > 0 else {
            return
        }
        let previousPhase = phase
        if case .loaded = previousPhase {
            // Preserve a visible image while a size change is
            // resolved from the memory cache.
        } else {
            phase = .loading
        }

        do {
            let decodedImage =
                try await imageLoader.image(
                    GitLabMarkdownImageLoadRequest(
                        accountID:
                            image.accountID,
                        url: image.url,
                        targetPixelWidth:
                            targetPixelWidth
                    )
                )
            guard !Task.isCancelled else {
                return
            }
            phase = .loaded(decodedImage)
        } catch is CancellationError {
            guard !Task.isCancelled else {
                return
            }
            phase = previousPhase
        } catch {
            guard !Task.isCancelled else {
                return
            }
            if case .loaded = previousPhase {
                phase = previousPhase
            } else {
                phase = .failed(
                    error.localizedDescription
                )
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
            .font(.callout.weight(.semibold))
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
