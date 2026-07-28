import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussion resolution model")
struct GitLabDiscussionResolutionModelTests {
    @Test("Resolves and reopens with authoritative metadata and readiness refresh")
    @MainActor
    func resolvesAndReopens() async throws {
        let resolver = GitLabAPIUser(
            id: 77,
            username: "resolver",
            name: "Resolve Person",
            avatarURL: nil,
            webURL: nil
        )
        let resolvedAt = Date(
            timeIntervalSince1970: 8_000
        )
        let unresolved =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let resolved =
            resolutionDiscussion(
                id: "thread",
                resolved: true,
                resolvedBy: resolver,
                resolvedAt: resolvedAt
            )
        let reopened =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .success(resolved),
                        .success(reopened),
                    ],
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [unresolved],
                mutator: mutator
            )

        await context.model.toggle(
            unresolved
        )

        #expect(
            context.model.status(
                for: resolved
            )
                == GitLabDiscussionResolutionStatus(
                    isResolved: true,
                    phase: .idle,
                    desiredResolved: nil,
                    resolvedBy: resolver,
                    resolvedAt: resolvedAt,
                    failure: nil
                )
        )
        #expect(
            context.state.reconciled
                == [resolved]
        )
        #expect(
            context.state.readinessRefreshCount
                == 1
        )

        await context.model.toggle(
            resolved
        )

        #expect(
            context.model.status(
                for: reopened
            )?
                .isResolved == false
        )
        #expect(
            context.model.status(
                for: reopened
            )?
                .resolvedBy == nil
        )
        #expect(
            context.state.reconciled
                == [
                    resolved,
                    reopened,
                ]
        )
        #expect(
            context.state.readinessRefreshCount
                == 2
        )
        #expect(
            await mutator.resolutionCalls
                == [
                    ResolutionCall(
                        discussionID: "thread",
                        resolved: true
                    ),
                    ResolutionCall(
                        discussionID: "thread",
                        resolved: false
                    ),
                ]
        )
    }

    @Test("Presents an optimistic state and coalesces repeated taps")
    @MainActor
    func presentsOptimisticState() async throws {
        let unresolved =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let resolved =
            resolutionDiscussion(
                id: "thread",
                resolved: true
            )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .success(resolved),
                    ],
                ],
                gatedResolutionIDs: [
                    "thread",
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [unresolved],
                mutator: mutator
            )

        let first = Task {
            await context.model.toggle(
                unresolved
            )
        }
        await mutator.waitUntilResolutionStarts(
            discussionID: "thread"
        )

        let pending = try #require(
            context.model.status(
                for: unresolved
            )
        )
        #expect(pending.phase == .pending)
        #expect(pending.isResolved)
        #expect(pending.desiredResolved == true)
        #expect(pending.resolvedBy == nil)
        #expect(pending.resolvedAt == nil)

        await context.model.toggle(
            unresolved
        )
        #expect(
            await mutator.resolutionCalls
                .count == 1
        )

        await mutator.releaseResolution(
            discussionID: "thread"
        )
        await first.value

        #expect(
            context.model.status(
                for: resolved
            )?
                .phase == .idle
        )
    }

    @Test("Keeps the control honestly busy while refreshing readiness")
    @MainActor
    func presentsReadinessRefreshState()
        async throws
    {
        let resolver = GitLabAPIUser(
            id: 77,
            username: "resolver",
            name: "Resolve Person",
            avatarURL: nil,
            webURL: nil
        )
        let unresolved =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let resolved =
            resolutionDiscussion(
                id: "thread",
                resolved: true,
                resolvedBy: resolver,
                resolvedAt: Date(
                    timeIntervalSince1970:
                        8_000
                )
            )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .success(resolved),
                    ],
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [unresolved],
                mutator: mutator
            )
        context.state.gatesReadiness = true

        let operation = Task {
            await context.model.toggle(
                unresolved
            )
        }
        await context.state
            .waitUntilReadinessRefreshStarts()

        let refreshing = try #require(
            context.model.status(
                for: resolved
            )
        )
        #expect(
            refreshing.phase
                == .refreshingReadiness
        )
        #expect(refreshing.isResolved)
        #expect(
            refreshing.resolvedBy
                == resolver
        )

        await context.model.toggle(
            resolved
        )
        #expect(
            await mutator.resolutionCalls
                .count == 1
        )

        context.state
            .releaseReadinessRefresh()
        await operation.value

        #expect(
            context.model.status(
                for: resolved
            )?
                .phase == .idle
        )
    }

    @Test("Allows independent mutations for different discussion IDs")
    @MainActor
    func mutatesIndependentDiscussions() async throws {
        let first =
            resolutionDiscussion(
                id: "first",
                resolved: false
            )
        let second =
            resolutionDiscussion(
                id: "second",
                resolved: true
            )
        let resolvedFirst =
            resolutionDiscussion(
                id: "first",
                resolved: true
            )
        let reopenedSecond =
            resolutionDiscussion(
                id: "second",
                resolved: false
            )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "first": [
                        .success(resolvedFirst),
                    ],
                    "second": [
                        .success(reopenedSecond),
                    ],
                ],
                gatedResolutionIDs: [
                    "first",
                    "second",
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [
                    first,
                    second,
                ],
                mutator: mutator
            )

        let firstTask = Task {
            await context.model.toggle(first)
        }
        let secondTask = Task {
            await context.model.toggle(second)
        }
        await mutator.waitUntilResolutionStarts(
            discussionID: "first"
        )
        await mutator.waitUntilResolutionStarts(
            discussionID: "second"
        )

        #expect(
            context.model.status(for: first)?
                .phase == .pending
        )
        #expect(
            context.model.status(for: second)?
                .phase == .pending
        )
        #expect(
            await mutator.resolutionCalls
                .count == 2
        )

        await mutator.releaseResolution(
            discussionID: "first"
        )
        await mutator.releaseResolution(
            discussionID: "second"
        )
        await firstTask.value
        await secondTask.value

        #expect(
            Set(
                context.state.reconciled
                    .map(\.id)
            ) == [
                "first",
                "second",
            ]
        )
        #expect(
            context.state.readinessRefreshCount
                == 2
        )
    }

    @Test("Rejects read-only and inapplicable discussions before transport")
    @MainActor
    func rejectsInvalidStarts() async throws {
        let actionable =
            resolutionDiscussion(
                id: "actionable",
                resolved: false
            )
        let mutator =
            ResolutionRecordingMutator()
        let readOnly =
            try ResolutionModelContext(
                discussions: [actionable],
                apiAccess: .readOnly,
                mutator: mutator
            )

        await readOnly.model.toggle(
            actionable
        )
        await readOnly.model.toggle(
            makeTestDiscussion(
                id: "individual",
                individualNote: true,
                notes: [
                    makeTestDiscussionNote(
                        resolvable: true
                    ),
                ]
            )
        )
        await readOnly.model.toggle(
            makeTestDiscussion(
                id: "non-resolvable"
            )
        )
        await readOnly.model.toggle(
            resolutionDiscussion(
                id: "",
                resolved: false
            )
        )

        #expect(
            readOnly.model.status(
                for: actionable
            )?
                .failure == .readOnly
        )
        #expect(
            await mutator.resolutionCalls
                .isEmpty
        )
    }

    @Test("Rolls back definite failures without refreshing readiness")
    @MainActor
    func rollsBackRejectedFailures() async throws {
        let failures: [
            GitLabDiscussionMutationError
        ] = [
            .encoding,
            .request(
                .api(
                    .validation(
                        statusCode: 400
                    )
                )
            ),
            .request(
                .api(.unauthenticated)
            ),
            .request(
                .api(.forbidden)
            ),
            .request(
                .api(.notFound)
            ),
            .request(
                .api(
                    .validation(
                        statusCode: 409
                    )
                )
            ),
            .request(
                .api(
                    .validation(
                        statusCode: 422
                    )
                )
            ),
        ]

        for (index, failure) in
            failures.enumerated()
        {
            let id = "thread-\(index)"
            let discussion =
                resolutionDiscussion(
                    id: id,
                    resolved: false
                )
            let mutator =
                ResolutionRecordingMutator(
                    resolutionResults: [
                        id: [
                            .failure(failure),
                        ],
                    ]
                )
            let context =
                try ResolutionModelContext(
                    discussions: [discussion],
                    mutator: mutator
                )

            await context.model.toggle(
                discussion
            )

            let status = try #require(
                context.model.status(
                    for: discussion
                )
            )
            #expect(status.phase == .rejected)
            #expect(!status.isResolved)
            #expect(
                status.failure
                    == .mutation(
                        failure,
                        certainty: .rejected
                    )
            )
            #expect(
                context.state.reconciled
                    .isEmpty
            )
            #expect(
                context.state
                    .readinessRefreshCount
                    == 0
            )
        }
    }

    @Test("Unknown delivery blocks another write until an exact check proves success")
    @MainActor
    func checksUnknownSuccess() async throws {
        let unresolved =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let resolved =
            resolutionDiscussion(
                id: "thread",
                resolved: true
            )
        let failure =
            GitLabDiscussionMutationError
                .request(
                    .api(
                        .connectivity(
                            .networkConnectionLost
                        )
                    )
                )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .failure(failure),
                    ],
                ],
                readResults: [
                    "thread": [
                        .success(resolved),
                    ],
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [unresolved],
                mutator: mutator
            )

        await context.model.toggle(
            unresolved
        )

        let unknown = try #require(
            context.model.status(
                for: unresolved
            )
        )
        #expect(
            unknown.phase
                == .deliveryUnknown
        )
        #expect(unknown.isResolved)
        #expect(
            unknown.failure
                == .mutation(
                    failure,
                    certainty:
                        .deliveryUnknown
                )
        )

        await context.model.toggle(
            unresolved
        )
        #expect(
            await mutator.resolutionCalls
                .count == 1
        )

        await context.model.checkGitLab(
            discussionID: "thread"
        )

        #expect(
            context.model.status(
                for: resolved
            )?
                .phase == .idle
        )
        #expect(
            context.state.reconciled
                == [resolved]
        )
        #expect(
            context.state.readinessRefreshCount
                == 1
        )
        #expect(
            await mutator.readDiscussionIDs
                == ["thread"]
        )
    }

    @Test("A check proving no change enables one explicit retry")
    @MainActor
    func retriesAfterConfirmedNoChange()
        async throws
    {
        let unresolved =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let resolved =
            resolutionDiscussion(
                id: "thread",
                resolved: true
            )
        let unknown =
            GitLabDiscussionMutationError
                .request(
                    .api(
                        .server(
                            statusCode: 503
                        )
                    )
                )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .failure(unknown),
                        .success(resolved),
                    ],
                ],
                readResults: [
                    "thread": [
                        .success(unresolved),
                    ],
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [unresolved],
                mutator: mutator
            )

        await context.model.toggle(
            unresolved
        )
        await context.model.checkGitLab(
            discussionID: "thread"
        )

        let retry = try #require(
            context.model.status(
                for: unresolved
            )
        )
        #expect(
            retry.phase == .retryAvailable
        )
        #expect(!retry.isResolved)
        #expect(retry.desiredResolved == true)

        await context.model.retry(
            discussionID: "thread"
        )

        #expect(
            await mutator.resolutionCalls
                .count == 2
        )
        #expect(
            context.state.reconciled
                == [
                    unresolved,
                    resolved,
                ]
        )
        #expect(
            context.state.readinessRefreshCount
                == 1
        )
    }

    @Test("Malformed and failed checks retain unknown delivery")
    @MainActor
    func retainsUnknownAfterFailedChecks()
        async throws
    {
        let unresolved =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let unknown =
            GitLabDiscussionMutationError
                .request(
                    .api(
                        .connectivity(
                            .timedOut
                        )
                    )
                )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .failure(unknown),
                    ],
                ],
                readResults: [
                    "thread": [
                        .success(
                            resolutionDiscussion(
                                id: "wrong",
                                resolved: true
                            )
                        ),
                        .failure(
                            .request(
                                .api(
                                    .connectivity(
                                        .notConnectedToInternet
                                    )
                                )
                            )
                        ),
                    ],
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [unresolved],
                mutator: mutator
            )

        await context.model.toggle(
            unresolved
        )
        await context.model.checkGitLab(
            discussionID: "thread"
        )
        #expect(
            context.model.status(
                for: unresolved
            )?
                .phase
                == .deliveryUnknown
        )

        await context.model.checkGitLab(
            discussionID: "thread"
        )
        #expect(
            context.model.status(
                for: unresolved
            )?
                .phase
                == .deliveryUnknown
        )
        #expect(
            await mutator.resolutionCalls
                .count == 1
        )
        #expect(
            await mutator.readDiscussionIDs
                .count == 2
        )
    }

    @Test("Invalid mutation responses become delivery unknown")
    @MainActor
    func rejectsInvalidMutationResponses()
        async throws
    {
        let invalidResponses = [
            resolutionDiscussion(
                id: "wrong",
                resolved: true
            ),
            resolutionDiscussion(
                id: "thread",
                resolved: false
            ),
            makeTestDiscussion(
                id: "thread"
            ),
        ]

        for (index, response) in
            invalidResponses.enumerated()
        {
            let id = "thread"
            let unresolved =
                resolutionDiscussion(
                    id: id,
                    resolved: false
                )
            let mutator =
                ResolutionRecordingMutator(
                    resolutionResults: [
                        id: [
                            .success(response),
                        ],
                    ]
                )
            let context =
                try ResolutionModelContext(
                    discussions: [
                        unresolved,
                    ],
                    mutator: mutator
                )

            await context.model.toggle(
                unresolved
            )

            #expect(
                context.model.status(
                    for: unresolved
                )?
                    .phase
                    == .deliveryUnknown,
                "Invalid response \(index)"
            )
            #expect(
                context.state.reconciled
                    .isEmpty
            )
        }
    }

    @Test("A newer loaded discussion forces an exact read before reconciliation")
    @MainActor
    func protectsNewerDiscussion() async throws {
        let baseline =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let mutationResponse =
            resolutionDiscussion(
                id: "thread",
                resolved: true,
                resolvedAt: Date(
                    timeIntervalSince1970:
                        10_000
                )
            )
        let newer =
            resolutionDiscussion(
                id: "thread",
                resolved: true,
                resolvedAt: Date(
                    timeIntervalSince1970:
                        11_000
                )
            )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .success(
                            mutationResponse
                        ),
                    ],
                ],
                readResults: [
                    "thread": [
                        .success(newer),
                    ],
                ],
                gatedResolutionIDs: [
                    "thread",
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [baseline],
                mutator: mutator
            )

        let operation = Task {
            await context.model.toggle(
                baseline
            )
        }
        await mutator.waitUntilResolutionStarts(
            discussionID: "thread"
        )
        context.state.current[
            "thread"
        ] = resolutionDiscussion(
            id: "thread",
            resolved: false,
            resolvedAt: Date(
                timeIntervalSince1970:
                    10_500
            )
        )
        await mutator.releaseResolution(
            discussionID: "thread"
        )
        await operation.value

        #expect(
            context.state.reconciled
                == [newer]
        )
        #expect(
            await mutator.readDiscussionIDs
                == ["thread"]
        )
        #expect(
            context.state.readinessRefreshCount
                == 1
        )
    }

    @Test("Account switching and detail cancellation discard late results")
    @MainActor
    func discardsLateResults() async throws {
        let baseline =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let resolved =
            resolutionDiscussion(
                id: "thread",
                resolved: true
            )

        for cancels in [false, true] {
            let mutator =
                ResolutionRecordingMutator(
                    resolutionResults: [
                        "thread": [
                            .success(resolved),
                        ],
                    ],
                    gatedResolutionIDs: [
                        "thread",
                    ]
                )
            let context =
                try ResolutionModelContext(
                    discussions: [baseline],
                    mutator: mutator
                )
            let operation = Task {
                await context.model.toggle(
                    baseline
                )
            }
            await mutator
                .waitUntilResolutionStarts(
                    discussionID: "thread"
                )

            if cancels {
                context.model.cancelAll()
            } else {
                context.state.isAccountCurrent =
                    false
            }
            await mutator.releaseResolution(
                discussionID: "thread"
            )
            await operation.value

            #expect(
                context.state.reconciled
                    .isEmpty
            )
            #expect(
                context.state
                    .readinessRefreshCount
                    == 0
            )
            #expect(
                context.model.status(
                    for: baseline
                )?
                    .phase == .idle
            )
        }
    }

    @Test("Cancellation before transport writes nothing and cancellation during transport is unknown")
    @MainActor
    func classifiesCancellation() async throws {
        let baseline =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )

        let beforeMutator =
            ResolutionRecordingMutator()
        let before =
            try ResolutionModelContext(
                discussions: [baseline],
                mutator: beforeMutator
            )
        let cancelledBefore = Task {
            withUnsafeCurrentTask {
                $0?.cancel()
            }
            await before.model.toggle(
                baseline
            )
        }
        await cancelledBefore.value

        #expect(
            await beforeMutator
                .resolutionCalls.isEmpty
        )
        #expect(
            before.model.status(
                for: baseline
            )?
                .phase == .idle
        )

        let duringMutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .success(
                            resolutionDiscussion(
                                id: "thread",
                                resolved: true
                            )
                        ),
                    ],
                ],
                gatedResolutionIDs: [
                    "thread",
                ]
            )
        let during =
            try ResolutionModelContext(
                discussions: [baseline],
                mutator: duringMutator
            )
        let cancelledDuring = Task {
            await during.model.toggle(
                baseline
            )
        }
        await duringMutator
            .waitUntilResolutionStarts(
                discussionID: "thread"
            )
        cancelledDuring.cancel()
        await cancelledDuring.value

        let status = try #require(
            during.model.status(
                for: baseline
            )
        )
        #expect(
            status.phase
                == .deliveryUnknown
        )
        #expect(status.isResolved)
        #expect(
            status.failure
                == .mutation(
                    .request(
                        .api(.cancelled)
                    ),
                    certainty:
                        .deliveryUnknown
                )
        )
        #expect(
            await duringMutator
                .resolutionCalls.count == 1
        )
        #expect(
            during.state.reconciled
                .isEmpty
        )
    }

    @Test("The same discussion ID stays isolated between account-scoped models")
    @MainActor
    func isolatesAccounts() async throws {
        let baseline =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let firstFailure =
            GitLabDiscussionMutationError
                .request(
                    .api(
                        .server(
                            statusCode: 503
                        )
                    )
                )
        let firstMutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .failure(firstFailure),
                    ],
                ]
            )
        let secondResolved =
            resolutionDiscussion(
                id: "thread",
                resolved: true
            )
        let secondMutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .success(
                            secondResolved
                        ),
                    ],
                ]
            )
        let first =
            try ResolutionModelContext(
                discussions: [baseline],
                userID: 9,
                mutator: firstMutator
            )
        let second =
            try ResolutionModelContext(
                discussions: [baseline],
                userID: 10,
                mutator: secondMutator
            )

        await first.model.toggle(baseline)
        await second.model.toggle(baseline)

        #expect(
            first.model.status(
                for: baseline
            )?
                .phase
                == .deliveryUnknown
        )
        #expect(
            second.model.status(
                for: secondResolved
            )?
                .phase == .idle
        )
        #expect(
            first.state.reconciled
                .isEmpty
        )
        #expect(
            second.state.reconciled
                == [secondResolved]
        )
        #expect(
            first.model.accountID
                != second.model.accountID
        )
    }

    @Test("Exposes resolution authentication failures to the account session")
    @MainActor
    func exposesAuthenticationFailure()
        async throws
    {
        let baseline =
            resolutionDiscussion(
                id: "thread",
                resolved: false
            )
        let authenticationError =
            GitLabSessionClientError.api(
                .unauthenticated
            )
        let mutator =
            ResolutionRecordingMutator(
                resolutionResults: [
                    "thread": [
                        .failure(
                            .request(
                                authenticationError
                            )
                        ),
                    ],
                ]
            )
        let context =
            try ResolutionModelContext(
                discussions: [baseline],
                mutator: mutator
            )

        await context.model.toggle(
            baseline
        )

        #expect(
            context.model
                .authenticationFailure
                == authenticationError
        )
    }
}

