import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab merge request approval rule management")
struct GitLabMergeRequestApprovalRuleManagementTests {
    @Test("Loads only active candidates not already direct or eligible")
    func filtersMemberCandidates() async {
        let rule = makeEditableRule()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(rule),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 7),
                            makeMember(id: 8),
                            makeMember(id: 9),
                            makeMember(
                                id: 10,
                                state: "blocked"
                            ),
                        ])
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )

        await fixture.model
            .beginAddingApprover(
                to: rule
            )

        #expect(
            fixture.model.selectedRule?
                .id == 41
        )
        #expect(
            fixture.model.availableMembers
                .map(\.id) == [9]
        )
        #expect(
            await service.memberSearches
                == [nil]
        )
    }

    @Test("A successful member retry clears only the recovered member error")
    func clearsRecoveredMemberFailure() async {
        let rule = makeEditableRule()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(rule),
                ],
                memberResults: [
                    .failure(
                        .api(
                            .connectivity(
                                .timedOut
                            )
                        )
                    ),
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )

        await fixture.model
            .beginAddingApprover(
                to: rule
            )
        #expect(
            fixture.model.failure
                != nil
        )

        await fixture.model
            .searchMembers("")

        #expect(fixture.model.failure == nil)
        #expect(
            fixture.model.memberOptionsError
                == nil
        )
        #expect(
            fixture.model.availableMembers
                .map(\.id) == [9]
        )
    }

    @Test(
        "Locks unsafe rule kinds before member loading",
        arguments: [
            makeEditableRule(
                ruleType: "code_owner"
            ),
            makeEditableRule(
                ruleType: "report_approver"
            ),
            makeEditableRule(
                ruleType: "any_approver"
            ),
            makeEditableRule(
                ruleType: "future_rule"
            ),
            makeEditableRule(
                containsHiddenGroups: true
            ),
            makeEditableRule(
                users: nil
            ),
            makeEditableRule(
                groups: nil
            ),
            makeEditableRule(
                name: nil
            ),
            makeEditableRule(
                approvalsRequired: nil
            ),
            makeEditableRule(
                containsHiddenGroups: nil
            ),
        ]
    )
    func locksUnsafeRules(
        rule: GitLabMergeRequestApprovalRule
    ) async {
        let service =
            RuleManagementService()
        let fixture = makeRuleFixture(
            service: service
        )

        await fixture.model
            .beginAddingApprover(
                to: rule
            )

        #expect(
            fixture.model.selectedRule
                == nil
        )
        #expect(
            fixture.model.failure
                != nil
        )
        #expect(await service.ruleReadCount == 0)
        #expect(await service.memberReadCount == 0)
    }

    @Test("Read-only access loads no rule or members")
    func blocksReadOnlyAccess() async {
        let service =
            RuleManagementService()
        let fixture = makeRuleFixture(
            service: service,
            apiAccess: .readOnly
        )

        await fixture.model
            .beginAddingApprover(
                to: makeEditableRule()
            )

        #expect(
            fixture.model.failure
                == .readOnly
        )
        #expect(await service.ruleReadCount == 0)
        #expect(await service.memberReadCount == 0)
        #expect(await service.replacements.isEmpty)
    }

    @Test("An account change during the exact rule read publishes no picker state")
    func isolatesAccountGeneration() async {
        let baseline = makeEditableRule()
        let gate = RuleManagementGate()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                ],
                ruleReadGate: gate,
                gatedRuleRead: 1
            )
        let fixture = makeRuleFixture(
            service: service
        )

        let task = Task { @MainActor in
            await fixture.model
                .beginAddingApprover(
                    to: baseline
                )
        }
        await gate.waitUntilEntered()
        fixture.isCurrent = false
        await gate.open()
        await task.value

        #expect(
            fixture.model.selectedRule
                == nil
        )
        #expect(await service.memberReadCount == 0)
        #expect(await service.replacements.isEmpty)
    }

    @Test("Closing during member loading clears superseded loading state")
    func cancelsInFlightPickerLoading() async {
        let baseline = makeEditableRule()
        let gate = RuleManagementGate()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                memberReadGate: gate,
                gatedMemberRead: 1
            )
        let fixture = makeRuleFixture(
            service: service
        )

        let task = Task { @MainActor in
            await fixture.model
                .beginAddingApprover(
                    to: baseline
                )
        }
        await gate.waitUntilEntered()
        fixture.model.cancelRuleAddition()
        await gate.open()
        await task.value

        #expect(
            fixture.model.selectedRule
                == nil
        )
        #expect(
            fixture.model.availableMembers
                .isEmpty
        )
        #expect(
            fixture.model.isLoadingRule
                == false
        )
        #expect(
            fixture.model.isLoadingMembers
                == false
        )
    }

    @Test("Preserves every fresh member, group, name, and count")
    func submitsCompleteReplacement() async {
        let baseline = makeEditableRule()
        let applied =
            makeEditableRule(
                users: [
                    makeRuleUser(id: 7),
                    makeRuleUser(id: 9),
                ]
            )
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(baseline),
                    .success(applied),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                updateResults: [
                    .success(applied),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )

        await fixture.model
            .beginAddingApprover(
                to: baseline
            )
        let member = try! #require(
            fixture.model
                .availableMembers.first
        )
        fixture.model.selectApprover(
            member
        )
        await fixture.model
            .confirmRuleAddition()

        let replacement = try! #require(
            await service.replacements.first
        )
        #expect(replacement.name == "Security")
        #expect(
            replacement.approvalsRequired == 2
        )
        #expect(
            replacement.userIDs == [7, 9]
        )
        #expect(
            replacement.groupIDs == [19]
        )
        #expect(
            replacement.removeHiddenGroups
                == false
        )
        #expect(
            fixture.model.failure == nil
        )
        #expect(
            fixture.model.selectedRule?
                .users?.map(\.id) == [7, 9]
        )
    }

    @Test("Canceling confirmation keeps the selected rule and member choices")
    func cancelsOnlyRuleConfirmation() async {
        let baseline = makeEditableRule()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )
        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )

        fixture.model
            .cancelRuleAdditionConfirmation()

        #expect(
            fixture.model
                .ruleAdditionConfirmation
                == nil
        )
        #expect(
            fixture.model.selectedRule?
                .id == baseline.id
        )
        #expect(
            fixture.model.availableMembers
                .map(\.id) == [9]
        )
    }

    @Test("A changed second exact rule sends no update")
    func rejectsChangedFreshRule() async {
        let baseline = makeEditableRule()
        let changed =
            makeEditableRule(
                approvalsRequired: 3
            )
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(changed),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )

        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )
        await fixture.model
            .confirmRuleAddition()

        #expect(
            fixture.model.failure
                == .ruleChanged
        )
        #expect(await service.replacements.isEmpty)
    }

    @Test("A newly direct or eligible selected member sends no update")
    func rejectsNoLongerAvailableMember() async {
        let baseline = makeEditableRule()
        let changed =
            makeEditableRule(
                eligibleApprovers: [
                    makeRuleUser(id: 8),
                    makeRuleUser(id: 9),
                ]
            )
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(changed),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )

        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )
        await fixture.model
            .confirmRuleAddition()

        #expect(
            fixture.model.failure
                == .memberUnavailable
        )
        #expect(await service.replacements.isEmpty)
    }

    @Test("Maps a definite rule permission denial without retaining an unknown mutation")
    func mapsPermissionDenial() async {
        let baseline = makeEditableRule()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(baseline),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                updateResults: [
                    .failure(
                        .api(.forbidden)
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )

        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )
        await fixture.model
            .confirmRuleAddition()

        #expect(
            fixture.model.failure
                == .permissionDenied
        )
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
        #expect(await service.replacements.count == 1)
    }

    @Test("Rapid confirmations send exactly one rule replacement")
    func ignoresRapidConfirmations() async {
        let baseline = makeEditableRule()
        let applied =
            makeEditableRule(
                users: [
                    makeRuleUser(id: 7),
                    makeRuleUser(id: 9),
                ]
            )
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(baseline),
                    .success(applied),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                updateResults: [
                    .success(applied),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )
        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )

        async let first: Void =
            fixture.model
                .confirmRuleAddition()
        async let second: Void =
            fixture.model
                .confirmRuleAddition()
        _ = await (first, second)

        #expect(await service.replacements.count == 1)
        #expect(fixture.model.failure == nil)
    }

    @Test("A response that drops prior membership remains unknown until an exact stale check")
    func rejectsAuthoritativeDataLoss() async {
        let baseline = makeEditableRule()
        let lossy =
            makeEditableRule(
                users: [
                    makeRuleUser(id: 9),
                ]
            )
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(baseline),
                    .success(lossy),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                updateResults: [
                    .success(lossy),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )
        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )

        await fixture.model
            .confirmRuleAddition()

        #expect(
            fixture.model.failure
                == .deliveryUnknown
        )
        #expect(
            fixture.model.hasUnresolvedMutation
        )

        await fixture.model.checkGitLab()

        #expect(
            fixture.model.failure
                == .ruleChanged
        )
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
    }

    @Test("Cancellation during the second exact read sends no replacement")
    func cancelsBeforeRuleWrite() async {
        let baseline = makeEditableRule()
        let gate = RuleManagementGate()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(baseline),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                ruleReadGate: gate,
                gatedRuleRead: 2
            )
        let fixture = makeRuleFixture(
            service: service
        )
        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )

        let task = Task { @MainActor in
            await fixture.model
                .confirmRuleAddition()
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.open()
        await task.value

        #expect(await service.replacements.isEmpty)
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
        #expect(fixture.model.phase == .idle)
    }

    @Test("Cancellation after sending the replacement requires an explicit exact check")
    func retainsCancelledRuleWrite() async {
        let baseline = makeEditableRule()
        let applied =
            makeEditableRule(
                users: [
                    makeRuleUser(id: 7),
                    makeRuleUser(id: 9),
                ]
            )
        let gate = RuleManagementGate()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(baseline),
                    .success(applied),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                updateResults: [
                    .failure(
                        .api(.cancelled)
                    ),
                ],
                updateGate: gate,
                gatedUpdate: 1
            )
        let fixture = makeRuleFixture(
            service: service
        )
        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )

        let task = Task { @MainActor in
            await fixture.model
                .confirmRuleAddition()
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.open()
        await task.value

        #expect(await service.replacements.count == 1)
        #expect(
            fixture.model.failure
                == .deliveryUnknown
        )
        #expect(
            fixture.model.hasUnresolvedMutation
        )

        await fixture.model.checkGitLab()

        #expect(fixture.model.failure == nil)
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
    }

    @Test("Unknown rule delivery reconciles an applied addition")
    func reconcilesUnknownRuleDelivery() async {
        let baseline = makeEditableRule()
        let applied =
            makeEditableRule(
                users: [
                    makeRuleUser(id: 7),
                    makeRuleUser(id: 9),
                ]
            )
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                    .success(baseline),
                    .success(applied),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                ],
                updateResults: [
                    .failure(
                        .api(
                            .server(
                                statusCode: 503
                            )
                        )
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )

        await selectMember(
            id: 9,
            rule: baseline,
            fixture: fixture
        )
        await fixture.model
            .confirmRuleAddition()

        #expect(
            fixture.model.failure
                == .deliveryUnknown
        )
        #expect(
            fixture.model.hasUnresolvedMutation
        )

        await fixture.model.checkGitLab()

        #expect(fixture.model.failure == nil)
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
        #expect(
            fixture.model.selectedRule?
                .users?.map(\.id) == [7, 9]
        )
    }

    @Test("Unknown rule delivery distinguishes unapplied and stale state")
    func classifiesUnknownRuleDelivery() async {
        let baseline = makeEditableRule()
        let stale =
            makeEditableRule(
                groups: [
                    makeRuleGroup(id: 20),
                ]
            )

        for (checked, expected) in [
            (
                baseline,
                GitLabMergeRequestApprovalManagementFailure
                    .notApplied
            ),
            (
                stale,
                .ruleChanged
            ),
        ] {
            let service =
                RuleManagementService(
                    ruleResults: [
                        .success(baseline),
                        .success(baseline),
                        .success(checked),
                    ],
                    memberResults: [
                        .success(
                            memberPage([
                                makeMember(id: 9),
                            ])
                        ),
                    ],
                    updateResults: [
                        .failure(
                            .api(
                                .connectivity(
                                    .networkConnectionLost
                                )
                            )
                        ),
                    ]
                )
            let fixture = makeRuleFixture(
                service: service
            )

            await selectMember(
                id: 9,
                rule: baseline,
                fixture: fixture
            )
            await fixture.model
                .confirmRuleAddition()
            await fixture.model.checkGitLab()

            #expect(
                fixture.model.failure
                    == expected
            )
            #expect(
                fixture.model
                    .hasUnresolvedMutation
                    == false
            )
        }
    }

    @Test("Paginates member search without mixing search generations")
    func paginatesMemberSearch() async {
        let baseline = makeEditableRule()
        let nextURL = URL(
            string:
                "https://gitlab.example.com/api/v4/projects/42/members/all?page=2"
        )!
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                ],
                memberResults: [
                    .success(
                        memberPage(
                            [makeMember(id: 9)],
                            nextPageURL: nil
                        )
                    ),
                    .success(
                        memberPage(
                            [makeMember(id: 10)],
                            nextPageURL: nextURL
                        )
                    ),
                    .success(
                        memberPage([
                            makeMember(id: 11),
                        ])
                    ),
                ]
            )
        let fixture = makeRuleFixture(
            service: service
        )
        await fixture.model
            .beginAddingApprover(
                to: baseline
            )

        await fixture.model.searchMembers(
            " ada "
        )
        await fixture.model
            .loadNextMembersPage()

        #expect(
            fixture.model.availableMembers
                .map(\.id) == [10, 11]
        )
        #expect(
            await service.memberSearches
                == [
                    nil,
                    "ada",
                    "ada",
                ]
        )
        #expect(
            await service.memberNextURLs
                == [
                    nil,
                    nil,
                    nextURL,
                ]
        )
        #expect(
            await service.memberProjectIDs
                == [42, 42, 42]
        )
    }

    @Test("A newer member search discards an older in-flight response")
    func isolatesMemberSearchGenerations() async {
        let baseline = makeEditableRule()
        let gate = RuleManagementGate()
        let service =
            RuleManagementService(
                ruleResults: [
                    .success(baseline),
                ],
                memberResults: [
                    .success(
                        memberPage([
                            makeMember(id: 9),
                        ])
                    ),
                    .success(
                        memberPage([
                            makeMember(id: 10),
                        ])
                    ),
                    .success(
                        memberPage([
                            makeMember(id: 11),
                        ])
                    ),
                ],
                memberReadGate: gate,
                gatedMemberRead: 2
            )
        let fixture = makeRuleFixture(
            service: service
        )
        await fixture.model
            .beginAddingApprover(
                to: baseline
            )

        let oldSearch = Task { @MainActor in
            await fixture.model
                .searchMembers("old")
        }
        await gate.waitUntilEntered()
        await fixture.model
            .searchMembers("new")
        await gate.open()
        await oldSearch.value

        #expect(
            fixture.model.availableMembers
                .map(\.id) == [11]
        )
        #expect(
            await service.memberSearches
                == [
                    nil,
                    "old",
                    "new",
                ]
        )
    }
}

