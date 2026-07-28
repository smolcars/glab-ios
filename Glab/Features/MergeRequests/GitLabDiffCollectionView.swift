import SwiftUI
import UIKit

enum GitLabDiffLayoutMetrics {
    static let baseRowHeight: CGFloat = 24

    static func scale(
        for rowHeight: CGFloat
    ) -> CGFloat {
        max(
            1,
            rowHeight / baseRowHeight
        )
    }

    static func gutterWidth(
        for rowHeight: CGFloat
    ) -> CGFloat {
        50 * scale(for: rowHeight)
    }

    static func contentWidth(
        maximumColumnCount: Int,
        rowHeight: CGFloat
    ) -> CGFloat {
        let scale = scale(for: rowHeight)
        let estimated =
            CGFloat(maximumColumnCount)
                * 8 * scale
                + 124 * scale
        return min(
            max(estimated, 520 * scale),
            8_000
        )
    }
}

struct GitLabDiffCollectionView: UIViewRepresentable {
    let document: GitLabParsedDiffDocument
    let documentID:
        GitLabDiffDocumentID
    let selectedHunkJump: GitLabDiffHunkJump?
    let rowHeight: CGFloat
    let contentWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            document: document,
            documentID: documentID
        )
    }

    func makeUIView(
        context: Context
    ) -> UICollectionView {
        let layout = GitLabDiffCollectionViewLayout()
        layout.configure(
            itemCount: document.items.count,
            rowHeight: rowHeight,
            contentWidth: contentWidth
        )

        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.backgroundColor =
            .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.alwaysBounceHorizontal = true
        collectionView.showsVerticalScrollIndicator =
            true
        collectionView.showsHorizontalScrollIndicator =
            true
        collectionView.contentInsetAdjustmentBehavior =
            .never
        collectionView.dataSource =
            context.coordinator
        collectionView.register(
            GitLabDiffCollectionViewCell.self,
            forCellWithReuseIdentifier:
                GitLabDiffCollectionViewCell
                    .reuseIdentifier
        )
        collectionView.accessibilityIdentifier =
            "mergeRequestDiffs.document"
        context.coordinator.collectionView =
            collectionView
        return collectionView
    }

    func updateUIView(
        _ collectionView: UICollectionView,
        context: Context
    ) {
        guard
            let layout =
                collectionView.collectionViewLayout
                    as?
                    GitLabDiffCollectionViewLayout
        else {
            return
        }

        let didReplaceDocument =
            context.coordinator.update(
                document: document,
                documentID: documentID
            )
        let didChangeLayout = layout.configure(
            itemCount: document.items.count,
            rowHeight: rowHeight,
            contentWidth: contentWidth
        )

        if didReplaceDocument || didChangeLayout {
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            context.coordinator.resetScrollPosition()
        }

        context.coordinator.apply(
            selectedHunkJump
        )
    }

    @MainActor
    final class Coordinator:
        NSObject,
        UICollectionViewDataSource
    {
        fileprivate weak var collectionView:
            UICollectionView?

        private var document:
            GitLabParsedDiffDocument
        private var documentID:
            GitLabDiffDocumentID
        private var lastHunkJumpID: UUID?

        init(
            document: GitLabParsedDiffDocument,
            documentID:
                GitLabDiffDocumentID
        ) {
            self.document = document
            self.documentID = documentID
        }

        func collectionView(
            _ collectionView: UICollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            document.items.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard
                let cell = collectionView
                    .dequeueReusableCell(
                        withReuseIdentifier:
                            GitLabDiffCollectionViewCell
                                .reuseIdentifier,
                        for: indexPath
                    ) as?
                    GitLabDiffCollectionViewCell,
                document.items.indices.contains(
                    indexPath.item
                )
            else {
                return UICollectionViewCell()
            }

            cell.configure(
                with:
                    document.items[
                        indexPath.item
                    ]
            )
            return cell
        }

        fileprivate func update(
            document:
                GitLabParsedDiffDocument,
            documentID:
                GitLabDiffDocumentID
        ) -> Bool {
            let didReplace =
                self.documentID != documentID
            self.document = document
            self.documentID = documentID
            if didReplace {
                lastHunkJumpID = nil
            }
            return didReplace
        }

        fileprivate func apply(
            _ jump: GitLabDiffHunkJump?
        ) {
            guard
                let jump,
                jump.id != lastHunkJumpID
            else {
                return
            }
            lastHunkJumpID = jump.id

            guard
                let hunk = document.hunks.first(
                    where: {
                        $0.ordinal == jump.ordinal
                    }
                )
            else {
                return
            }
            scrollToItem(hunk.renderItemIndex)
        }

        fileprivate func resetScrollPosition() {
            guard let collectionView else {
                return
            }
            lastHunkJumpID = nil
            collectionView.setContentOffset(
                CGPoint(
                    x:
                        -collectionView
                            .adjustedContentInset.left,
                    y:
                        -collectionView
                            .adjustedContentInset.top
                ),
                animated: false
            )
        }

        private func scrollToItem(
            _ itemIndex: Int
        ) {
            guard
                let collectionView,
                let layout =
                    collectionView
                        .collectionViewLayout
                        as?
                        GitLabDiffCollectionViewLayout
            else {
                return
            }

            collectionView.layoutIfNeeded()
            let maximumY = max(
                -collectionView
                    .adjustedContentInset.top,
                layout.collectionViewContentSize.height
                    - collectionView.bounds.height
                    + collectionView
                        .adjustedContentInset.bottom
            )
            let targetY = min(
                max(
                    CGFloat(itemIndex)
                        * layout.rowHeight
                        - collectionView
                            .adjustedContentInset.top,
                    -collectionView
                        .adjustedContentInset.top
                ),
                maximumY
            )
            collectionView.setContentOffset(
                CGPoint(
                    x:
                        -collectionView
                            .adjustedContentInset.left,
                    y: targetY
                ),
                animated: false
            )
        }
    }
}