private struct ResolutionCall:
    Equatable,
    Sendable
{
    let discussionID: String
    let resolved: Bool
}

@MainActor
private final class ResolutionModelState {
    var current:
        [String: GitLabDiscussion]
    var reconciled:
        [GitLabDiscussion] = []
    var readinessRefreshCount = 0
    var gatesReadiness = false
    var isAccountCurrent = true
    private var readinessRefreshStarted =
        false
    private var readinessRefreshReleased =
        false
    private var readinessStartWaiters:
        [CheckedContinuation<Void, Never>] =
            []
    private var readinessReleaseWaiter:
        CheckedContinuation<Void, Never>?

    init(
        discussions: [GitLabDiscussion]
    ) {
        current = Dictionary(
            uniqueKeysWithValues:
                discussions.map {
                    ($0.id, $0)
                }
        )
    }

    func refreshReadiness() async {
        readinessRefreshCount += 1
        guard gatesReadiness else {
            return
        }

        readinessRefreshStarted = true
        for waiter in readinessStartWaiters {
            waiter.resume()
        }
        readinessStartWaiters.removeAll()

        guard !readinessRefreshReleased else {
            return
        }
        await withCheckedContinuation {
            readinessReleaseWaiter = $0
        }
    }

    func waitUntilReadinessRefreshStarts()
        async
    {
        guard !readinessRefreshStarted else {
            return
        }
        await withCheckedContinuation {
            readinessStartWaiters.append($0)
        }
    }

