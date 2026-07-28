import Foundation
import Testing
@testable import Glab

@Suite(
    "GitLab emoji reactions model",
    .serialized
)
@MainActor
struct GitLabEmojiReactionsModelTests {
    @Test("Loads every page and groups current-user awards")
    func loadsEveryPage() async throws {
        let nextURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/issues/7/award_emoji"
                    + "?page=2"
            )
        )
        let loader = SequencedReactionLoader(
            pages: [
                .success(
                    page(
                        [
                            makeTestEmojiAward(
                                id: 1,
                                userID: 7
                            ),
                        ],
                        nextPageURL: nextURL
                    )
                ),
                .success(
                    page(
                        [
                            makeTestEmojiAward(
                                id: 2,
                                userID: 8
                            ),
                        ]
                    )
                ),
            ]
        )
        let mutator =
            ImmediateReactionMutator()
        let model = makeModel(
            loader: loader,
            mutator: mutator
        )

        await model.loadIfNeeded()

        #expect(model.groups.count == 1)
        #expect(model.groups[0].count == 2)
        #expect(
            model.groups[0]
                .currentUserAwardIDs == [1]
        )
        #expect(model.hasLoaded)
        #expect(!model.isLoading)
        #expect(await loader.callCount == 2)
    }

    @Test("Read-only sessions never mutate")
    func preventsReadOnlyMutation() async {
        let loader = SequencedReactionLoader(
            pages: [.success(page([]))]
        )
        let mutator =
            ImmediateReactionMutator()
        let model = makeModel(
            apiAccess: .readOnly,
            loader: loader,
            mutator: mutator
        )
        await model.loadIfNeeded()

        await model.toggleReaction(
            named: "thumbsup"
        )

        #expect(!model.canMutate)
        #expect(await mutator.addCalls.isEmpty)
        #expect(
            model.mutationFailure?
                .error
                == .insufficientAccess(
                    required: .write
                )
        )
    }

    @Test("Optimistically adds once and reconciles the returned award")
    func optimisticallyAdds() async {
        let loader = SequencedReactionLoader(
            pages: [.success(page([]))]
        )
        let created = makeTestEmojiAward(
            id: 404,
            name: "heart",
            userID: 7
        )
        let mutator =
            GatedReactionMutator(
                result: .add(
                    .success(created)
                )
            )
        let model = makeModel(
            loader: loader,
            mutator: mutator
        )
        await model.loadIfNeeded()

        let first = Task {
            await model.toggleReaction(
                named: "heart"
            )
        }
        await mutator.waitUntilStarted()

        #expect(model.groups.count == 1)
        #expect(model.groups[0].count == 1)
        #expect(
            model.groups[0]
                .isSelectedByCurrentUser
        )
        #expect(model.groups[0].isPending)

        await model.toggleReaction(
            named: "heart"
        )
        #expect(await mutator.addCalls == ["heart"])

        await mutator.release()
        await first.value

        #expect(model.groups[0].count == 1)
        #expect(
            model.groups[0]
                .currentUserAwardIDs == [404]
        )
        #expect(!model.groups[0].isPending)
        #expect(model.mutationFailure == nil)
    }

    @Test("Rolls an exact removal back after rejection")
    func rollsBackRejectedRemoval() async {
        let existing = makeTestEmojiAward(
            id: 91,
            name: "thumbsup",
            userID: 7
        )
        let failure =
            GitLabSessionClientError
                .api(
                    .validation(statusCode: 422)
                )
        let loader = SequencedReactionLoader(
            pages: [
                .success(page([existing])),
            ]
        )
        let mutator =
            GatedReactionMutator(
                result: .remove(
                    .failure(failure)
                )
            )
        let model = makeModel(
            loader: loader,
            mutator: mutator
        )
        await model.loadIfNeeded()

        let task = Task {
            await model.toggleReaction(
                named: "thumbsup"
            )
        }
        await mutator.waitUntilStarted()

        #expect(model.groups.isEmpty)
        #expect(
            await mutator.removeCalls
                == [91]
        )

        await mutator.release()
        await task.value

        #expect(model.groups.count == 1)
        #expect(model.groups[0].count == 1)
        #expect(
            model.groups[0]
                .currentUserAwardIDs == [91]
        )
        #expect(
            model.mutationFailure?
                .certainty == .rejected
        )
    }

    @Test("Requires refresh after delivery-unknown rollback")
    func gatesUncertainMutation() async {
        let failure =
            GitLabSessionClientError
                .api(
                    .connectivity(
                        .networkConnectionLost
                    )
                )
        let loader = SequencedReactionLoader(
            pages: [
                .success(page([])),
                .success(page([])),
            ]
        )
        let mutator =
            ImmediateReactionMutator(
                addResults: [
                    .failure(failure),
                    .success(
                        makeTestEmojiAward(
                            id: 92,
                            userID: 7
                        )
                    ),
                ]
            )
        let model = makeModel(
            loader: loader,
            mutator: mutator
        )
        await model.loadIfNeeded()

        await model.toggleReaction(
            named: "thumbsup"
        )
        await model.toggleReaction(
            named: "thumbsup"
        )

        #expect(
            model.mutationFailure?
                .certainty
                == .deliveryUnknown
        )
        #expect(
            model.requiresRefresh(
                name: "thumbsup"
            )
        )
        #expect(
            await mutator.addCalls
                == ["thumbsup"]
        )

        await model.refresh()
        #expect(
            !model.requiresRefresh(
                name: "thumbsup"
            )
        )

        await model.toggleReaction(
            named: "thumbsup"
        )
        #expect(
            await mutator.addCalls
                == [
                    "thumbsup",
                    "thumbsup",
                ]
        )
        #expect(
            model.groups[0]
                .currentUserAwardIDs == [92]
        )
    }

    @Test("Surfaces mutation authentication failures")
    func surfacesAuthenticationFailure() async {
        let failure =
            GitLabSessionClientError
                .api(.unauthenticated)
        let loader = SequencedReactionLoader(
            pages: [.success(page([]))]
        )
        let mutator =
            ImmediateReactionMutator(
                addResults: [
                    .failure(failure),
                ]
            )
        let model = makeModel(
            loader: loader,
            mutator: mutator
        )
        await model.loadIfNeeded()

        await model.toggleReaction(
            named: "rocket"
        )

        #expect(
            model.authenticationFailure
                == failure
        )
    }

    private func makeModel(
        apiAccess:
            GitLabAPIAccess = .readWrite,
        loader:
            any GitLabEmojiReactionLoading,
        mutator:
            any GitLabEmojiReactionMutating
    ) -> GitLabEmojiReactionsModel {
        GitLabEmojiReactionsModel(
            awardable: testIssueAwardable,
            currentUserID: 7,
            apiAccess: apiAccess,
            loader: loader,
            mutator: mutator
        )
    }

    private func page(
        _ awards: [GitLabEmojiAward],
        nextPageURL: URL? = nil
    ) -> GitLabResourcePage<
        GitLabEmojiAward
    > {
        GitLabResourcePage(
            items: awards,
            nextPageURL: nextPageURL,
            totalCount: nil
        )
    }
}

