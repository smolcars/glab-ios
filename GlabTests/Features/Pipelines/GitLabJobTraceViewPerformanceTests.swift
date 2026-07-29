import Darwin.Mach
import QuartzCore
import SwiftUI
import Testing
import UIKit
@testable import Glab

@Suite(
    "GitLab job trace view performance",
    .serialized
)
@MainActor
struct GitLabJobTraceViewPerformanceTests {
    @Test("Meets the fifty-thousand-line collection-view renderer budgets")
    func rendererBudgets() async throws {
        try await prewarm()

        let baseline =
            try residentMemoryBytes()
        let fixture =
            try makeFixture(
                lineCount: 50_000
            )
        let host =
            try JobTraceRendererHost(
                document:
                    fixture.document
            )
        defer {
            host.tearDown()
        }
        let scrollView =
            try await host.prepare()
        let visibleMemory =
            try residentMemoryBytes()
        let memoryDelta =
            visibleMemory > baseline
            ? visibleMemory - baseline
            : 0
        let measurement =
            await JobTraceScrollDriver(
                scrollView: scrollView,
                frameCount: 600,
                rowHeight: 22
            )
            .run()
        let cacheMetrics =
            await fixture.document
            .cacheMetrics()

        let report =
            "JOB_TRACE_RENDERER_PERFORMANCE "
                + "scroll_work_p95_ms="
                + format(
                    measurement.workP95
                )
                + " scroll_work_max_ms="
                + format(
                    measurement
                    .maximumWork
                )
                + " scroll_hitch_ratio="
                + format(
                    measurement.hitchRatio
                )
                + " scroll_max_frame_ms="
                + format(
                    measurement.maximumFrame
                )
                + " memory_delta_mib="
                + format(
                    mebibytes(memoryDelta)
                )
                + " decoded_cache_lines="
                + String(
                    cacheMetrics.lineCount
                )
                + " decoded_cache_bytes="
                + String(
                    cacheMetrics.byteCount
                )
        print(report)
        Attachment.record(
            report,
            named:
                "job-trace-renderer-performance.txt"
        )

        #expect(
            cacheMetrics.lineCount <= 2_000
        )
        #expect(
            cacheMetrics.byteCount
                <= 8 * 1_024 * 1_024
        )
        #if !DEBUG
            #expect(
                measurement.workP95 < 8
            )
            #expect(
                measurement.maximumWork
                    < 16.67
            )
            #expect(
                measurement.hitchRatio
                    <= 0.05
            )
        #endif
    }

    private func prewarm() async throws {
        let fixture =
            try makeFixture(
                lineCount: 1_000
            )
        let host =
            try JobTraceRendererHost(
                document:
                    fixture.document
            )
        _ = try await host.prepare()
        host.tearDown()
    }

    private func makeFixture(
        lineCount: Int
    ) throws -> (
        document: GitLabJobTraceDocument,
        reader: JobTracePerformanceReader
    ) {
        let accountID =
            GitLabAccountID(
                host:
                    try GitLabHost(
                        "gitlab.example.com"
                    ),
                userID: 7
            )
        let route = try #require(
            GitLabJobTraceRoute(
                projectID: 42,
                jobID: 800
            )
        )
        let descriptor =
            GitLabJobTraceDescriptor(
                key:
                    GitLabJobTraceKey(
                        accountID:
                            accountID,
                        route: route
                    ),
                traceFileURL:
                    URL(
                        filePath:
                            "/tmp/renderer.raw"
                    ),
                indexFileURL:
                    URL(
                        filePath:
                            "/tmp/renderer.idx"
                    ),
                byteCount:
                    lineCount * 80,
                lineCount: lineCount,
                storedAt:
                    Date(
                        timeIntervalSince1970:
                            1_000
                    ),
                rawContentDigest:
                    "renderer-\(lineCount)",
                longLineCount: 0
            )
        let reader =
            JobTracePerformanceReader()
        return (
            GitLabJobTraceDocument(
                descriptor: descriptor,
                reader: reader
            ),
            reader
        )
    }

    private func residentMemoryBytes()
        throws -> UInt64
    {
        var info =
            mach_task_basic_info_data_t()
        var count =
            mach_msg_type_number_t(
                MemoryLayout.size(
                    ofValue: info
                )
                / MemoryLayout<natural_t>
                    .size
            )
        let result =
            withUnsafeMutablePointer(
                to: &info
            ) { pointer in
                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity: Int(count)
                ) { reboundPointer in
                    task_info(
                        mach_task_self_,
                        task_flavor_t(
                            MACH_TASK_BASIC_INFO
                        ),
                        reboundPointer,
                        &count
                    )
                }
            }
        guard result == KERN_SUCCESS else {
            throw
                JobTracePerformanceError
                .taskInfo(result)
        }
        return UInt64(info.resident_size)
    }

    private func mebibytes(
        _ bytes: UInt64
    ) -> Double {
        Double(bytes)
            / Double(1_024 * 1_024)
    }

    private func format(
        _ value: Double
    ) -> String {
        value.formatted(
            .number.precision(
                .fractionLength(3)
            )
        )
    }
}