    func releaseReadinessRefresh() {
        readinessRefreshReleased = true
        readinessReleaseWaiter?.resume()
        readinessReleaseWaiter = nil
    }
}

@MainActor
private struct ResolutionModelContext {
    let state: ResolutionModelState
    let model:
        GitLabDiscussionResolutionModel

    init(
        discussions: [GitLabDiscussion],
        userID: Int = 9,
        apiAccess:
            GitLabAPIAccess = .readWrite,
        mutator:
            any GitLabDiscussionMutating
    ) throws {
        let state =
            ResolutionModelState(
                discussions: discussions
            )
        self.state = state
        model =
            GitLabDiscussionResolutionModel(
                accountID:
                    GitLabAccountID(
                        host:
                            try GitLabHost(
                                "https://gitlab.example.com"
                            ),
                        userID: userID
                    ),
                route:
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                apiAccess: apiAccess,
                mutator: mutator,
                isAccountCurrent: {
                    state.isAccountCurrent
                },
                currentDiscussion: {
                    state.current[$0]
                },
                reconcile: {
                    discussion in
                    guard
                        state.current[
                            discussion.id
                        ] != nil
                    else {
                        return false
                    }
                    state.current[
                        discussion.id
                    ] = discussion
                    state.reconciled.append(
                        discussion
                    )
                    return true
                },
                refreshReadiness: {
                    await state
                        .refreshReadiness()
                }
            )
    }
}

