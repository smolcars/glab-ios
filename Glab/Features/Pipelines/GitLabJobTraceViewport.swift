import Foundation
import Observation

nonisolated enum GitLabJobTraceViewportWindow {
    static let maximumLineCount =
        GitLabJobTraceDocument
        .maximumVisibleWindowLineCount

    static func range(
        around index: Int,
        lineCount: Int
    ) -> Range<Int> {
        guard
            lineCount > 0,
            index >= 0,
            index < lineCount
        else {
            return 0..<0
        }

        let count = min(
            lineCount,
            maximumLineCount
        )
        let centeredLowerBound =
            index - count / 2
        let lowerBound = min(
            max(0, centeredLowerBound),
            lineCount - count
        )
        return Range(
            uncheckedBounds: (
                lower: lowerBound,
                upper: lowerBound + count
            )
        )
    }
}

nonisolated enum GitLabJobTraceLayoutMetrics {
    static let horizontalPadding: CGFloat =
        16
    static let minimumTextColumnWidth:
        CGFloat = 320
    static let maximumContentWidth:
        CGFloat = 8_000

    static func contentWidth(
        renderedByteCount: Int,
        glyphWidth: CGFloat,
        lineCount: Int
    ) -> CGFloat {
        let boundedByteCount = min(
            max(0, renderedByteCount),
            GitLabJobTraceIndexer
                .maximumRenderedLineByteCount
        )
        let digitCount = max(
            1,
            String(
                max(1, lineCount)
            ).count
        )
        let gutterWidth =
            CGFloat(digitCount + 2)
            * max(1, glyphWidth)
        let textWidth = max(
            minimumTextColumnWidth,
            CGFloat(boundedByteCount)
                * max(1, glyphWidth)
        )
        return min(
            gutterWidth
                + horizontalPadding
                + textWidth,
            maximumContentWidth
        )
    }
}

nonisolated enum GitLabJobTraceAccessibility {
    static let maximumLabelCharacterCount =
        512

    static func label(
        for line: GitLabJobTraceLine
    ) -> String {
        let text =
            String(
                line.text.prefix(
                    maximumLabelCharacterCount
                )
            )
        var label =
            "Line \(line.displayNumber), \(text)"
        if
            line.isTruncated
                || line.text.count
                    > maximumLabelCharacterCount
        {
            label += ", truncated"
        }
        return label
    }
}

@MainActor
@Observable
final class GitLabJobTraceViewport {
    private(set) var loadedRange:
        Range<Int> = 0..<0
    private(set) var error:
        GitLabJobTraceDocumentError?
    private(set) var maximumRenderedByteCount =
        0

    @ObservationIgnored
    private let document:
        GitLabJobTraceDocument
    @ObservationIgnored
    private var linesByIndex:
        [Int: GitLabJobTraceLine] = [:]
    @ObservationIgnored
    private var operation:
        LoadOperation?

    private struct LoadOperation {
        let id: UUID
        let range: Range<Int>
        let task:
            Task<
                Result<
                    [GitLabJobTraceLine],
                    GitLabJobTraceDocumentError
                >,
                Never
            >
    }

    init(document: GitLabJobTraceDocument) {
        self.document = document
    }

    var lineCount: Int {
        document.lineCount
    }

    var loadedLineCount: Int {
        linesByIndex.count
    }

    func line(
        at index: Int
    ) -> GitLabJobTraceLine? {
        linesByIndex[index]
    }

    func load(around index: Int) async {
        guard
            index >= 0,
            index < lineCount
        else {
            return
        }
        if
            loadedRange.contains(index),
            linesByIndex[index] != nil
        {
            return
        }

        if
            let operation,
            operation.range.contains(index)
        {
            await publish(
                operation,
                result:
                    await operation.task.value
            )
            return
        }

        operation?.task.cancel()
        let range =
            GitLabJobTraceViewportWindow
            .range(
                around: index,
                lineCount: lineCount
            )
        let id = UUID()
        let document = document
        let task:
            Task<
                Result<
                    [GitLabJobTraceLine],
                    GitLabJobTraceDocumentError
                >,
                Never
            > = Task {
            do {
                return Result.success(
                    try await document.lines(
                        in: range
                    )
                )
            } catch
                let error as
                    GitLabJobTraceDocumentError
            {
                return Result.failure(
                    error
                )
            } catch is CancellationError {
                return Result.failure(
                    .invalidRange
                )
            } catch {
                return Result.failure(
                    .invalidFile
                )
            }
        }
        let operation = LoadOperation(
            id: id,
            range: range,
            task: task
        )
        self.operation = operation
        await publish(
            operation,
            result: await task.value
        )
    }

    func cancel() {
        operation?.task.cancel()
        operation = nil
        loadedRange = 0..<0
        linesByIndex.removeAll(
            keepingCapacity: false
        )
        maximumRenderedByteCount = 0
        error = nil
    }

    private func publish(
        _ completedOperation:
            LoadOperation,
        result:
            Result<
                [GitLabJobTraceLine],
                GitLabJobTraceDocumentError
            >
    ) async {
        guard
            operation?.id
                == completedOperation.id
        else {
            return
        }
        operation = nil
        guard !Task.isCancelled else {
            return
        }

        switch result {
        case let .success(lines):
            guard
                lines.count
                    == completedOperation
                    .range.count,
                zip(
                    completedOperation.range,
                    lines
                ).allSatisfy({
                    $0 == $1.index
                })
            else {
                error = .invalidFile
                return
            }
            linesByIndex =
                Dictionary(
                    uniqueKeysWithValues:
                        lines.map {
                            ($0.index, $0)
                        }
                )
            loadedRange =
                completedOperation.range
            maximumRenderedByteCount =
                max(
                    maximumRenderedByteCount,
                    lines.map {
                        $0.text.utf8.count
                    }.max() ?? 0
                )
            error = nil
        case let .failure(error):
            guard
                !completedOperation
                .task.isCancelled
            else {
                return
            }
            self.error = error
        }
    }
}
