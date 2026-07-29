#if DEBUG
    import SwiftUI

    struct
        GitLabMergeRequestApprovalFixtureView:
        View
    {
        private let accountID:
            GitLabAccountID
        private let summary:
            GitLabMergeRequestApprovalSummary
        @State private var model:
            GitLabMergeRequestApprovalManagementModel

        @MainActor
        init() {
            let fixture =
                GitLabMergeRequestApprovalFixture()
            let accountID =
                GitLabAccountID(
                    host:
                        try! GitLabHost(
                            "gitlab.example.com"
                        ),
                    userID: 7
                )
            self.accountID = accountID
            summary = fixture.summary
            _model = State(
                initialValue:
                    GitLabMergeRequestApprovalManagementModel(
                        route:
                            fixture
                            .mergeRequest
                            .route,
                        accountID:
                            accountID,
                        apiAccess: .readWrite,
                        service: fixture,
                        currentMergeRequest: {
                            fixture
                                .mergeRequest
                        },
                        currentApprovalSummary: {
                            fixture.summary
                        },
                        isAccountCurrent: {
                            true
                        },
                        onMergeRequestReconciled: {
                            _ in
                        },
                        onApprovalSummaryReconciled: {
                            _ in
                        }
                    )
            )
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    GitLabDetailScrollContent(
                        bottomPadding: 24
                    ) {
                        Text(
                            "Approval UI fixture"
                        )
                        .font(.title2.bold())
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                        GitLabMergeRequestApprovalManagementView(
                            approvalState:
                                .loaded(
                                    .available(
                                        summary
                                    )
                                ),
                            model: model,
                            accountID:
                                accountID
                        )
                    }
                }
                .navigationTitle(
                    "Merge Request"
                )
                .navigationBarTitleDisplayMode(
                    .inline
                )
                .background(
                    Color(
                        uiColor:
                            .systemGroupedBackground
                    )
                )
            }
            .task {
                await model
                    .loadDetailsIfNeeded()
            }
        }
    }

    private nonisolated struct
        GitLabMergeRequestApprovalFixture:
        GitLabMergeRequestApprovalServing,
        Sendable
    {
        let mergeRequest:
            GitLabMergeRequest
        let summary:
            GitLabMergeRequestApprovalSummary
        let details:
            GitLabMergeRequestApprovalDetails
        let rule:
            GitLabMergeRequestApprovalRule
        let members:
            [GitLabProjectMember]

        init() {
            let currentUser =
                Self.user(
                    id: 7,
                    name:
                        "Nitesh Balusu",
                    username: "nitesh"
                )
            let approver =
                Self.user(
                    id: 8,
                    name:
                        "Ada Lovelace",
                    username: "ada"
                )
            let eligible =
                Self.user(
                    id: 9,
                    name:
                        "Grace Hopper",
                    username: "grace"
                )
            let rule =
                GitLabMergeRequestApprovalRule(
                    id: 41,
                    name:
                        "Security review",
                    ruleType: "regular",
                    eligibleApprovers: [
                        approver,
                        currentUser,
                        eligible,
                    ],
                    approvalsRequired: 2,
                    users: [
                        approver,
                        eligible,
                    ],
                    groups: [],
                    containsHiddenGroups:
                        false,
                    approvedBy: [
                        approver
                    ],
                    approved: false,
                    overridden: true
                )
            self.rule = rule
            details =
                GitLabMergeRequestApprovalDetails(
                    approvalRulesOverwritten:
                        true,
                    rules: [
                        rule,
                        GitLabMergeRequestApprovalRule(
                            id: 42,
                            name:
                                "Code owners",
                            ruleType:
                                "code_owner",
                            eligibleApprovers: [
                                eligible
                            ],
                            approvalsRequired:
                                1,
                            users: [],
                            groups: [],
                            containsHiddenGroups:
                                false,
                            approvedBy: [],
                            approved: false,
                            overridden: false
                        ),
                    ]
                )
            summary =
                GitLabMergeRequestApprovalSummary(
                    approved: false,
                    approvalsRequired: 2,
                    approvalsLeft: 1,
                    approvedBy: [
                        GitLabMergeRequestApproval(
                            user: approver,
                            approvedAt:
                                Date(
                                    timeIntervalSince1970:
                                        1_785_328_496
                                )
                        ),
                    ]
                )
            mergeRequest =
                GitLabMergeRequest(
                    id: 101,
                    iid: 7,
                    projectID: 42,
                    title:
                        "Harden approval handling",
                    description: nil,
                    state: "opened",
                    draft: false,
                    legacyWorkInProgress:
                        nil,
                    labels: [],
                    author: currentUser,
                    assignees: [],
                    reviewers: [],
                    sourceBranch:
                        "approval-ui",
                    targetBranch: "main",
                    userNotesCount: 2,
                    createdAt:
                        Date(
                            timeIntervalSince1970:
                                1_785_000_000
                        ),
                    updatedAt:
                        Date(
                            timeIntervalSince1970:
                                1_785_328_496
                        ),
                    closedAt: nil,
                    mergedAt: nil,
                    webURL:
                        URL(
                            string:
                                "https://gitlab.example.com/group/project/-/merge_requests/7"
                        ),
                    references:
                        GitLabMergeRequestReferences(
                            short: "!7",
                            relative:
                                "project!7",
                            full:
                                "group/project!7"
                        ),
                    sha: "fixture-head",
                    diffRefs: nil,
                    changesCount: "3",
                    detailedMergeStatus:
                        "mergeable",
                    hasConflicts: false,
                    blockingDiscussionsResolved:
                        true,
                    headPipeline: nil
                )
            members = [
                Self.member(
                    id: 10,
                    name:
                        "Margaret Hamilton",
                    username:
                        "margaret"
                ),
                Self.member(
                    id: 11,
                    name:
                        "Katherine Johnson",
                    username:
                        "katherine"
                ),
            ]
        }

        @concurrent
        func loadLatestMergeRequest(
            at route:
                GitLabMergeRequestRoute
        ) async throws(
            GitLabSessionClientError
        ) -> GitLabMergeRequest {
            mergeRequest
        }

        @concurrent
        func loadApprovalSummary(
            at route:
                GitLabMergeRequestRoute
        ) async throws(
            GitLabSessionClientError
        )
            -> GitLabMergeRequestApprovalSummary
        {
            summary
        }

        @concurrent
        func loadApprovalDetails(
            at route:
                GitLabMergeRequestRoute
        ) async throws(
            GitLabSessionClientError
        )
            -> GitLabMergeRequestApprovalDetailsAvailability
        {
            .available(details)
        }

        @concurrent
        func loadApprovalDetails(
            at route:
                GitLabMergeRequestRoute,
            refreshBehavior:
                GitLabCacheRefreshBehavior,
            onResponse:
                @escaping @Sendable (
                    GitLabAPIResponseEvent<
                        GitLabMergeRequestApprovalDetailsAvailability
                    >
                ) async -> Void
        ) async throws(
            GitLabSessionClientError
        ) {
            await onResponse(
                GitLabAPIResponseEvent(
                    value:
                        .available(
                            details
                        ),
                    metadata:
                        GitLabResponseMetadata(),
                    source: .network
                )
            )
        }

        @concurrent
        func loadApprovalRule(
            at route:
                GitLabMergeRequestRoute,
            ruleID: Int
        ) async throws(
            GitLabSessionClientError
        )
            -> GitLabMergeRequestApprovalRule
        {
            rule
        }

        @concurrent
        func loadMembersPage(
            projectID: Int,
            search: String?,
            after nextPageURL: URL?
        ) async throws(
            GitLabSessionClientError
        )
            -> GitLabResourcePage<
                GitLabProjectMember
            >
        {
            let normalized =
                search?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()
            guard
                let normalized,
                !normalized.isEmpty
            else {
                return GitLabResourcePage(
                    items: members,
                    nextPageURL: nil
                )
            }
            return GitLabResourcePage(
                items:
                    members.filter {
                        $0.name
                            .lowercased()
                            .contains(
                                normalized
                            )
                            || $0.username
                            .lowercased()
                            .contains(
                                normalized
                            )
                    },
                nextPageURL: nil
            )
        }

        @concurrent
        func approve(
            at route:
                GitLabMergeRequestRoute,
            sha: String
        ) async throws(
            GitLabSessionClientError
        )
            -> GitLabMergeRequestApprovalSummary
        {
            summary
        }

        @concurrent
        func unapprove(
            at route:
                GitLabMergeRequestRoute
        ) async throws(
            GitLabSessionClientError
        )
            -> GitLabMergeRequestApprovalSummary
        {
            summary
        }

        @concurrent
        func updateApprovalRule(
            at route:
                GitLabMergeRequestRoute,
            ruleID: Int,
            replacement:
                GitLabMergeRequestApprovalRuleReplacement
        ) async throws(
            GitLabSessionClientError
        )
            -> GitLabMergeRequestApprovalRule
        {
            rule
        }

        private static func user(
            id: Int,
            name: String,
            username: String
        ) -> GitLabAPIUser {
            GitLabAPIUser(
                id: id,
                username: username,
                name: name,
                avatarURL: nil,
                webURL: nil
            )
        }

        private static func member(
            id: Int,
            name: String,
            username: String
        ) -> GitLabProjectMember {
            GitLabProjectMember(
                id: id,
                username: username,
                name: name,
                state: "active",
                avatarURL: nil,
                webURL: nil,
                accessLevel: 30
            )
        }
    }
#endif
