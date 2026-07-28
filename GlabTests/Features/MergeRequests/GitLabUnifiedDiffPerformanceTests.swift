import Foundation
import Testing
@testable import Glab

@Suite(
    "GitLab unified diff performance",
    .serialized
)
struct GitLabUnifiedDiffPerformanceTests {
    @Test("Meets simulator parser and warm-cache budgets")
    func parserAndCacheBudgets() async throws {
        let oneThousand = try await p95ParseMilliseconds(
            source:
                GitLabUnifiedDiffFixtures
                .oneThousandLines
        )
        let tenThousand = try await p95ParseMilliseconds(
            source:
                GitLabUnifiedDiffFixtures
                .tenThousandLines
        )
        let fiftyThousand = try await p95ParseMilliseconds(
            source:
                GitLabUnifiedDiffFixtures
                .fiftyThousandLines
        )
        let warmCache =
            try await p95CacheHitMilliseconds()

        print(
            "DIFF_PERFORMANCE "
                + "1k_p95_ms=\(format(oneThousand)) "
                + "10k_p95_ms=\(format(tenThousand)) "
                + "50k_p95_ms=\(format(fiftyThousand)) "
                + "warm_cache_p95_ms=\(format(warmCache))"
        )

        #expect(oneThousand < 10)
        #expect(tenThousand < 50)
        #expect(fiftyThousand < 200)
        #expect(warmCache < 2)
    }

    private func p95ParseMilliseconds(
        source: String
    ) async throws -> Double {
        _ = try await GitLabUnifiedDiffParser.parse(
            source
        )

        var measurements: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            let document =
                try await GitLabUnifiedDiffParser
                .parse(source)
            #expect(!document.items.isEmpty)
            measurements.append(
                milliseconds(
                    from: start,
                    to: ContinuousClock.now
                )
            )
        }
        return percentile95(measurements)
    }

    private func p95CacheHitMilliseconds()
        async throws -> Double
    {
        let renderer = GitLabDiffRenderer()
        let request = try makeRequest(
            source:
                GitLabUnifiedDiffFixtures
                .tenThousandLines
        )
        _ = try await renderer.render(request)

        var measurements: [Double] = []
        for _ in 0..<100 {
            let start = ContinuousClock.now
            let document =
                try await renderer.render(request)
            #expect(!document.items.isEmpty)
            measurements.append(
                milliseconds(
                    from: start,
                    to: ContinuousClock.now
                )
            )
        }
        return percentile95(measurements)
    }

    private func makeRequest(
        source: String
    ) throws -> GitLabDiffRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabDiffRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            route: GitLabMergeRequestRoute(
                projectID: 10,
                mergeRequestIID: 7
            ),
            headSHA: "head",
            oldPath: "Sources/File.swift",
            newPath: "Sources/File.swift",
            source: source
        )
    }

    private func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Double {
        let components =
            start.duration(to: end).components
        return
            Double(components.seconds) * 1_000
            + Double(components.attoseconds)
                / 1_000_000_000_000_000
    }

    private func percentile95(
        _ measurements: [Double]
    ) -> Double {
        let sorted = measurements.sorted()
        let index = min(
            sorted.count - 1,
            Int(
                ceil(
                    Double(sorted.count) * 0.95
                )
            ) - 1
        )
        return sorted[index]
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