@MainActor
private func selectMember(
    id: Int,
    rule: GitLabMergeRequestApprovalRule,
    fixture: RuleManagementFixture
) async {
    await fixture.model
        .beginAddingApprover(to: rule)
    let member = fixture.model
        .availableMembers
        .first { $0.id == id }
    if let member {
        fixture.model.selectApprover(
            member
        )
    }
}

@MainActor
private final class RuleManagementFixture {
    var mergeRequest = makeRuleMergeRequest()
    var summary = makeRuleSummary()
    var isCurrent = true
    private let service:
        any GitLabMergeRequestApprovalServing
    private let accountID =
        makeRuleAccountID()
    private let apiAccess:
        GitLabAPIAccess
    lazy var model =
        GitLabMergeRequestApprovalManagementModel(
            route: mergeRequest.route,
            accountID: accountID,
            apiAccess: apiAccess,
            service: service,
            currentMergeRequest: {
                [weak self] in
                self?.mergeRequest
            },
            currentApprovalSummary: {
                [weak self] in
                self?.summary
            },
            isAccountCurrent: {
                [weak self] in
                self?.isCurrent == true
            },
            onMergeRequestReconciled: {
                [weak self] value in
                self?.mergeRequest = value
            },
            onApprovalSummaryReconciled: {
                [weak self] value in
                self?.summary = value
            }
        )

