import Foundation
import Testing
@testable import Glab

@Suite(
    "GitLab discussion performance",
    .serialized
)
struct GitLabDiscussionPerformanceTests {
    private let resource: GitLabDiscussionResource =
        .issue(
            GitLabIssueRoute(
                projectID: 42,
                issueIID: 7
            )
        )

    @Test("Defines deterministic mixed discussion fixtures")
    func fixtureCoverage() throws {
        let discussions = try decode(
            GitLabDiscussionPerformanceFixtures
                .data(discussionCount: 20)
        )

        #expect(discussions.count == 20)
        #expect(
            discussions.contains {
                $0.notes.count > 1
            }
        )
        #expect(
            discussions
                .flatMap(\.notes)
                .contains { $0.isSystem }
        )
        #expect(
            discussions
                .flatMap(\.notes)
                .contains {
                    $0.kind == .diff
                }
        )
        #expect(
            discussions
                .flatMap(\.notes)
                .contains { $0.isInternal }
        )
    }

    @Test("Meets decode and model publication budgets")
    @MainActor
    func performanceBudgets() async throws {
        let data20 =
            try GitLabDiscussionPerformanceFixtures
                .data(discussionCount: 20)
        let data200 =
            try GitLabDiscussionPerformanceFixtures
                .data(discussionCount: 200)
        let discussions200 = try decode(data200)

        let decode20 =
            try p95DecodeMilliseconds(
                data: data20
            )
        let decode200 =
            try p95DecodeMilliseconds(
                data: data200
            )
        let firstPage =
            await p95FirstPageMilliseconds(
                discussions: discussions200,
                source: .network
            )
        let warmCache =
            await p95FirstPageMilliseconds(
                discussions: discussions200,
                source: .cache(.fresh)
            )
        let duplicateMerge =
            await p95DuplicateMergeMilliseconds(
                discussions: discussions200
            )

        print(
            "DISCUSSION_PERFORMANCE "
                + "decode20_p95_ms="
                + "\(format(decode20)) "
                + "decode200_p95_ms="
                + "\(format(decode200)) "
                + "first_page_p95_ms="
                + "\(format(firstPage)) "
                + "warm_cache_p95_ms="
                + "\(format(warmCache)) "
                + "duplicate_merge_p95_ms="
                + "\(format(duplicateMerge))"
        )

        #expect(decode20 < decode20Budget)
        #expect(decode200 < decode200Budget)
        #expect(firstPage < publicationBudget)
        #expect(warmCache < publicationBudget)
        #expect(
            duplicateMerge
                < duplicateMergeBudget
        )
    }

    @Test("Loading discussions does not eagerly parse Markdown")
    @MainActor
    func markdownRemainsLazy() async throws {
        let discussions = try decode(
            GitLabDiscussionPerformanceFixtures
                .data(discussionCount: 20)
        )
        let loader = PerformanceDiscussionLoader(
            firstPage: discussions,
            nextPage: nil,
            firstPageSource: .network
        )
        let parser = RecordingDiscussionParser()
        let renderer = GitLabMarkdownRenderer(
            parser: parser.parse
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.discussions.count == 20)
        #expect(await parser.callCount == 0)

        let note = try #require(
            model.discussions.first?.notes.first
        )
        _ = try await renderer.render(
            try markdownRequest(for: note)
        )

        #expect(await parser.callCount == 1)
    }

    private func p95DecodeMilliseconds(
        data: Data
    ) throws -> Double {
        _ = try decode(data)
        var measurements: [Double] = []

        for _ in 0..<30 {
            let start = ContinuousClock.now
            let discussions = try decode(data)
            #expect(!discussions.isEmpty)
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
    private func p95FirstPageMilliseconds(
        discussions: [GitLabDiscussion],
        source: GitLabAPIResponseSource
    ) async -> Double {
        var measurements: [Double] = []

        for _ in 0..<30 {
            let loader =
                PerformanceDiscussionLoader(
                    firstPage: discussions,
                    nextPage: nil,
                    firstPageSource: source
                )
            let model = GitLabDiscussionsModel(
                resource: resource,
                loader: loader
            )
            let start = ContinuousClock.now
            await model.loadIfNeeded()
            #expect(
                model.discussions.count
                    == discussions.count
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

    @MainActor
    private func p95DuplicateMergeMilliseconds(
        discussions: [GitLabDiscussion]
    ) async -> Double {
        var measurements: [Double] = []
        let last = discussions.last!

        for _ in 0..<30 {
            let loader =
                PerformanceDiscussionLoader(
                    firstPage: discussions,
                    nextPage: discussions,
                    firstPageSource: .network
                )
            let model = GitLabDiscussionsModel(
                resource: resource,
                loader: loader
            )
            await model.loadIfNeeded()

            let start = ContinuousClock.now
            await model.loadNextPageIfNeeded(
                after: last
            )
            #expect(
                model.discussions.count
                    == discussions.count
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

    private func decode(
        _ data: Data
    ) throws -> [GitLabDiscussion] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [GitLabDiscussion].self,
            from: data
        )
    }

    private func markdownRequest(
        for note: GitLabDiscussionNote
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            resource:
                resource.markdownResourceID(
                    noteID: note.id
                ),
            source: note.body,
            webURL: URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project/-/issues/7"
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

    private var decode20Budget: Double {
#if DEBUG
        20
#else
        10
#endif
    }

    private var decode200Budget: Double {
#if DEBUG
        150
#else
        75
#endif
    }

    private var publicationBudget: Double {
#if DEBUG
        10
#else
        5
#endif
    }

    private var duplicateMergeBudget: Double {
#if DEBUG
        20
#else
        10
#endif
    }
}

private actor PerformanceDiscussionLoader:
    GitLabDiscussionLoading
{
    let firstPage: [GitLabDiscussion]
    let nextPage: [GitLabDiscussion]?
    let firstPageSource:
        GitLabAPIResponseSource

    init(
        firstPage: [GitLabDiscussion],
        nextPage: [GitLabDiscussion]?,
        firstPageSource:
            GitLabAPIResponseSource
    ) {
        self.firstPage = firstPage
        self.nextPage = nextPage
        self.firstPageSource =
            firstPageSource
    }

    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>
    {
        if nextPageURL == nil {
            return firstResourcePage
        }

        return GitLabResourcePage(
            items: nextPage ?? [],
            nextPageURL: nil
        )
    }

    func loadDiscussionsFirstPage(
        for resource: GitLabDiscussionResource,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabDiscussion
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        await onPage(
            GitLabResourcePageEvent(
                page: firstResourcePage,
                source: firstPageSource
            )
        )
    }

    private var firstResourcePage:
        GitLabResourcePage<GitLabDiscussion>
    {
        GitLabResourcePage(
            items: firstPage,
            nextPageURL:
                nextPage == nil
                ? nil
                : URL(
                    string:
                        "https://gitlab.example.com/"
                        + "api/v4/discussions?page=2"
                )
        )
    }
}

private actor RecordingDiscussionParser {
    private(set) var callCount = 0

    func parse(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument {
        callCount += 1
        return GitLabMarkdownDocument(
            blocks: [
                .paragraph(
                    GitLabMarkdownText(
                        attributedString:
                            AttributedString(
                                request.source
                            )
                    )
                ),
            ]
        )
    }
}
