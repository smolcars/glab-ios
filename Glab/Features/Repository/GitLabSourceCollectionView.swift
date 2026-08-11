import SwiftUI
import UIKit

struct GitLabSourceCollectionView:
    UIViewRepresentable
{
    let document: GitLabSourceDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeUIView(
        context: Context
    ) -> UICollectionView {
        let layout = GitLabSourceCollectionLayout()
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.backgroundColor =
            .glabSurface
        collectionView.alwaysBounceVertical = true
        collectionView.alwaysBounceHorizontal = true
        collectionView.showsVerticalScrollIndicator =
            true
        collectionView.showsHorizontalScrollIndicator =
            true
        collectionView
            .contentInsetAdjustmentBehavior = .never
        collectionView.dataSource =
            context.coordinator
        collectionView.delegate =
            context.coordinator
        collectionView.register(
            GitLabSourceLineCell.self,
            forCellWithReuseIdentifier:
                GitLabSourceLineCell.reuseIdentifier
        )
        collectionView.accessibilityIdentifier =
            "repository.source"
        context.coordinator.attach(collectionView)
        return collectionView
    }

    func updateUIView(
        _ collectionView: UICollectionView,
        context: Context
    ) {
        context.coordinator.update(document)
    }

    static func dismantleUIView(
        _ collectionView: UICollectionView,
        coordinator: Coordinator
    ) {
        collectionView.dataSource = nil
        collectionView.delegate = nil
    }

    @MainActor
    final class Coordinator:
        NSObject,
        UICollectionViewDataSource,
        UICollectionViewDelegate
    {
        private(set) var document:
            GitLabSourceDocument
        private weak var collectionView:
            UICollectionView?
        private var highlighter:
            GitLabSourceLineHighlighter
        private var font = UIFont
            .monospacedSystemFont(
                ofSize: 14,
                weight: .regular
            )
        private var rowHeight: CGFloat = 24
        private var glyphWidth: CGFloat = 8
        private var gutterWidth: CGFloat = 48

        init(document: GitLabSourceDocument) {
            self.document = document
            highlighter = GitLabSourceLineHighlighter(
                language: document.language
            )
        }

        func collectionView(
            _ collectionView: UICollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            document.lineCount
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard
                let cell = collectionView
                    .dequeueReusableCell(
                        withReuseIdentifier:
                            GitLabSourceLineCell
                            .reuseIdentifier,
                        for: indexPath
                    ) as? GitLabSourceLineCell
            else {
                return UICollectionViewCell()
            }

            let line = document.lines[
                indexPath.item
            ]
            cell.configure(
                lineNumber: indexPath.item + 1,
                source:
                    highlighter.attributedLine(
                        line,
                        index: indexPath.item,
                        font: font
                    ),
                plainSource: line,
                font: font,
                gutterWidth: gutterWidth,
                horizontalOffset:
                    collectionView.contentOffset.x
            )
            return cell
        }

        func scrollViewDidScroll(
            _ scrollView: UIScrollView
        ) {
            let horizontalOffset =
                scrollView.contentOffset.x
            collectionView?.visibleCells
                .compactMap {
                    $0 as? GitLabSourceLineCell
                }
                .forEach {
                    $0.updateGutterPosition(
                        horizontalOffset:
                            horizontalOffset
                    )
                }
        }

        fileprivate func attach(
            _ collectionView: UICollectionView
        ) {
            self.collectionView = collectionView
            updateMetrics()
            configureLayout()
        }

        fileprivate func update(
            _ document: GitLabSourceDocument
        ) {
            updateMetrics()
            guard self.document != document else {
                configureLayout()
                return
            }

            self.document = document
            highlighter = GitLabSourceLineHighlighter(
                language: document.language
            )
            collectionView?.reloadData()
            configureLayout()
            collectionView?.setContentOffset(
                .zero,
                animated: false
            )
        }

        private func updateMetrics() {
            let scaledFont = UIFontMetrics(
                forTextStyle: .body
            ).scaledFont(
                for: UIFont.monospacedSystemFont(
                    ofSize: 14,
                    weight: .regular
                ),
                compatibleWith:
                    collectionView?.traitCollection
            )
            let scaledRowHeight = ceil(
                scaledFont.lineHeight + 7
            )
            let scaledGlyphWidth = max(
                1,
                ("M" as NSString).size(
                    withAttributes: [
                        .font: scaledFont,
                    ]
                ).width
            )
            let digits = max(
                1,
                String(
                    max(1, document.lineCount)
                ).count
            )
            let scaledGutterWidth = max(
                44,
                CGFloat(digits + 2)
                    * scaledGlyphWidth
            )
            guard
                scaledFont != font
                    || scaledRowHeight != rowHeight
                    || scaledGlyphWidth != glyphWidth
                    || scaledGutterWidth
                        != gutterWidth
            else {
                return
            }

            font = scaledFont
            rowHeight = scaledRowHeight
            glyphWidth = scaledGlyphWidth
            gutterWidth = scaledGutterWidth
            highlighter.removeAllCachedLines()
            collectionView?.reloadData()
        }

        private func configureLayout() {
            guard
                let layout = collectionView?
                    .collectionViewLayout
                    as? GitLabSourceCollectionLayout
            else {
                return
            }

            let contentWidth = gutterWidth
                + 16
                + CGFloat(
                    document
                        .maximumRenderedColumnCount
                ) * glyphWidth
                + 24
            layout.configure(
                itemCount: document.lineCount,
                rowHeight: rowHeight,
                contentWidth: contentWidth
            )
        }
    }
}