    init(
        service:
            any GitLabMergeRequestApprovalServing,
        apiAccess:
            GitLabAPIAccess = .readWrite
    ) {
        self.service = service
        self.apiAccess = apiAccess
    }
}

@MainActor
private func makeRuleFixture(
    service:
        any GitLabMergeRequestApprovalServing,
    apiAccess:
        GitLabAPIAccess = .readWrite
) -> RuleManagementFixture {
    RuleManagementFixture(
        service: service,
        apiAccess: apiAccess
    )
}

private actor RuleManagementService:
    GitLabMergeRequestApprovalServing
{
    private var ruleResults:
        [
            Result<
                GitLabMergeRequestApprovalRule,
                GitLabSessionClientError
            >
        ]
    private var memberResults:
        [
            Result<
                GitLabResourcePage<
                    GitLabProjectMember
                >,
                GitLabSessionClientError
            >
        ]
    private var updateResults:
        [
            Result<
                GitLabMergeRequestApprovalRule,
                GitLabSessionClientError
            >
        ]

    private(set) var ruleReadCount = 0
    private(set) var memberReadCount = 0
    private(set) var memberSearches:
        [String?] = []
    private(set) var memberNextURLs:
        [URL?] = []
    private(set) var memberProjectIDs:
        [Int] = []
    private(set) var replacements:
        [
            GitLabMergeRequestApprovalRuleReplacement
        ] = []
    private let ruleReadGate:
        RuleManagementGate?
    private let gatedRuleRead: Int?
    private let memberReadGate:
        RuleManagementGate?
    private let gatedMemberRead: Int?
    private let updateGate:
        RuleManagementGate?
    private let gatedUpdate: Int?
    private var updateCount = 0

    init(
        ruleResults:
            [
                Result<
                    GitLabMergeRequestApprovalRule,
                    GitLabSessionClientError
                >
            ] = [],
        memberResults:
            [
                Result<
                    GitLabResourcePage<
                        GitLabProjectMember
                    >,
                    GitLabSessionClientError
                >
            ] = [],
        updateResults:
            [
                Result<
                    GitLabMergeRequestApprovalRule,
                    GitLabSessionClientError
                >
            ] = [],
        ruleReadGate:
            RuleManagementGate? = nil,
        gatedRuleRead: Int? = nil,
        memberReadGate:
            RuleManagementGate? = nil,
        gatedMemberRead: Int? = nil,
        updateGate:
            RuleManagementGate? = nil,
        gatedUpdate: Int? = nil
    ) {
        self.ruleResults = ruleResults
        self.memberResults = memberResults
        self.updateResults = updateResults
        self.ruleReadGate = ruleReadGate
        self.gatedRuleRead = gatedRuleRead
        self.memberReadGate =
            memberReadGate
        self.gatedMemberRead =
            gatedMemberRead
        self.updateGate = updateGate
        self.gatedUpdate = gatedUpdate
    }

    func loadLatestMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async -> GitLabMergeRequest {
        makeRuleMergeRequest()
    }

    func loadApprovalSummary(
        at route: GitLabMergeRequestRoute
    ) async -> GitLabMergeRequestApprovalSummary {
        makeRuleSummary()
    }

    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute
    ) async -> GitLabMergeRequestApprovalDetailsAvailability {
        .unavailable
    }

    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalDetailsAvailability
                >
            ) async -> Void
    ) async {
        await onResponse(
            GitLabAPIResponseEvent(
                value: .unavailable,
                metadata:
                    GitLabResponseMetadata(),
                source: .network
            )
        )
    }

    func loadApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule
    {
        ruleReadCount += 1
        let result = take(
            from: &ruleResults
        )
        if
            ruleReadCount
                == gatedRuleRead,
            let ruleReadGate
        {
            await ruleReadGate.wait()
        }
        return try resolve(result)
    }

    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        memberReadCount += 1
        memberProjectIDs.append(projectID)
        memberSearches.append(search)
        memberNextURLs.append(nextPageURL)
        let result = take(
            from: &memberResults
        )
        if
            memberReadCount
                == gatedMemberRead,
            let memberReadGate
        {
            await memberReadGate.wait()
        }
        return try resolve(result)
    }

    func approve(
        at route: GitLabMergeRequestRoute,
        sha: String
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        throw .api(.invalidResponse)
    }

    func unapprove(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        throw .api(.invalidResponse)
    }

    func updateApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int,
        replacement:
            GitLabMergeRequestApprovalRuleReplacement
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule
    {
        replacements.append(
            replacement
        )
        updateCount += 1
        let result = take(
            from: &updateResults
        )
        if
            updateCount == gatedUpdate,
            let updateGate
        {
            await updateGate.wait()
        }
        return try resolve(result)
    }

    private func take<Value>(
        from values:
            inout [
                Result<
                    Value,
                    GitLabSessionClientError
                >
            ]
    ) -> Result<
        Value,
        GitLabSessionClientError
    >
    {
        guard !values.isEmpty else {
            return .failure(
                .api(.invalidResponse)
            )
        }
        return values.removeFirst()
    }

    private func resolve<Value>(
        _ result:
            Result<
                Value,
                GitLabSessionClientError
            >
    ) throws(GitLabSessionClientError)
        -> Value
    {
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }
}

