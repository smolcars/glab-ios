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

    @Test("Meets task indexing, rewrite, render, and interaction budgets")
    @MainActor
    func taskInteractionBudgets() async throws {
        let small =
            GitLabMarkdownFixtures
                .taskSourceComplex
        let hundredKB =
            GitLabMarkdownFixtures
                .taskPerformanceHundredKB
        let nearLimit =
            GitLabMarkdownFixtures
                .taskPerformanceNearLimit

        #expect(
            hundredKB.utf8.count
                >= 100_000
        )
        #expect(
            nearLimit.utf8.count
                >= 900_000
        )
        #expect(
            nearLimit.utf8.count
                <= 1_048_576
        )

        let smallIndex =
            try await p95IndexMilliseconds(
                source: small,
                iterations: 20
            )
        let hundredKBIndex =
            try await p95IndexMilliseconds(
                source: hundredKB,
                iterations: 10
            )
        let nearLimitIndex =
            try await p95IndexMilliseconds(
                source: nearLimit,
                iterations: 3
            )
        let hundredKBRewrite =
            try await p95RewriteMilliseconds(
                source: hundredKB,
                iterations: 10
            )
        let nearLimitRewrite =
            try await p95RewriteMilliseconds(
                source: nearLimit,
                iterations: 3
            )
        let nearLimitParse =
            try await p95ParseMilliseconds(
                source: nearLimit,
                iterations: 3
            )
        let hundredKBFirstRender =
            try await p95FirstRenderMilliseconds(
                source: hundredKB,
                iterations: 5
            )
        let preparation =
            try p95TogglePreparationMilliseconds(
                batchSize: 100,
                iterations: 10
            )
        let lookup =
            try await p95StateLookupMilliseconds(
                batchSize: 10_000,
                iterations: 10
            )

        print(
            "MARKDOWN_TASK_PERFORMANCE "
                + "small_index_p95_ms=\(format(smallIndex)) "
                + "hundred_kb_index_p95_ms=\(format(hundredKBIndex)) "
                + "near_limit_index_p95_ms=\(format(nearLimitIndex)) "
                + "hundred_kb_rewrite_p95_ms=\(format(hundredKBRewrite)) "
                + "near_limit_rewrite_p95_ms=\(format(nearLimitRewrite)) "
                + "near_limit_parse_p95_ms=\(format(nearLimitParse)) "
                + "hundred_kb_first_render_p95_ms=\(format(hundredKBFirstRender)) "
                + "prepare_100_p95_ms=\(format(preparation)) "
                + "lookup_10000_p95_ms=\(format(lookup))"
        )

        #expect(smallIndex < 5)
        #expect(
            hundredKBIndex
                < hundredKBIndexBudget
        )
        #expect(
            nearLimitIndex
                < nearLimitIndexBudget
        )
        #expect(
            hundredKBRewrite
                < hundredKBRewriteBudget
        )
        #expect(
            nearLimitRewrite
                < nearLimitRewriteBudget
        )
        #expect(
            nearLimitParse
                < nearLimitParseBudget
        )
        #expect(
            hundredKBFirstRender
                < hundredKBRenderBudget
        )
        #expect(preparation < 10)
        #expect(lookup < 10)
    }

    private func p95ParseMilliseconds(
        source: String,
        iterations: Int = 20
    ) async throws -> Double {
        let request = try makeRequest(
            source: source
        )
        _ = try await GitLabMarkdownParser.parse(
            request
        )

        var measurements: [Double] = []
        for _ in 0..<iterations {
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

    private func p95IndexMilliseconds(
        source: String,
        iterations: Int
    ) async throws -> Double {
        _ = try await
            GitLabMarkdownTaskSourceIndex
            .tasks(in: source)

        var measurements: [Double] = []
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            let tasks =
                try await
                    GitLabMarkdownTaskSourceIndex
                    .tasks(in: source)
            #expect(!tasks.isEmpty)
            measurements.append(
                milliseconds(
                    from: start,
                    to: ContinuousClock.now
                )
            )
        }
        return percentile95(measurements)
    }

    private func p95RewriteMilliseconds(
        source: String,
        iterations: Int
    ) async throws -> Double {
        let tasks =
            try await
                GitLabMarkdownTaskSourceIndex
                .tasks(in: source)
        let task = try #require(
            tasks.first {
                $0.state
                    == .incomplete
            }
        )

        var measurements: [Double] = []
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            let rewritten =
                try await
                    GitLabMarkdownTaskSourceRewriter
                    .rewrite(
                        source,
                        task: task,
                        to: .complete
                    )
            #expect(
                rewritten.utf8.count
                    == source.utf8.count
            )
            measurements.append(
                milliseconds(
                    from: start,
                    to: ContinuousClock.now
                )
            )
        }
        return percentile95(measurements)
    }

    private func p95FirstRenderMilliseconds(
        source: String,
        iterations: Int
    ) async throws -> Double {
        let request = try makeRequest(
            source: source
        )
        var measurements: [Double] = []

        for _ in 0..<iterations {
            let renderer =
                GitLabMarkdownRenderer()
            let start = ContinuousClock.now
            let document =
                try await renderer.render(
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

    @MainActor
    private func
        p95TogglePreparationMilliseconds(
            batchSize: Int,
            iterations: Int
        ) throws -> Double
    {
        let accountID =
            try makeAccountID()
        let service =
            MarkdownPerformanceEditingService()
        let store =
            InMemoryGitLabResourceEditDraftStore()
        var measurements: [Double] = []

        for _ in 0..<iterations {
            let start = ContinuousClock.now
            var finalPhase =
                GitLabDescriptionTaskTogglePhase
                .saving
            for _ in 0..<batchSize {
                let model =
                    GitLabDescriptionTaskToggleModel(
                        accountID: accountID,
                        apiAccess: .readWrite,
                        service: service,
                        draftStore: store,
                        isAccountCurrent: {
                            true
                        },
                        onSuccess: { _ in },
                        onStale: {}
                    )
                finalPhase = model.phase
            }
            #expect(finalPhase == .idle)
            measurements.append(
                milliseconds(
                    from: start,
                    to: ContinuousClock.now
                )
            )
        }
        return percentile95(measurements)
    }

    @MainActor
    private func p95StateLookupMilliseconds(
        batchSize: Int,
        iterations: Int
    ) async throws -> Double {
        let source = "- [ ] Ship"
        let task = try #require(
            try await
                GitLabMarkdownTaskSourceIndex
                .tasks(in: source)
                .first
        )
        let model =
            GitLabDescriptionTaskToggleModel(
                accountID:
                    try makeAccountID(),
                apiAccess: .readWrite,
                service:
                    MarkdownPerformanceEditingService(),
                draftStore:
                    InMemoryGitLabResourceEditDraftStore(),
                isAccountCurrent: {
                    true
                },
                onSuccess: { _ in },
                onStale: {}
            )
        var measurements: [Double] = []

        for _ in 0..<iterations {
            let start = ContinuousClock.now
            var state =
                GitLabMarkdownTaskState
                .complete
            for _ in 0..<batchSize {
                state =
                    model.displayedState(
                        for: task
                    )
            }
            #expect(state == .incomplete)
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

    private func makeAccountID()
        throws -> GitLabAccountID
    {
        GitLabAccountID(
            host:
                try GitLabHost(
                    "https://gitlab.example.com"
                ),
            userID: 1
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

    private var hundredKBIndexBudget: Double {
#if DEBUG
        20
#else
        15
#endif
    }

    private var nearLimitIndexBudget: Double {
#if DEBUG
        150
#else
        110
#endif
    }

    private var hundredKBRewriteBudget: Double {
#if DEBUG
        25
#else
        18
#endif
    }

    private var nearLimitRewriteBudget: Double {
#if DEBUG
        175
#else
        130
#endif
    }

    private var nearLimitParseBudget: Double {
#if DEBUG
        1_800
#else
        1_400
#endif
    }

    private var hundredKBRenderBudget: Double {
#if DEBUG
        250
#else
        200
#endif
    }
}

private actor MarkdownPerformanceEditingService:
    GitLabResourceEditing
{
    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        throw .api(.invalidResponse)
    }

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        throw .api(.invalidResponse)
    }

    func invalidateAffectedReads(
        for target:
            GitLabResourceEditTarget
    ) {}
}