@MainActor
private final class GitLabSourceCollectionLayout:
    UICollectionViewLayout
{
    private var itemCount = 0
    private var rowHeight: CGFloat = 24
    private var requestedContentWidth:
        CGFloat = 320

    func configure(
        itemCount: Int,
        rowHeight: CGFloat,
        contentWidth: CGFloat
    ) {
        let values = (
            max(0, itemCount),
            max(1, rowHeight),
            max(1, contentWidth)
        )
        guard
            self.itemCount != values.0
                || self.rowHeight != values.1
                || requestedContentWidth
                    != values.2
        else {
            return
        }
        self.itemCount = values.0
        self.rowHeight = values.1
        requestedContentWidth = values.2
        invalidateLayout()
    }

    override var collectionViewContentSize:
        CGSize
    {
        let bounds = collectionView?.bounds ?? .zero
        return CGSize(
            width: max(
                bounds.width,
                requestedContentWidth
            ),
            height: max(
                bounds.height,
                CGFloat(itemCount) * rowHeight
            )
        )
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        guard itemCount > 0 else {
            return []
        }
        let first = max(
            0,
            Int(floor(rect.minY / rowHeight))
        )
        let last = min(
            itemCount - 1,
            Int(
                floor(
                    max(rect.minY, rect.maxY - 1)
                        / rowHeight
                )
            )
        )
        guard first <= last else {
            return []
        }
        return (first...last).map(attributes)
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard
            (0..<itemCount).contains(
                indexPath.item
            )
        else {
            return nil
        }
        return attributes(indexPath.item)
    }

    override func shouldInvalidateLayout(
        forBoundsChange newBounds: CGRect
    ) -> Bool {
        guard let collectionView else {
            return false
        }
        return collectionView.bounds.size
            != newBounds.size
    }

    private func attributes(
        _ item: Int
    ) -> UICollectionViewLayoutAttributes {
        let attributes =
            UICollectionViewLayoutAttributes(
                forCellWith: IndexPath(
                    item: item,
                    section: 0
                )
            )
        attributes.frame = CGRect(
            x: 0,
            y: CGFloat(item) * rowHeight,
            width: collectionViewContentSize.width,
            height: rowHeight
        )
        return attributes
    }
}

