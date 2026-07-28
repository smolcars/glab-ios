import Darwin.Mach
import SwiftUI
import Testing
import UIKit
@testable import Glab

@Suite(
    "GitLab diff collection performance",
    .serialized
)
@MainActor
struct GitLabDiffCollectionViewPerformanceTests {
    @Test("Meets optimized renderer budgets")
    func rendererBudgets() async throws {
        try await prewarmRenderer()

        let memoryDelta =
            try await fiftyThousandLineMemoryDelta()
        let tenThousand =
            try await firstInteractiveMeasurements(
                source:
                    GitLabUnifiedDiffFixtures
                    .tenThousandLines
            )
        let fiftyThousand =
            try await firstInteractiveMeasurements(
                source:
                    GitLabUnifiedDiffFixtures
                    .fiftyThousandLines
            )
        let scroll =
            try await deterministicScrollMeasurement()

        print(
            "DIFF_RENDERER_PERFORMANCE "
                + "10k_median_ms="
                + "\(format(tenThousand.median)) "
                + "10k_p95_ms="
                + "\(format(tenThousand.p95)) "
                + "50k_median_ms="
                + "\(format(fiftyThousand.median)) "
                + "50k_p95_ms="
                + "\(format(fiftyThousand.p95)) "
                + "50k_memory_mib="
                + "\(format(mebibytes(memoryDelta))) "
                + "scroll_work_p95_ms="
                + "\(format(scroll.workP95)) "
                + "scroll_hitch_ratio="
                + "\(format(scroll.hitchRatio)) "
                + "scroll_max_frame_ms="
                + "\(format(scroll.maximumFrame))"
        )

        #if !DEBUG
            #expect(tenThousand.p95 < 250)
            #expect(fiftyThousand.p95 < 500)
            #expect(
                memoryDelta
                    <= 100 * 1_024 * 1_024
            )
            #expect(scroll.hitchRatio <= 0.05)
            #expect(scroll.maximumFrame <= 250)
        #endif
    }

    private func prewarmRenderer() async throws {
        let document =
            try await GitLabUnifiedDiffParser.parse(
                GitLabUnifiedDiffFixtures
                    .oneThousandLines
            )
        let host = try RendererHost(
            document: document,
            documentID: try makeDocumentID()
        )
        let collectionView =
            try await host.prepare()
        #expect(!collectionView.visibleCells.isEmpty)
        host.tearDown()
    }

    private func fiftyThousandLineMemoryDelta()
        async throws -> UInt64
    {
        let source =
            GitLabUnifiedDiffFixtures
            .fiftyThousandLines
        let baseline = try residentMemoryBytes()
        let document =
            try await GitLabUnifiedDiffParser.parse(
                source
            )
        let host = try RendererHost(
            document: document,
            documentID: try makeDocumentID(),
            isVisible: true
        )
        let collectionView =
            try await host.prepare()
        #expect(!collectionView.visibleCells.isEmpty)
        let visibleMemory =
            try residentMemoryBytes()
        host.tearDown()
        return visibleMemory > baseline
            ? visibleMemory - baseline
            : 0
    }

    private func firstInteractiveMeasurements(
        source: String
    ) async throws -> PerformanceDistribution {
        var samples: [Double] = []
        samples.reserveCapacity(20)

        for _ in 0..<20 {
            let start = ContinuousClock.now
            let document =
                try await GitLabUnifiedDiffParser
                .parse(source)
            let host = try RendererHost(
                document: document,
                documentID:
                    try makeDocumentID()
            )
            let collectionView =
                try await host.prepare()
            #expect(
                !collectionView
                    .visibleCells.isEmpty
            )
            samples.append(
                milliseconds(
                    start.duration(
                        to: ContinuousClock.now
                    )
                )
            )
            host.tearDown()
        }

        return PerformanceDistribution(
            samples: samples
        )
    }

    private func deterministicScrollMeasurement()
        async throws -> ScrollMeasurement
    {
        let document =
            try await GitLabUnifiedDiffParser.parse(
                GitLabUnifiedDiffFixtures
                    .fiftyThousandLines
            )
        let host = try RendererHost(
            document: document,
            documentID: try makeDocumentID(),
            isVisible: true
        )
        defer {
            host.tearDown()
        }

        let collectionView =
            try await host.prepare()
        return await ScrollDisplayLinkDriver(
            collectionView: collectionView,
            frameCount: 600
        )
        .run()
    }

    private func makeDocumentID()
        throws -> GitLabDiffDocumentID
    {
        GitLabDiffDocumentID(
            accountID:
                GitLabAccountID(
                    host:
                        try GitLabHost(
                            "https://gitlab.example.com"
                        ),
                    userID: 1
                ),
            route:
                GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                ),
            headSHA: "benchmark-head",
            fileID:
                GitLabMergeRequestDiffFileID(
                    oldPath: "Sources/File.swift",
                    newPath: "Sources/File.swift"
                )
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
            throw PerformanceTestError
                .taskInfo(result)
        }
        return UInt64(info.resident_size)
    }

    private func milliseconds(
        _ duration: Duration
    ) -> Double {
        let components = duration.components
        return
            Double(components.seconds)
                * 1_000
            + Double(components.attoseconds)
                / 1_000_000_000_000_000
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

@MainActor
private final class RendererHost {
    let window: UIWindow
    let controller:
        UIHostingController<GitLabDiffCollectionView>

    init(
        document: GitLabParsedDiffDocument,
        documentID: GitLabDiffDocumentID,
        isVisible: Bool = true
    ) throws {
        let renderer =
            GitLabDiffCollectionView(
                document: document,
                documentID: documentID,
                selectedHunkJump: nil,
                rowHeight:
                    GitLabDiffLayoutMetrics
                    .baseRowHeight,
                contentWidth:
                    GitLabDiffLayoutMetrics
                    .contentWidth(
                        maximumLineLength:
                            document
                            .maximumRenderedLineLength,
                        rowHeight:
                            GitLabDiffLayoutMetrics
                            .baseRowHeight
                    )
            )
        controller =
            UIHostingController(
                rootView: renderer
            )
        guard
            let windowScene =
                UIApplication.shared.connectedScenes
                .compactMap({
                    $0 as? UIWindowScene
                })
                .first
        else {
            throw PerformanceTestError
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
        if isVisible {
            window.makeKeyAndVisible()
        }
    }

    func prepare()
        async throws -> UICollectionView
    {
        await Task.yield()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        CATransaction.flush()
        await Task.yield()
        controller.view.layoutIfNeeded()
        CATransaction.flush()

        guard
            let collectionView =
                Self.collectionView(
                    in: controller.view
                )
        else {
            throw PerformanceTestError
                .missingCollectionView
        }
        collectionView.layoutIfNeeded()
        CATransaction.flush()
        return collectionView
    }

    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private static func collectionView(
        in view: UIView
    ) -> UICollectionView? {
        if let collectionView =
            view as? UICollectionView
        {
            return collectionView
        }
        for subview in view.subviews {
            if let collectionView =
                collectionView(in: subview)
            {
                return collectionView
            }
        }
        return nil
    }
}

private struct PerformanceDistribution {
    let median: Double
    let p95: Double

    init(samples: [Double]) {
        let sorted = samples.sorted()
        median =
            sorted[sorted.count / 2]
        let p95Index = min(
            sorted.count - 1,
            Int(
                ceil(
                    Double(sorted.count)
                        * 0.95
                )
            ) - 1
        )
        p95 = sorted[p95Index]
    }
}

private struct ScrollMeasurement {
    let workP95: Double
    let hitchRatio: Double
    let maximumFrame: Double
}

@MainActor
private final class ScrollDisplayLinkDriver:
    NSObject
{
    private let collectionView:
        UICollectionView
    private let frameCount: Int
    private let scrollDistance: CGFloat
    private let clock = ContinuousClock()

    private var displayLink: CADisplayLink?
    private var continuation:
        CheckedContinuation<
            ScrollMeasurement,
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
        collectionView: UICollectionView,
        frameCount: Int
    ) {
        self.collectionView = collectionView
        self.frameCount = frameCount
        let maximumOffset = max(
            0,
            collectionView.contentSize.height
                - collectionView.bounds.height
        )
        scrollDistance = min(
            maximumOffset,
            GitLabDiffLayoutMetrics
                .baseRowHeight
                * 4
                * CGFloat(frameCount)
        )
        super.init()
        workSamples.reserveCapacity(frameCount)
        frameSamples.reserveCapacity(
            frameCount - 1
        )
        expectedFrameSamples.reserveCapacity(
            frameCount - 1
        )
    }

    func run() async -> ScrollMeasurement {
        await withCheckedContinuation {
            continuation in
            self.continuation = continuation
            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(step)
            )
            displayLink.preferredFrameRateRange =
                CAFrameRateRange(
                    minimum: 60,
                    maximum: 60,
                    preferred: 60
                )
            displayLink.add(
                to: .main,
                forMode: .common
            )
            self.displayLink = displayLink
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
            Double(completedFrames)
                / Double(frameCount)
        let workStart = clock.now
        collectionView.setContentOffset(
            CGPoint(
                x: 0,
                y:
                    scrollDistance
                    * progress
            ),
            animated: false
        )
        collectionView.layoutIfNeeded()
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
            expectedFrameSamples.reduce(0, +)
        let overBudgetTime = zip(
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
        let measurement =
            ScrollMeasurement(
                workP95:
                    Self.percentile95(
                        workSamples
                    ),
                hitchRatio:
                    expectedTime > 0
                    ? overBudgetTime
                        / expectedTime
                    : 0,
                maximumFrame:
                    frameSamples.max()
                    ?? 0
            )
        continuation?.resume(
            returning: measurement
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

private enum PerformanceTestError: Error {
    case missingCollectionView
    case missingWindowScene
    case taskInfo(kern_return_t)
}