@MainActor
private final class GitLabDiffCollectionViewLayout:
    UICollectionViewLayout
{
    private(set) var rowHeight =
        GitLabDiffLayoutMetrics.baseRowHeight
    private var itemCount = 0
    private var requestedContentWidth: CGFloat = 520

    @discardableResult
    func configure(
        itemCount: Int,
        rowHeight: CGFloat,
        contentWidth: CGFloat
    ) -> Bool {
        let normalizedRowHeight = max(
            1,
            rowHeight
        )
        let normalizedContentWidth = max(
            1,
            contentWidth
        )
        guard
            self.itemCount != itemCount
                || self.rowHeight
                    != normalizedRowHeight
                || requestedContentWidth
                    != normalizedContentWidth
        else {
            return false
        }

        self.itemCount = itemCount
        self.rowHeight = normalizedRowHeight
        requestedContentWidth =
            normalizedContentWidth
        invalidateLayout()
        return true
    }

    override var collectionViewContentSize:
        CGSize
    {
        let bounds = collectionView?.bounds ?? .zero
        let rowsHeight =
            CGFloat(itemCount) * rowHeight
        let trailingScrollAllowance = max(
            0,
            bounds.height - rowHeight
        )
        return CGSize(
            width: max(
                bounds.width,
                requestedContentWidth
            ),
            height: max(
                bounds.height,
                rowsHeight
                    + trailingScrollAllowance
            )
        )
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        guard
            itemCount > 0,
            rowHeight > 0
        else {
            return []
        }

        let first = max(
            0,
            Int(floor(rect.minY / rowHeight))
        )
        let last = min(
            itemCount - 1,
            Int(floor(
                max(
                    rect.minY,
                    rect.maxY - 1
                ) / rowHeight
            ))
        )
        guard first <= last else {
            return []
        }

        return (first...last).map {
            attributes(forItem: $0)
        }
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
        return attributes(
            forItem: indexPath.item
        )
    }

    override func shouldInvalidateLayout(
        forBoundsChange newBounds: CGRect
    ) -> Bool {
        guard let collectionView else {
            return false
        }
        return newBounds.size
            != collectionView.bounds.size
    }

    private func attributes(
        forItem item: Int
    ) -> UICollectionViewLayoutAttributes {
        let attributes =
            UICollectionViewLayoutAttributes(
                forCellWith:
                    IndexPath(
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
private final class GitLabDiffCollectionViewCell:
    UICollectionViewCell
{
    static let reuseIdentifier =
        "GitLabDiffCollectionViewCell"

    private let oldLineLabel = UILabel()
    private let newLineLabel = UILabel()
    private let textView = UITextView()
    private var showsLineNumbers = true

    override init(frame: CGRect) {
        super.init(frame: frame)

        oldLineLabel.textAlignment = .right
        newLineLabel.textAlignment = .right
        oldLineLabel.textColor = .secondaryLabel
        newLineLabel.textColor = .secondaryLabel
        oldLineLabel.adjustsFontForContentSizeCategory =
            true
        newLineLabel.adjustsFontForContentSizeCategory =
            true
        oldLineLabel.backgroundColor =
            .secondarySystemBackground
        newLineLabel.backgroundColor =
            .secondarySystemBackground

        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.maximumNumberOfLines = 1
        textView.textContainer.lineBreakMode = .byClipping
        textView.adjustsFontForContentSizeCategory = true

        contentView.addSubview(oldLineLabel)
        contentView.addSubview(newLineLabel)
        contentView.addSubview(textView)
        isAccessibilityElement = true
        oldLineLabel.isAccessibilityElement = false
        newLineLabel.isAccessibilityElement = false
        textView.isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        oldLineLabel.text = nil
        newLineLabel.text = nil
        textView.text = nil
        accessibilityLabel = nil
        contentView.backgroundColor = .clear
        showsLineNumbers = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gutterWidth =
            GitLabDiffLayoutMetrics.gutterWidth(
                for: bounds.height
            )

        if showsLineNumbers {
            oldLineLabel.frame = CGRect(
                x: 0,
                y: 0,
                width: gutterWidth,
                height: bounds.height
            )
            newLineLabel.frame = CGRect(
                x: gutterWidth,
                y: 0,
                width: gutterWidth,
                height: bounds.height
            )
            textView.frame = CGRect(
                x: gutterWidth * 2 + 8,
                y: 0,
                width: max(
                    0,
                    bounds.width
                        - gutterWidth * 2 - 24
                ),
                height: bounds.height
            )
        } else {
            oldLineLabel.frame = .zero
            newLineLabel.frame = .zero
            textView.frame = CGRect(
                x: 12,
                y: 0,
                width: max(
                    0,
                    bounds.width - 24
                ),
                height: bounds.height
            )
        }
    }

    func configure(
        with item: GitLabDiffRenderItem
    ) {
        let font = UIFontMetrics(
            forTextStyle: .caption1
        )
        .scaledFont(
            for:
                UIFont.monospacedSystemFont(
                    ofSize: 12,
                    weight: .regular
                ),
            compatibleWith: traitCollection
        )
        oldLineLabel.font = font
        newLineLabel.font = font
        textView.font = font
        textView.textColor = .label
        textView.tintColor = .systemOrange
        showsLineNumbers = item.line != nil

        switch item {
        case let .context(line):
            configure(
                line,
                prefix: " ",
                backgroundColor: .clear
            )
        case let .addition(line):
            configure(
                line,
                prefix: "+",
                backgroundColor:
                    UIColor.systemGreen
                        .withAlphaComponent(0.12)
            )
        case let .deletion(line):
            configure(
                line,
                prefix: "-",
                backgroundColor:
                    UIColor.systemRed
                        .withAlphaComponent(0.12)
            )
        case let .hunkHeader(_, text):
            configureSpecial(
                text,
                textColor: .systemBlue,
                backgroundColor:
                    UIColor.systemBlue
                        .withAlphaComponent(0.1),
                accessibilityLabel:
                    "Diff hunk, \(text)"
            )
        case let .noNewlineMarker(text):
            configureSpecial(
                text,
                textColor: .secondaryLabel,
                backgroundColor:
                    .secondarySystemBackground,
                accessibilityLabel: text
            )
        case let .fileMetadata(text):
            configureSpecial(
                text,
                textColor: .secondaryLabel,
                backgroundColor:
                    .secondarySystemBackground,
                accessibilityLabel:
                    "File metadata, \(text)"
            )
        }
        setNeedsLayout()
    }

    private func configure(
        _ line: GitLabDiffLine,
        prefix: String,
        backgroundColor: UIColor
    ) {
        oldLineLabel.text =
            line.oldLineNumber.map(String.init)
        newLineLabel.text =
            line.newLineNumber.map(String.init)
        textView.text = prefix + line.text
        contentView.backgroundColor =
            backgroundColor
        accessibilityLabel =
            Self.accessibilityLabel(line)
    }

    private func configureSpecial(
        _ text: String,
        textColor: UIColor,
        backgroundColor: UIColor,
        accessibilityLabel: String
    ) {
        oldLineLabel.text = nil
        newLineLabel.text = nil
        textView.text = text
        textView.textColor = textColor
        contentView.backgroundColor =
            backgroundColor
        self.accessibilityLabel =
            accessibilityLabel
    }

    private static func accessibilityLabel(
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
