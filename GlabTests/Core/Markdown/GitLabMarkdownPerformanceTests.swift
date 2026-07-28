import Foundation
import Testing
@testable import Glab

@Suite(
    "GitLab Markdown performance",
    .serialized
)
struct GitLabMarkdownPerformanceTests {
    @Test("Meets simulator parse and cache budgets")
    func parserAndCacheBudgets() async throws {
        let small = try await p95ParseMilliseconds(
            source: GitLabMarkdownFixtures.small
        )
        let medium = try await p95ParseMilliseconds(
            source: GitLabMarkdownFixtures.medium
        )
        let large = try await p95ParseMilliseconds(
            source: GitLabMarkdownFixtures.large
        )
        let warmCache =
            try await p95CacheHitMilliseconds()

        print(
            "MARKDOWN_PERFORMANCE "
                + "small_p95_ms=\(format(small)) "
                + "medium_p95_ms=\(format(medium)) "
                + "large_p95_ms=\(format(large)) "
                + "warm_cache_p95_ms=\(format(warmCache))"
        )

        #expect(small < 10)
        #expect(medium < mediumParseBudget)
        #expect(large < largeParseBudget)
        #expect(warmCache < 2)
    }

    private func p95ParseMilliseconds(
        source: String
    ) async throws -> Double {
        let request = try makeRequest(
            source: source
        )
        _ = try await GitLabMarkdownParser.parse(
            request
        )

        var measurements: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            let document =
                try await GitLabMarkdownParser.parse(
                    request
                )
            #expect(!document.blocks.isEmpty)
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
        let renderer = GitLabMarkdownRenderer()
        let request = try makeRequest(
            source: GitLabMarkdownFixtures.medium
        )
        _ = try await renderer.render(request)

        var measurements: [Double] = []
        for _ in 0..<100 {
            let start = ContinuousClock.now
            let document =
                try await renderer.render(request)
            #expect(!document.blocks.isEmpty)
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
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            resource: .issue(
                projectID: 10,
                issueIID: 42
            ),
            source: source,
            webURL: URL(
                string:
                    "https://gitlab.example.com/group/project"
                    + "/-/issues/42"
            )
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

    private var mediumParseBudget: Double {
#if DEBUG
        35
#else
        25
#endif
    }

    private var largeParseBudget: Double {
#if DEBUG
        225
#else
        175
#endif
    }
}
