import SwiftUI
import UIKit

struct GitLabJobTraceCollectionView:
    UIViewRepresentable
{
    let document:
        GitLabJobTraceDocument
    let selectedLineIndex: Int?
    let jump: GitLabJobTraceJump?
    let rowHeight: CGFloat
    let glyphWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            document: document,
            selectedLineIndex:
                selectedLineIndex
        )
    }

    func makeUIView(
        context: Context
    ) -> UICollectionView {
        let layout =
            GitLabJobTraceCollectionViewLayout()
        layout.configure(
            itemCount:
                document.lineCount,
            rowHeight: rowHeight,
            contentWidth:
                GitLabJobTraceLayoutMetrics
                .contentWidth(
                    renderedByteCount: 0,
                    glyphWidth: glyphWidth,
                    lineCount:
                        document.lineCount
                )
        )

        let collectionView =
            UICollectionView(
                frame: .zero,
                collectionViewLayout: layout
            )
        collectionView.backgroundColor =
            .systemBackground
        collectionView.alwaysBounceVertical =
            true
        collectionView.alwaysBounceHorizontal =
            true
        collectionView.showsVerticalScrollIndicator =
            true
        collectionView.showsHorizontalScrollIndicator =
            true
        collectionView
            .contentInsetAdjustmentBehavior =
            .never
        collectionView.dataSource =
            context.coordinator
        collectionView.delegate =
            context.coordinator
        collectionView.prefetchDataSource =
            context.coordinator
        collectionView.register(
            GitLabJobTraceCollectionViewCell
                .self,
            forCellWithReuseIdentifier:
                GitLabJobTraceCollectionViewCell
                .reuseIdentifier
        )
        collectionView
            .accessibilityIdentifier =
            "jobTrace.collection"
        context.coordinator.attach(
            collectionView,
            rowHeight: rowHeight,
            glyphWidth: glyphWidth
        )
        return collectionView
    }

    func updateUIView(
        _ collectionView: UICollectionView,
        context: Context
    ) {
        context.coordinator.update(
            document: document,
            selectedLineIndex:
                selectedLineIndex,
            rowHeight: rowHeight,
            glyphWidth: glyphWidth
        )
        context.coordinator.apply(jump)
    }

    static func dismantleUIView(
        _ collectionView:
            UICollectionView,
        coordinator: Coordinator
    ) {
        coordinator.cancel()
        collectionView.dataSource = nil
        collectionView.delegate = nil
        collectionView
            .prefetchDataSource = nil
    }

    @MainActor
    final class Coordinator:
        NSObject,
        UICollectionViewDataSource,
        UICollectionViewDelegate,
        UICollectionViewDataSourcePrefetching
    {
        private weak var collectionView:
            UICollectionView?
        private var document:
            GitLabJobTraceDocument
        private var viewport:
            GitLabJobTraceViewport
        private var selectedLineIndex:
            Int?
        private var rowHeight: CGFloat = 22
        private var glyphWidth: CGFloat = 7.6
        private var lastJumpID: UUID?
        private var loadTask:
            Task<Void, Never>?
        private var requestedRange:
            Range<Int> = 0..<0
        private let errorLabel =
            UILabel()

        init(
            document:
                GitLabJobTraceDocument,
            selectedLineIndex: Int?
        ) {
            self.document = document
            viewport =
                GitLabJobTraceViewport(
                    document: document
            )
            self.selectedLineIndex =
                selectedLineIndex
        }

        func collectionView(
            _ collectionView:
                UICollectionView,
            numberOfItemsInSection
            section: Int
        ) -> Int {
            viewport.lineCount
        }

        func collectionView(
            _ collectionView:
                UICollectionView,
            cellForItemAt indexPath:
                IndexPath
        ) -> UICollectionViewCell {
            guard
                let cell =
                    collectionView
                    .dequeueReusableCell(
                        withReuseIdentifier:
                            GitLabJobTraceCollectionViewCell
                            .reuseIdentifier,
                        for: indexPath
                    ) as?
                    GitLabJobTraceCollectionViewCell
            else {
                return UICollectionViewCell()
            }

            let line =
                viewport.line(
                    at: indexPath.item
                )
            cell.configure(
                index: indexPath.item,
                line: line,
                isSelected:
                    selectedLineIndex
                    == indexPath.item,
                gutterWidth:
                    gutterWidth
            )
            if line == nil {
                requestLoad(
                    around:
                        indexPath.item
                )
            }
            return cell
        }

        func collectionView(
            _ collectionView:
                UICollectionView,
            prefetchItemsAt indexPaths:
                [IndexPath]
        ) {
            guard !indexPaths.isEmpty else {
                return
            }
            let middle =
                indexPaths[
                    indexPaths.count / 2
                ]
            requestLoad(
                around: middle.item
            )
        }

        func scrollViewDidScroll(
            _ scrollView: UIScrollView
        ) {
            guard
                viewport.lineCount > 0,
                rowHeight > 0
            else {
                return
            }
            let centerY =
                scrollView.contentOffset.y
                + scrollView.bounds.height
                    / 2
            let index = min(
                viewport.lineCount - 1,
                max(
                    0,
                    Int(
                        centerY
                            / rowHeight
                    )
                )
            )
            requestLoad(around: index)
            positionErrorLabel()
        }

        fileprivate func attach(
            _ collectionView:
                UICollectionView,
            rowHeight: CGFloat,
            glyphWidth: CGFloat
        ) {
            self.collectionView =
                collectionView
            self.rowHeight =
                max(1, rowHeight)
            self.glyphWidth =
                max(1, glyphWidth)
            configureErrorLabel()
            collectionView.addSubview(
                errorLabel
            )
            requestLoad(around: 0)
        }

        fileprivate func update(
            document:
                GitLabJobTraceDocument,
            selectedLineIndex: Int?,
            rowHeight: CGFloat,
            glyphWidth: CGFloat
        ) {
            let didReplaceDocument =
                ObjectIdentifier(
                    self.document
                )
                != ObjectIdentifier(document)
            let previousSelection =
                self.selectedLineIndex
            let normalizedRowHeight =
                max(1, rowHeight)
            let normalizedGlyphWidth =
                max(1, glyphWidth)
            let didChangeMetrics =
                self.rowHeight
                    != normalizedRowHeight
                || self.glyphWidth
                    != normalizedGlyphWidth

            self.selectedLineIndex =
                selectedLineIndex
            self.rowHeight =
                normalizedRowHeight
            self.glyphWidth =
                normalizedGlyphWidth

            if didReplaceDocument {
                replaceDocument(document)
                return
            }

            updateLayout()
            if didChangeMetrics {
                collectionView?.reloadData()
            } else if
                previousSelection
                    != selectedLineIndex
            {
                reloadVisibleLines(
                    at: [
                        previousSelection,
                        selectedLineIndex,
                    ]
                    .compactMap { $0 }
                )
            }
        }

        fileprivate func apply(
            _ jump: GitLabJobTraceJump?
        ) {
            guard
                let jump,
                jump.id != lastJumpID,
                jump.lineIndex >= 0,
                jump.lineIndex
                    < viewport.lineCount
            else {
                return
            }
            lastJumpID = jump.id
            loadTask?.cancel()
            let targetIndex =
                jump.lineIndex
            requestedRange =
                GitLabJobTraceViewportWindow
                .range(
                    around: targetIndex,
                    lineCount:
                        viewport.lineCount
                )
            loadTask = Task {
                await viewport.load(
                    around: targetIndex
                )
                guard
                    !Task.isCancelled
                else {
                    return
                }
                publishLoadedLines()
                scrollToLine(targetIndex)
            }
        }

        fileprivate func cancel() {
            loadTask?.cancel()
            loadTask = nil
            requestedRange = 0..<0
            viewport.cancel()
        }

        private func replaceDocument(
            _ document:
                GitLabJobTraceDocument
        ) {
            cancel()
            self.document = document
            viewport =
                GitLabJobTraceViewport(
                    document: document
                )
            lastJumpID = nil
            updateErrorLabel(nil)
            collectionView?.reloadData()
            updateLayout()
            collectionView?.setContentOffset(
                .zero,
                animated: false
            )
            requestLoad(around: 0)
        }

        private func requestLoad(
            around index: Int
        ) {
            guard
                index >= 0,
                index
                    < viewport.lineCount,
                viewport.line(at: index)
                    == nil
            else {
                return
            }
            if requestedRange.contains(
                index
            ) {
                return
            }

            loadTask?.cancel()
            requestedRange =
                GitLabJobTraceViewportWindow
                .range(
                    around: index,
                    lineCount:
                        viewport.lineCount
                )
            loadTask = Task {
                await viewport.load(
                    around: index
                )
                guard
                    !Task.isCancelled
                else {
                    return
                }
                publishLoadedLines()
            }
        }

        private func publishLoadedLines() {
            requestedRange = 0..<0
            updateLayout()
            updateErrorLabel(
                viewport.error
            )
            guard
                let collectionView
            else {
                return
            }
            let visible =
                collectionView
                .indexPathsForVisibleItems
                .filter {
                    viewport.loadedRange
                        .contains($0.item)
                }
            if !visible.isEmpty {
                collectionView
                    .reloadItems(
                        at: visible
                    )
            }
        }

        private func updateLayout() {
            guard
                let layout =
                    collectionView?
                    .collectionViewLayout
                    as?
                    GitLabJobTraceCollectionViewLayout
            else {
                return
            }
            _ = layout.configure(
                itemCount:
                    viewport.lineCount,
                rowHeight: rowHeight,
                contentWidth:
                    GitLabJobTraceLayoutMetrics
                    .contentWidth(
                        renderedByteCount:
                            viewport
                            .maximumRenderedByteCount,
                        glyphWidth:
                            glyphWidth,
                        lineCount:
                            viewport
                            .lineCount
                    )
            )
        }

        private var gutterWidth: CGFloat {
            let digitCount = max(
                1,
                String(
                    max(
                        1,
                        viewport.lineCount
                    )
                ).count
            )
            return CGFloat(
                digitCount + 2
            ) * glyphWidth
        }

        private func reloadVisibleLines(
            at indexes: [Int]
        ) {
            guard
                let collectionView
            else {
                return
            }
            let visible =
                Set(
                    collectionView
                    .indexPathsForVisibleItems
                    .map(\.item)
                )
            let indexPaths =
                indexes
                .filter(visible.contains)
                .map {
                    IndexPath(
                        item: $0,
                        section: 0
                    )
                }
            if !indexPaths.isEmpty {
                collectionView
                    .reloadItems(
                        at: indexPaths
                    )
            }
        }

        private func scrollToLine(
            _ index: Int
        ) {
            guard
                let collectionView,
                let layout =
                    collectionView
                    .collectionViewLayout
                    as?
                    GitLabJobTraceCollectionViewLayout
            else {
                return
            }
            collectionView.layoutIfNeeded()
            let targetY =
                CGFloat(index)
                * layout.rowHeight
                - (
                    collectionView
                    .bounds.height
                    - layout.rowHeight
                ) / 2
            let maximumY = max(
                0,
                layout
                    .collectionViewContentSize
                    .height
                    - collectionView
                    .bounds.height
            )
            collectionView.setContentOffset(
                CGPoint(
                    x:
                        collectionView
                        .contentOffset.x,
                    y:
                        min(
                            max(0, targetY),
                            maximumY
                        )
                ),
                animated: false
            )
        }

        private func configureErrorLabel() {
            errorLabel.font =
                .preferredFont(
                    forTextStyle:
                        .caption1
                )
            errorLabel
                .adjustsFontForContentSizeCategory =
                true
            errorLabel.textColor =
                .systemOrange
            errorLabel.backgroundColor =
                .secondarySystemBackground
            errorLabel.textAlignment =
                .center
            errorLabel.numberOfLines = 2
            errorLabel.layer.cornerRadius =
                13
            errorLabel.layer.masksToBounds =
                true
            errorLabel.isHidden = true
            errorLabel
                .accessibilityIdentifier =
                "jobTrace.lineError"
        }

        private func updateErrorLabel(
            _ error:
                GitLabJobTraceDocumentError?
        ) {
            errorLabel.text =
                error?.description
            errorLabel.isHidden =
                error == nil
            positionErrorLabel()
        }

        private func positionErrorLabel() {
            guard
                !errorLabel.isHidden,
                let collectionView
            else {
                return
            }
            let availableWidth = max(
                1,
                collectionView
                    .bounds.width - 20
            )
            let fittingSize =
                errorLabel.sizeThatFits(
                    CGSize(
                        width:
                            availableWidth
                            - 20,
                        height:
                            .greatestFiniteMagnitude
                    )
                )
            let width = min(
                availableWidth,
                fittingSize.width + 20
            )
            let height = max(
                26,
                fittingSize.height + 10
            )
            errorLabel.frame = CGRect(
                x:
                    collectionView
                    .contentOffset.x
                    + (
                        collectionView
                            .bounds.width
                        - width
                    ) / 2,
                y:
                    collectionView
                    .contentOffset.y
                    + 6,
                width: width,
                height: height
            )
        }
    }
}