private actor SequencedReactionLoader:
    GitLabEmojiReactionLoading
{
    private var pages: [
        Result<
            GitLabResourcePage<
                GitLabEmojiAward
            >,
            GitLabSessionClientError
        >
    ]
    private(set) var callCount = 0

    init(
        pages: [
            Result<
                GitLabResourcePage<
                    GitLabEmojiAward
                >,
                GitLabSessionClientError
            >
        ]
    ) {
        self.pages = pages
    }

    func loadReactionsPage(
        for awardable: GitLabEmojiAwardable,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabEmojiAward
        >
    {
        callCount += 1
        guard !pages.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try pages.removeFirst().get()
    }
}

private actor ImmediateReactionMutator:
    GitLabEmojiReactionMutating
{
    private var addResults: [
        Result<
            GitLabEmojiAward,
            GitLabSessionClientError
        >
    ]
    private var removeResults: [
        Result<
            Void,
            GitLabSessionClientError
        >
    ]
    private(set) var addCalls:
        [String] = []
    private(set) var removeCalls:
        [Int] = []

    init(
        addResults: [
            Result<
                GitLabEmojiAward,
                GitLabSessionClientError
            >
        ] = [],
        removeResults: [
            Result<
                Void,
                GitLabSessionClientError
            >
        ] = []
    ) {
        self.addResults = addResults
        self.removeResults = removeResults
    }

    func addReaction(
        named name: String,
        to awardable: GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError)
        -> GitLabEmojiAward
    {
        addCalls.append(name)
        guard !addResults.isEmpty else {
            return makeTestEmojiAward(
                name: name
            )
        }
        return try addResults
            .removeFirst()
            .get()
    }

    func removeReaction(
        awardID: Int,
        from awardable:
            GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError) {
        removeCalls.append(awardID)
        guard !removeResults.isEmpty else {
            return
        }
        try removeResults
            .removeFirst()
            .get()
    }
}

private actor GatedReactionMutator:
    GitLabEmojiReactionMutating
{
    enum ResultValue {
        case add(
            Result<
                GitLabEmojiAward,
                GitLabSessionClientError
            >
        )
        case remove(
            Result<
                Void,
                GitLabSessionClientError
            >
        )
    }

    let result: ResultValue
    private(set) var addCalls:
        [String] = []
    private(set) var removeCalls:
        [Int] = []
    private var didStart = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation:
        CheckedContinuation<Void, Never>?
    private var shouldRelease = false

    init(result: ResultValue) {
        self.result = result
    }

    func addReaction(
        named name: String,
        to awardable: GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError)
        -> GitLabEmojiAward
    {
        addCalls.append(name)
        await waitForRelease()
        guard case let .add(result) = result else {
            throw .api(.invalidResponse)
        }
        return try result.get()
    }

    func removeReaction(
        awardID: Int,
        from awardable:
            GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError) {
        removeCalls.append(awardID)
        await waitForRelease()
        guard case let .remove(result) = result else {
            throw .api(.invalidResponse)
        }
        try result.get()
    }

    func waitUntilStarted() async {
        guard !didStart else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func release() {
        shouldRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func waitForRelease() async {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            if shouldRelease {
                $0.resume()
            } else {
                releaseContinuation = $0
            }
        }
    }
}