private actor RuleManagementGate {
    private var entered = false
    private var isOpen = false
    private var entryWaiters:
        [CheckedContinuation<Void, Never>] =
            []
    private var operationWaiters:
        [CheckedContinuation<Void, Never>] =
            []

    func wait() async {
        entered = true
        let waitingForEntry =
            entryWaiters
        entryWaiters.removeAll()
        waitingForEntry.forEach {
            $0.resume()
        }

        guard !isOpen else {
            return
        }
        await withCheckedContinuation {
            operationWaiters.append($0)
        }
    }

    func waitUntilEntered() async {
        guard !entered else {
            return
        }
        await withCheckedContinuation {
            entryWaiters.append($0)
        }
    }

    func open() {
        isOpen = true
        let waiters = operationWaiters
        operationWaiters.removeAll()
        waiters.forEach {
            $0.resume()
        }
    }
}

private nonisolated func makeEditableRule(
    ruleType: String? = "regular",
    name: String? = "Security",
    eligibleApprovers:
        [GitLabAPIUser]? = [
            makeRuleUser(id: 8),
        ],
    approvalsRequired: Int? = 2,
    users:
        [GitLabAPIUser]? = [
            makeRuleUser(id: 7),
        ],
    groups:
        [GitLabMergeRequestApprovalRuleGroup]? = [
            makeRuleGroup(id: 19),
        ],
    containsHiddenGroups: Bool? = false
) -> GitLabMergeRequestApprovalRule {
    GitLabMergeRequestApprovalRule(
        id: 41,
        name: name,
        ruleType: ruleType,
        eligibleApprovers:
            eligibleApprovers,
        approvalsRequired:
            approvalsRequired,
        users: users,
        groups: groups,
        containsHiddenGroups:
            containsHiddenGroups,
        approvedBy: [],
        approved: false,
        overridden: false
    )
}