private actor ResolutionRecordingMutator:
    GitLabDiscussionMutating
{
    private var resolutionResults:
        [
            String:
                [
                    Result<
                        GitLabDiscussion,
                        GitLabDiscussionMutationError
                    >
                ]
        ]
    private var readResults:
        [
            String:
                [
                    Result<
                        GitLabDiscussion,
                        GitLabDiscussionMutationError
                    >
                ]
        ]
    private let gatedResolutionIDs:
        Set<String>
    private var startedResolutionIDs:
        Set<String> = []
    private var startWaiters:
        [
            String:
                [
                    CheckedContinuation<
                        Void,
                        Never
                    >
                ]
        ] = [:]
    private var releaseWaiters:
        [
            String:
                CheckedContinuation<
                    Void,
                    Never
                >
        ] = [:]
    private var releasedResolutionIDs:
        Set<String> = []

    private(set) var resolutionCalls:
        [ResolutionCall] = []
    private(set) var readDiscussionIDs:
        [String] = []

    init(
        resolutionResults:
            [
                String:
                    [
                        Result<
                            GitLabDiscussion,
                            GitLabDiscussionMutationError
                        >
                    ]
            ] = [:],
        readResults:
            [
                String:
                    [
                        Result<
                            GitLabDiscussion,
                            GitLabDiscussionMutationError
                        >
                    ]
            ] = [:],
        gatedResolutionIDs:
            Set<String> = []
    ) {
        self.resolutionResults =
            resolutionResults
        self.readResults = readResults
        self.gatedResolutionIDs =
            gatedResolutionIDs
    }

    func loadMergeRequestDiscussion(
        at route: GitLabMergeRequestRoute,
        discussionID: String
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        readDiscussionIDs.append(
            discussionID
        )
        return try takeResult(
            from: &readResults,
            discussionID: discussionID
        )
    }

    func setMergeRequestDiscussionResolution(
        at route: GitLabMergeRequestRoute,
        discussionID: String,
        resolved: Bool
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        resolutionCalls.append(
            ResolutionCall(
                discussionID:
                    discussionID,
                resolved: resolved
            )
        )
        startedResolutionIDs.insert(
            discussionID
        )
        startWaiters
            .removeValue(
                forKey: discussionID
            )?
            .forEach {
                $0.resume()
            }

        if
            gatedResolutionIDs
                .contains(discussionID),
            !releasedResolutionIDs
                .contains(discussionID)
        {
            await withTaskCancellationHandler {
                await withCheckedContinuation {
                    continuation in
                    releaseWaiters[
                        discussionID
                    ] = continuation
                }
            } onCancel: {
                Task {
                    await self
                        .releaseResolution(
                            discussionID:
                                discussionID
                        )
                }
            }
        }

        guard !Task.isCancelled else {
            throw .request(
                .api(.cancelled)
            )
        }
        return try takeResult(
            from: &resolutionResults,
            discussionID: discussionID
        )
    }

    func waitUntilResolutionStarts(
        discussionID: String
    ) async {
        guard
            !startedResolutionIDs
                .contains(discussionID)
        else {
            return
        }
        await withCheckedContinuation {
            continuation in
            startWaiters[
                discussionID,
                default: []
            ].append(continuation)
        }
    }

    func releaseResolution(
        discussionID: String
    ) {
        releasedResolutionIDs.insert(
            discussionID
        )
        releaseWaiters
            .removeValue(
                forKey: discussionID
            )?
            .resume()
    }

    func createDiscussion(
        for resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        throw .request(
            .api(.invalidResponse)
        )
    }

    func createDiffDiscussion(
        for route: GitLabMergeRequestRoute,
        body: GitLabDiscussionCommentBody,
        position: GitLabDiffLinePosition
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        throw .request(
            .api(.invalidResponse)
        )
    }

    func reply(
        to discussionID: String,
        in resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussionNote
    {
        throw .request(
            .api(.invalidResponse)
        )
    }

    private func takeResult(
        from results:
            inout [
                String:
                    [
                        Result<
                            GitLabDiscussion,
                            GitLabDiscussionMutationError
                        >
                    ]
            ],
        discussionID: String
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        guard
            var values =
                results[discussionID],
            !values.isEmpty
        else {
            throw .request(
                .api(.invalidResponse)
            )
        }
        let result =
            values.removeFirst()
        results[discussionID] = values
        return try result.get()
    }
}

private func resolutionDiscussion(
    id: String,
    resolved: Bool?,
    resolvedBy: GitLabAPIUser? = nil,
    resolvedAt: Date? = nil
) -> GitLabDiscussion {
    makeTestDiscussion(
        id: id,
        notes: [
            makeTestDiscussionNote(
                type: "DiscussionNote",
                resolvable: true,
                resolved: resolved,
                resolvedBy: resolvedBy,
                resolvedAt: resolvedAt
            ),
        ]
    )
}
