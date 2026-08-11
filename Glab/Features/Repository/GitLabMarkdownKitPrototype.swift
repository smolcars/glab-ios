import MarkdownKit
import SwiftUI
import UIKit

nonisolated enum GitLabMarkdownKitPrototypeRenderer {
    enum Palette: Hashable, Sendable {
        case light
        case dark
    }

    @concurrent
    static func render(
        source: String,
        palette: Palette
    ) async -> sending NSAttributedString? {
        guard !Task.isCancelled else {
            return nil
        }

        let document = ExtendedMarkdownParser()
            .parse(source)
        let foregroundColor =
            palette == .dark
            ? "#F3F4F6"
            : "#1F2328"
        let codeBackground =
            palette == .dark
            ? "#2D333B"
            : "#F6F8FA"
        let borderColor =
            palette == .dark
            ? "#444C56"
            : "#D0D7DE"
        let quoteColor =
            palette == .dark
            ? "#768390"
            : "#8C959F"
        let generator = AttributedStringGenerator(
            fontSize: 17,
            fontColor: foregroundColor,
            codeFontSize: 15,
            codeFontColor: foregroundColor,
            codeBlockFontSize: 14,
            codeBlockFontColor: foregroundColor,
            codeBlockBackground: codeBackground,
            syntaxHighlighting: nil,
            borderColor: borderColor,
            blockquoteColor: quoteColor,
            h1Color: foregroundColor,
            h2Color: foregroundColor,
            h3Color: foregroundColor,
            h4Color: foregroundColor,
            maxImageWidth: "100%",
            customStyle:
                "a { color: #0A84FF; } "
                + "body { line-height: 1.35; }"
        )
        let result = generator.generate(
            doc: document
        )

        guard !Task.isCancelled else {
            return nil
        }
        return result
    }
}

struct GitLabMarkdownKitPrototypeView: View {
    private struct LoadIdentity: Hashable {
        let digest: Data
        let palette:
            GitLabMarkdownKitPrototypeRenderer
            .Palette
    }

    private enum RenderState {
        case loading
        case loaded(NSAttributedString)
        case failed
    }

    let source: String

    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.gitLabMarkdownLinkHandler)
    private var linkHandler
    @State private var state:
        RenderState = .loading

    init(source: String) {
        self.source = source
    }

    var body: some View {
        content
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard
                        GitLabWebURL.validated(url)
                            != nil
                    else {
                        return .discarded
                    }
                    return linkHandler.handle(url)
                        ? .handled
                        : .systemAction
                }
            )
            .task(id: loadIdentity) {
                state = .loading
                let rendered =
                    await GitLabMarkdownKitPrototypeRenderer
                    .render(
                        source: source,
                        palette: palette
                    )
                guard !Task.isCancelled else {
                    return
                }
                state = rendered.map(
                    RenderState.loaded
                )
                    ?? .failed
            }
            .accessibilityIdentifier(
                "repository.markdownKitPrototype"
            )
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Formatting with MarkdownKit…")
                    .foregroundStyle(.secondary)
            }
            .font(.glabCallout)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        case let .loaded(attributedText):
            GitLabMarkdownKitAttributedTextView(
                attributedText: attributedText
            )
        case .failed:
            ContentUnavailableView(
                "Couldn’t format this file",
                systemImage:
                    "exclamationmark.triangle"
            )
        }
    }

    private var palette:
        GitLabMarkdownKitPrototypeRenderer.Palette
    {
        colorScheme == .dark ? .dark : .light
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            digest:
                GitLabMarkdownSourceDigest
                .digest(for: source),
            palette: palette
        )
    }
}

private struct GitLabMarkdownKitAttributedTextView:
    UIViewRepresentable
{
    let attributedText: NSAttributedString

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
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(
        _ textView: UITextView,
        context: Context
    ) {
        textView.attributedText = attributedText
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