private nonisolated func makeRuleUser(
    id: Int
) -> GitLabAPIUser {
    makeTestAPIUser(
        id: id,
        username: "user-\(id)",
        name: "User \(id)"
    )
}

private nonisolated func makeRuleGroup(
    id: Int
) -> GitLabMergeRequestApprovalRuleGroup {
    GitLabMergeRequestApprovalRuleGroup(
        id: id,
        name: "Group \(id)",
        path: "group-\(id)",
        avatarURL: nil,
        webURL: nil
    )
}

private nonisolated func makeMember(
    id: Int,
    state: String = "active"
) -> GitLabProjectMember {
    GitLabProjectMember(
        id: id,
        username: "user-\(id)",
        name: "User \(id)",
        state: state,
        avatarURL: nil,
        webURL: nil,
        accessLevel: 30
    )
}

private nonisolated func memberPage(
    _ members: [GitLabProjectMember],
    nextPageURL: URL? = nil
) -> GitLabResourcePage<
    GitLabProjectMember
> {
    GitLabResourcePage(
        items: members,
        nextPageURL: nextPageURL
    )
}

private nonisolated func makeRuleMergeRequest()
    -> GitLabMergeRequest
{
    makeTestMergeRequest(
        sha: "head",
        diffRefs:
            GitLabMergeRequestDiffRefs(
                baseSHA: "base",
                startSHA: "start",
                headSHA: "head"
            ),
        detailedMergeStatus:
            "mergeable"
    )
}

private nonisolated func makeRuleSummary()
    -> GitLabMergeRequestApprovalSummary
{
    GitLabMergeRequestApprovalSummary(
        approved: false,
        approvalsRequired: 2,
        approvalsLeft: 2,
        approvedBy: []
    )
}

private nonisolated func makeRuleAccountID()
    -> GitLabAccountID
{
    GitLabAccountID(
        host:
            try! GitLabHost(
                "https://gitlab.example.com"
            ),
        userID: 7
    )
}