@MainActor
private final class GitLabSourceLineCell:
    UICollectionViewCell
{
    static let reuseIdentifier =
        "GitLabSourceLineCell"

    private let gutterView = UIView()
    private let lineNumberLabel = UILabel()
    private let sourceLabel = UILabel()
    private var gutterWidth: CGFloat = 48
    private var horizontalOffset: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)

        gutterView.backgroundColor =
            .glabRaisedSurface
        lineNumberLabel.textAlignment = .right
        lineNumberLabel.textColor =
            .tertiaryLabel
        lineNumberLabel.numberOfLines = 1
        sourceLabel.numberOfLines = 1
        sourceLabel.lineBreakMode = .byClipping

        gutterView.addSubview(lineNumberLabel)
        contentView.addSubview(sourceLabel)
        contentView.addSubview(gutterView)
        isAccessibilityElement = true
        gutterView.isAccessibilityElement = false
        lineNumberLabel.isAccessibilityElement = false
        sourceLabel.isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError(
            "init(coder:) has not been implemented"
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        lineNumberLabel.text = nil
        sourceLabel.attributedText = nil
        accessibilityLabel = nil
        gutterView.transform = .identity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gutterView.transform = .identity
        gutterView.frame = CGRect(
            x: 0,
            y: 0,
            width: gutterWidth,
            height: bounds.height
        )
        gutterView.transform = CGAffineTransform(
            translationX: horizontalOffset,
            y: 0
        )
        lineNumberLabel.frame = CGRect(
            x: 6,
            y: 0,
            width: max(0, gutterWidth - 12),
            height: bounds.height
        )
        sourceLabel.frame = CGRect(
            x: gutterWidth + 12,
            y: 0,
            width: max(
                0,
                bounds.width - gutterWidth - 20
            ),
            height: bounds.height
        )
    }

    func configure(
        lineNumber: Int,
        source: NSAttributedString,
        plainSource: String,
        font: UIFont,
        gutterWidth: CGFloat,
        horizontalOffset: CGFloat
    ) {
        self.gutterWidth = gutterWidth
        lineNumberLabel.font = font
        sourceLabel.font = font
        lineNumberLabel.text =
            String(lineNumber)
        sourceLabel.attributedText = source
        let accessibleSource =
            plainSource.count > 500
            ? String(plainSource.prefix(500))
                + "…"
            : plainSource
        accessibilityLabel = accessibleSource.isEmpty
            ? "Line \(lineNumber), blank"
            : "Line \(lineNumber), \(accessibleSource)"
        updateGutterPosition(
            horizontalOffset: horizontalOffset
        )
        setNeedsLayout()
    }

    func updateGutterPosition(
        horizontalOffset: CGFloat
    ) {
        self.horizontalOffset = horizontalOffset
        gutterView.transform =
            CGAffineTransform(
                translationX: horizontalOffset,
                y: 0
            )
    }
}

@MainActor
private final class GitLabSourceLineHighlighter {
    private let language: GitLabSourceLanguage
    private let cache = NSCache<
        NSNumber,
        NSAttributedString
    >()

    init(language: GitLabSourceLanguage) {
        self.language = language
        cache.countLimit = 600
    }

    func removeAllCachedLines() {
        cache.removeAllObjects()
    }

    func attributedLine(
        _ line: String,
        index: Int,
        font: UIFont
    ) -> NSAttributedString {
        let key = NSNumber(value: index)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let value = NSMutableAttributedString(
            string: line,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
            ]
        )
        guard line.utf16.count <= 4_096 else {
            cache.setObject(value, forKey: key)
            return value
        }

        highlight(
            pattern: keywordPattern,
            in: value,
            color: .systemPurple
        )
        highlight(
            pattern: #"\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b"#,
            in: value,
            color: .systemOrange
        )
        highlight(
            pattern: stringPattern,
            in: value,
            color: .systemBlue
        )
        highlight(
            pattern: commentPattern,
            in: value,
            color: .secondaryLabel
        )
        highlightLanguageSpecificSyntax(in: value)