private actor JobTracePerformanceReader:
    GitLabJobTraceReading
{
    func lines(
        in range: Range<Int>,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) async throws
        -> [GitLabJobTraceLine]
    {
        try Task.checkCancellation()
        return range.map { index in
            let text =
                "step \(index) "
                + "compile Sources/Feature\(index % 97).swift "
                + "--configuration release"
            return GitLabJobTraceLine(
                index: index,
                text: text,
                rawByteCount:
                    text.utf8.count,
                isTruncated: false
            )
        }
    }

    func search(
        _ query: String,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int,
        maximumResultCount: Int
    ) async throws
        -> GitLabJobTraceSearchResult
    {
        .empty
    }
}

@MainActor
private final class JobTraceRendererHost {
    let window: UIWindow
    let controller:
        UIHostingController<
            GitLabJobTraceLineSurface
        >

    init(
        document:
            GitLabJobTraceDocument
    ) throws {
        controller =
            UIHostingController(
                rootView:
                    GitLabJobTraceLineSurface(
                        document: document,
                        selectedLineIndex:
                            nil,
                        jump: nil
                    )
            )
        guard
            let windowScene =
                UIApplication.shared
                .connectedScenes
                .compactMap({
                    $0 as? UIWindowScene
                })
                .first
        else {
            throw
                JobTracePerformanceError
                .missingWindowScene
        }
        window = UIWindow(
            windowScene: windowScene
        )
        window.frame = CGRect(
            x: 0,
            y: 0,
            width: 402,
            height: 874
        )
        window.rootViewController =
            controller
        controller.loadViewIfNeeded()
        controller.view.frame =
            window.bounds
        window.makeKeyAndVisible()
    }

    func prepare()
        async throws -> UIScrollView
    {
        for _ in 0..<20 {
            controller.view
                .setNeedsLayout()
            controller.view
                .layoutIfNeeded()
            CATransaction.flush()
            await Task.yield()
        }
        guard
            let scrollView =
                Self.scrollView(
                    in: controller.view
                ),
            scrollView.contentSize.height
                > scrollView.bounds.height
        else {
            throw
                JobTracePerformanceError
                .missingScrollView
        }
        return scrollView
    }

    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private static func scrollView(
        in view: UIView
    ) -> UIScrollView? {
        if let scrollView =
            view as? UIScrollView
        {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView =
                scrollView(in: subview)
            {
                return scrollView
            }
        }
        return nil
    }
}

private struct JobTraceScrollMeasurement {
    let workP95: Double
    let maximumWork: Double
    let hitchRatio: Double
    let maximumFrame: Double
}

