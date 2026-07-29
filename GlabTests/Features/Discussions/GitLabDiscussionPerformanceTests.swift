import Foundation
import QuartzCore
import SwiftUI
import Testing
import UIKit
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

    @Test("Meets the maximum-sized activity normalization budget")
    func maximumActivityNormalizationPerformance() {
        let source = String(
            repeating:
                "<li>abc123 &amp; reviewed<br>next</li>",
            count: 1_024
        )
        let normalizer =
            GitLabActivityTextNormalizer()
        var measurements: [Double] = []

        _ = normalizer.normalize(source)
        for _ in 0..<30 {
            let start = ContinuousClock.now
            let value = normalizer.normalize(source)
            #expect(!value.isEmpty)
            #expect(value.count <= 8_192)
            measurements.append(
                milliseconds(
                    from: start,
                    to: ContinuousClock.now
                )
            )
        }

        let p95 = percentile95(measurements)
        print(
            "ACTIVITY_NORMALIZATION_PERFORMANCE "
                + "maximum_source_p95_ms="
                + "\(format(p95))"
        )
        #expect(
            p95 < activityNormalizationBudget
        )
    }

    @Test("Keeps MR-sized discussion scroll offsets stable")
    @MainActor
    func stableDiscussionScrollOffsets() async throws {
        let scrollResource:
            GitLabDiscussionResource =
                .mergeRequest(
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    )
                )
        let discussions = try decode(
            GitLabDiscussionPerformanceFixtures
                .data(
                    discussionCount: 76,
                    leadingSystemDiscussionCount: 65
                )
        )
        let loader = PerformanceDiscussionLoader(
            firstPage: discussions,
            nextPage: nil,
            firstPageSource: .network
        )
        let model = GitLabDiscussionsModel(
            resource: scrollResource,
            loader: loader
        )
        await model.loadIfNeeded()

        let host = try DiscussionScrollHost(
            model: model,
            resource: scrollResource
        )
        defer {
            host.tearDown()
        }
        let scrollView = try await host.prepare()
        #expect(
            scrollView.contentSize.height
                > scrollView.bounds.height
        )

        var maximumDrift: CGFloat = 0
        var maximumContentHeightDrift:
            CGFloat = 0
        let initialContentHeight =
            scrollView.contentSize.height
        let steps =
            Array(1...12)
            + Array((0..<12).reversed())
        for step in steps {
            let maximumOffset = max(
                0,
                scrollView.contentSize.height
                    - scrollView.bounds.height
            )
            let targetOffset =
                maximumOffset
                * CGFloat(step)
                / 12
            scrollView.setContentOffset(
                CGPoint(
                    x: 0,
                    y: targetOffset
                ),
                animated: false
            )
            scrollView.layoutIfNeeded()
            host.layout()
            await Task.yield()
            host.layout()
            let drift =
                scrollView.contentOffset.y
                - targetOffset
            maximumDrift = max(
                maximumDrift,
                abs(drift)
            )
            maximumContentHeightDrift = max(
                maximumContentHeightDrift,
                abs(
                    scrollView.contentSize.height
                        - initialContentHeight
                )
            )
        }

        #expect(
            maximumDrift <= 1,
            "The discussion scroll offset drifted by \(maximumDrift) points."
        )
        #expect(
            maximumContentHeightDrift <= 1,
            "The discussion content height drifted by \(maximumContentHeightDrift) points."
        )
    }

    @Test("Loads another discussion page only at the visible anchor")
    @MainActor
    func paginationAnchorVisibility() async throws {
        let resource:
            GitLabDiscussionResource =
                .mergeRequest(
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    )
                )
        let firstPage = try decode(
            GitLabDiscussionPerformanceFixtures
                .data(discussionCount: 20)
        )
        let nextPage = Array(
            try decode(
                GitLabDiscussionPerformanceFixtures
                    .data(discussionCount: 40)
            )
            .suffix(20)
        )
        let loader = PerformanceDiscussionLoader(
            firstPage: firstPage,
            nextPage: nextPage,
            firstPageSource: .network
        )
        let model = GitLabDiscussionsModel(
            resource: resource,
            loader: loader
        )
        await model.loadIfNeeded()

        let host = try DiscussionScrollHost(
            model: model,
            resource: resource
        )
        defer {
            host.tearDown()
        }
        let scrollView = try await host.prepare()

        #expect(
            await loader.pageLoadCallCount
                == 0
        )
        #expect(model.discussions.count == 20)

        host.scrollToPaginationAnchor()
        for _ in 0..<20 {
            host.layout()
            await Task.yield()
        }

        #expect(
            await loader.pageLoadCallCount
                == 1
        )
        #expect(model.discussions.count == 40)
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

    private var activityNormalizationBudget: Double {
#if DEBUG
        50
#else
        25
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
    private(set) var pageLoadCallCount = 0

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
        pageLoadCallCount += 1
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

@MainActor
private final class DiscussionScrollHost {
    let window: UIWindow
    let scrollController:
        DiscussionScrollController
    let controller:
        UIHostingController<
            DiscussionScrollTestView
        >

    init(
        model: GitLabDiscussionsModel,
        resource: GitLabDiscussionResource
    ) throws {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        let accountID = GitLabAccountID(
            host: host,
            userID: 1
        )
        scrollController =
            DiscussionScrollController()
        controller = UIHostingController(
            rootView:
                DiscussionScrollTestView(
                    model: model,
                    resource: resource,
                    accountID: accountID,
                    appSession: AppSession(
                        credentialStore:
                            InMemoryGitLabCredentialStore()
                    ),
                    scrollController:
                        scrollController
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
            throw DiscussionViewPerformanceError
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

    func prepare() async throws -> UIScrollView {
        for _ in 0..<20 {
            layout()
            await Task.yield()
        }
        guard
            let scrollView =
                Self.verticalScrollView(
                    in: controller.view
                )
        else {
            throw DiscussionViewPerformanceError
                .missingScrollView
        }
        return scrollView
    }

    func layout() {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        CATransaction.flush()
    }

    func scrollToPaginationAnchor() {
        scrollController
            .scrollToPaginationAnchor()
    }

    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private static func verticalScrollView(
        in view: UIView
    ) -> UIScrollView? {
        if
            let scrollView =
                view as? UIScrollView,
            scrollView.contentSize.height
                > scrollView.bounds.height
        {
            return scrollView
        }
        for subview in view.subviews {
            if
                let scrollView =
                    verticalScrollView(
                        in: subview
                    )
            {
                return scrollView
            }
        }
        return nil
    }
}

private struct DiscussionScrollTestView:
    View
{
    let model: GitLabDiscussionsModel
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let appSession: AppSession
    let scrollController:
        DiscussionScrollController
    private let reactions =
        EmptyDiscussionReactionService()
    private let renderer =
        GitLabMarkdownRenderer(
            parser: {
                GitLabMarkdownDocument(
                    blocks: [
                        .paragraph(
                            GitLabMarkdownText(
                                attributedString:
                                    AttributedString(
                                        $0.source
                                    )
                            )
                        ),
                    ]
                )
            }
        )

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GitLabDetailScrollContent {
                    ForEach(0..<8, id: \.self) {
                        index in
                        Text(
                            String(
                                repeating:
                                    "Readiness item \(index). ",
                                count: index + 1
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }

                    GitLabDiscussionSection(
                        model: model,
                        resource: resource,
                        accountID: accountID,
                        webURL: URL(
                            string:
                                "https://gitlab.example.com/"
                                + "group/project/-/merge_requests/7"
                        ),
                        apiAccess: .readOnly,
                        reactionService:
                            reactions,
                        resolutionModel: nil,
                        appSession: appSession,
                        launchComposer: { _ in }
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 76)
            }
            .onChange(
                of:
                    scrollController
                        .paginationScrollGeneration
            ) {
                proxy.scrollTo(
                    "discussion.pagination.anchor",
                    anchor: .bottom
                )
            }
        }
        .environment(
            \.gitLabMarkdownRenderer,
            renderer
        )
    }
}

@MainActor
@Observable
private final class DiscussionScrollController {
    private(set) var
        paginationScrollGeneration = 0

    func scrollToPaginationAnchor() {
        paginationScrollGeneration += 1
    }
}

private actor EmptyDiscussionReactionService:
    GitLabEmojiReactionLoading,
    GitLabEmojiReactionMutating
{
    func loadReactionsPage(
        for awardable: GitLabEmojiAwardable,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabEmojiAward>
    {
        GitLabResourcePage(
            items: [],
            nextPageURL: nil
        )
    }

    func addReaction(
        named name: String,
        to awardable: GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError)
        -> GitLabEmojiAward
    {
        throw .api(.invalidResponse)
    }

    func removeReaction(
        awardID: Int,
        from awardable: GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError) {
        throw .api(.invalidResponse)
    }
}

private enum DiscussionViewPerformanceError:
    Error
{
    case missingWindowScene
    case missingScrollView
}