        cache.setObject(value, forKey: key)
        return value
    }

    private var keywordPattern: String {
        let keywords: [String] = switch language {
        case .swift:
            [
                "actor", "async", "await", "case", "class",
                "enum", "extension", "func", "guard", "if",
                "import", "init", "let", "nonisolated", "private",
                "protocol", "return", "self", "some", "struct",
                "switch", "throw", "throws", "try", "var", "where",
            ]
        case .shell:
            [
                "case", "do", "done", "elif", "else", "esac",
                "fi", "for", "function", "if", "in", "then",
                "until", "while",
            ]
        case .python:
            [
                "and", "as", "async", "await", "class", "def",
                "elif", "else", "except", "False", "for", "from",
                "if", "import", "in", "is", "lambda", "None",
                "not", "or", "pass", "raise", "return", "True",
                "try", "while", "with", "yield",
            ]
        case .javascript, .typescript:
            [
                "async", "await", "break", "case", "catch", "class",
                "const", "continue", "default", "else", "export",
                "extends", "false", "for", "function", "if", "import",
                "interface", "let", "new", "null", "return", "switch",
                "throw", "true", "try", "type", "undefined", "var",
                "while",
            ]
        case .ruby:
            [
                "begin", "case", "class", "def", "do", "else", "elsif",
                "end", "ensure", "false", "if", "module", "nil", "rescue",
                "return", "self", "then", "true", "unless", "until", "while",
            ]
        case .rust:
            [
                "as", "async", "await", "const", "crate", "else", "enum",
                "false", "fn", "for", "if", "impl", "let", "loop", "match",
                "mod", "move", "mut", "pub", "ref", "return", "self", "struct",
                "trait", "true", "type", "unsafe", "use", "where", "while",
            ]
        case .go:
            [
                "break", "case", "chan", "const", "continue", "default",
                "defer", "else", "fallthrough", "for", "func", "go", "goto",
                "if", "import", "interface", "map", "package", "range", "return",
                "select", "struct", "switch", "type", "var",
            ]
        case .cLike:
            [
                "break", "case", "class", "const", "continue", "default",
                "do", "else", "enum", "false", "for", "if", "import", "new",
                "null", "private", "protected", "public", "return", "static",
                "struct", "switch", "this", "throw", "true", "try", "void", "while",
            ]
        case .json, .yaml, .markup, .markdown,
             .plainText:
            []
        }
        guard !keywords.isEmpty else {
            return #"(?!)"#
        }
        return #"\b(?:"#
            + keywords.joined(separator: "|")
            + #")\b"#
    }

    private var stringPattern: String {
        switch language {
        case .markup:
            #"(?:\"[^\"]*\"|'[^']*')"#
        default:
            #"(?:\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)"#
        }
    }

    private var commentPattern: String {
        switch language {
        case .shell, .python, .ruby, .yaml:
            #"#.*$"#
        case .json, .plainText, .markdown:
            #"(?!)"#
        case .markup:
            #"<!--.*?-->"#
        default:
            #"//.*$"#
        }
    }

    private func highlightLanguageSpecificSyntax(
        in value: NSMutableAttributedString
    ) {
        switch language {
        case .json, .yaml:
            highlight(
                pattern: #"^\s*(?:\"[^\"]+\"|[A-Za-z0-9_.-]+)(?=\s*:)"#,
                in: value,
                color: .systemPurple
            )
        case .markup:
            highlight(
                pattern: #"</?[A-Za-z][^>]*>|<\?[^>]*\?>"#,
                in: value,
                color: .systemPurple
            )
        case .markdown:
            highlight(
                pattern: #"^(?:#{1,6}|>|[-*+]\s)|(?:\*\*|__|`)[^`*_]+(?:\*\*|__|`)"#,
                in: value,
                color: .systemPurple
            )
        case .shell:
            highlight(
                pattern: #"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#,
                in: value,
                color: .systemTeal
            )
        default:
            break
        }
    }

    private func highlight(
        pattern: String,
        in value: NSMutableAttributedString,
        color: UIColor
    ) {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern
            )
        else {
            return
        }
        let range = NSRange(
            location: 0,
            length: value.length
        )
        expression.enumerateMatches(
            in: value.string,
            range: range
        ) { match, _, _ in
            guard let match else {
                return
            }
            value.addAttribute(
                .foregroundColor,
                value: color,
                range: match.range
            )
        }
    }
}