@MainActor
private final class JobTraceScrollDriver:
    NSObject
{
    private let scrollView: UIScrollView
    private let frameCount: Int
    private let scrollDistance: CGFloat
    private let clock = ContinuousClock()

    private var displayLink:
        CADisplayLink?
    private var continuation:
        CheckedContinuation<
            JobTraceScrollMeasurement,
            Never
        >?
    private var completedFrames = 0
    private var previousTimestamp:
        CFTimeInterval?
    private var workSamples: [Double] = []
    private var frameSamples: [Double] = []
    private var expectedFrameSamples:
        [Double] = []

    init(
        scrollView: UIScrollView,
        frameCount: Int,
        rowHeight: CGFloat
    ) {
        self.scrollView = scrollView
        self.frameCount = frameCount
        let maximumOffset = max(
            0,
            scrollView.contentSize.height
                - scrollView.bounds.height
        )
        scrollDistance = min(
            maximumOffset,
            max(1, rowHeight)
                * 4
                * CGFloat(frameCount)
        )
        super.init()
        workSamples.reserveCapacity(
            frameCount
        )
        frameSamples.reserveCapacity(
            frameCount - 1
        )
        expectedFrameSamples
            .reserveCapacity(
                frameCount - 1
            )
    }

    func run()
        async -> JobTraceScrollMeasurement
    {
        await withCheckedContinuation {
            continuation in
            self.continuation =
                continuation
            let displayLink =
                CADisplayLink(
                    target: self,
                    selector:
                        #selector(step)
                )
            displayLink
                .preferredFrameRateRange =
                CAFrameRateRange(
                    minimum: 60,
                    maximum: 60,
                    preferred: 60
                )
            displayLink.add(
                to: .main,
                forMode: .common
            )
            self.displayLink =
                displayLink
        }
    }

    @objc
    private func step(
        _ displayLink: CADisplayLink
    ) {
        if let previousTimestamp {
            frameSamples.append(
                (
                    displayLink.timestamp
                        - previousTimestamp
                ) * 1_000
            )
            expectedFrameSamples.append(
                max(
                    1,
                    (
                        displayLink
                            .targetTimestamp
                            - displayLink
                            .timestamp
                    ) * 1_000
                )
            )
        }
        previousTimestamp =
            displayLink.timestamp

        completedFrames += 1
        let progress =
            CGFloat(completedFrames)
            / CGFloat(frameCount)
        let workStart = clock.now
        scrollView.setContentOffset(
            CGPoint(
                x: 0,
                y:
                    scrollDistance
                    * progress
            ),
            animated: false
        )
        scrollView.layoutIfNeeded()
        CATransaction.flush()
        workSamples.append(
            Self.milliseconds(
                workStart.duration(
                    to: clock.now
                )
            )
        )

        guard
            completedFrames >= frameCount
        else {
            return
        }
        finish()
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        let expectedTime =
            expectedFrameSamples
            .reduce(0, +)
        let overBudgetTime =
            zip(
                frameSamples,
                expectedFrameSamples
            )
            .reduce(0) {
                result,
                pair in
                result + max(
                    0,
                    pair.0 - pair.1
                )
            }
        continuation?.resume(
            returning:
                JobTraceScrollMeasurement(
                    workP95:
                        Self.percentile95(
                            workSamples
                        ),
                    maximumWork:
                        workSamples.max()
                        ?? 0,
                    hitchRatio:
                        expectedTime > 0
                        ? overBudgetTime
                            / expectedTime
                        : 0,
                    maximumFrame:
                        frameSamples.max()
                        ?? 0
                )
        )
        continuation = nil
    }

    private static func percentile95(
        _ samples: [Double]
    ) -> Double {
        let sorted = samples.sorted()
        let index = min(
            sorted.count - 1,
            Int(
                ceil(
                    Double(sorted.count)
                        * 0.95
                )
            ) - 1
        )
        return sorted[index]
    }

    private static func milliseconds(
        _ duration: Duration
    ) -> Double {
        let components = duration.components
        return
            Double(components.seconds)
                * 1_000
            + Double(components.attoseconds)
                / 1_000_000_000_000_000
    }
}

private enum JobTracePerformanceError:
    Error
{
    case missingWindowScene
    case missingScrollView
    case taskInfo(kern_return_t)
}