@MainActor
private final class
GitLabJobTraceCollectionViewLayout:
    UICollectionViewLayout
{
    private(set) var rowHeight:
        CGFloat = 22
    private var itemCount = 0
    private var requestedContentWidth:
        CGFloat = 320

    @discardableResult
    func configure(
        itemCount: Int,
        rowHeight: CGFloat,
        contentWidth: CGFloat
    ) -> Bool {
        let itemCount = max(
            0,
            itemCount
        )
        let rowHeight = max(
            1,
            rowHeight
        )
        let contentWidth = max(
            1,
            contentWidth
        )
        guard
            self.itemCount != itemCount
                || self.rowHeight
                    != rowHeight
                || requestedContentWidth
                    != contentWidth
        else {
            return false
        }
        self.itemCount = itemCount
        self.rowHeight = rowHeight
        requestedContentWidth =
            contentWidth
        invalidateLayout()
        return true
    }

    override var collectionViewContentSize:
        CGSize
    {
        let bounds =
            collectionView?.bounds
            ?? .zero
        return CGSize(
            width: max(
                bounds.width,
                requestedContentWidth
            ),
            height: max(
                bounds.height,
                CGFloat(itemCount)
                    * rowHeight
            )
        )
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [
        UICollectionViewLayoutAttributes
    ]? {
        guard
            itemCount > 0,
            rowHeight > 0
        else {
            return []
        }
        let first = max(
            0,
            Int(
                floor(
                    rect.minY
                        / rowHeight
                )
            )
        )
        let last = min(
            itemCount - 1,
            Int(
                floor(
                    max(
                        rect.minY,
                        rect.maxY - 1
                    ) / rowHeight
                )
            )
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
            y:
                CGFloat(item)
                * rowHeight,
            width:
                collectionViewContentSize
                .width,
            height: rowHeight
        )
        return attributes
    }
}

@MainActor
private final class
GitLabJobTraceCollectionViewCell:
    UICollectionViewCell
{
    static let reuseIdentifier =
        "GitLabJobTraceCollectionViewCell"

    private let lineNumberLabel =
        UILabel()
    private let textLabel = UILabel()
    private var gutterWidth:
        CGFloat = 40

    override init(frame: CGRect) {
        super.init(frame: frame)

        lineNumberLabel
            .textAlignment = .right
        lineNumberLabel.textColor =
            .tertiaryLabel
        lineNumberLabel.backgroundColor =
            .secondarySystemBackground
        lineNumberLabel
            .adjustsFontForContentSizeCategory =
            true
        textLabel.textColor = .label
        textLabel.numberOfLines = 1
        textLabel.lineBreakMode =
            .byClipping
        textLabel
            .adjustsFontForContentSizeCategory =
            true

        contentView.addSubview(
            lineNumberLabel
        )
        contentView.addSubview(textLabel)
        isAccessibilityElement = true
        lineNumberLabel
            .isAccessibilityElement = false
        textLabel.isAccessibilityElement =
            false
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
        textLabel.text = nil
        accessibilityLabel = nil
        accessibilityTraits =
            .staticText
        contentView.backgroundColor =
            .clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        lineNumberLabel.frame = CGRect(
            x: 0,
            y: 0,
            width: gutterWidth,
            height: bounds.height
        )
        textLabel.frame = CGRect(
            x: gutterWidth + 8,
            y: 0,
            width: max(
                0,
                bounds.width
                    - gutterWidth
                    - 16
            ),
            height: bounds.height
        )
    }

    func configure(
        index: Int,
        line: GitLabJobTraceLine?,
        isSelected: Bool,
        gutterWidth: CGFloat
    ) {
        let font =
            UIFontMetrics(
                forTextStyle: .caption1
            )
            .scaledFont(
                for:
                    UIFont
                    .monospacedSystemFont(
                        ofSize: 12,
                        weight: .regular
                    ),
                compatibleWith:
                    traitCollection
            )
        lineNumberLabel.font = font
        textLabel.font = font
        self.gutterWidth =
            max(1, gutterWidth)
        lineNumberLabel.text =
            String(index + 1)
        textLabel.text = line?.text
        contentView.backgroundColor =
            isSelected
            ? UIColor.systemOrange
                .withAlphaComponent(0.18)
            : .clear
        accessibilityLabel =
            line.map {
                GitLabJobTraceAccessibility
                .label(for: $0)
            }
            ?? "Line \(index + 1), loading"
        accessibilityTraits =
            isSelected
            ? [.staticText, .selected]
            : .staticText
        setNeedsLayout()
    }
}
