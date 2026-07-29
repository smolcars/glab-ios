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
        private let mode:
            GitLabMergeRequestApprovalFixtureMode
        @State private var model:
            GitLabMergeRequestApprovalManagementModel

        @MainActor
        init() {
            let mode =
                GitLabMergeRequestApprovalFixtureMode
                .current
            let fixture =
                GitLabMergeRequestApprovalFixture(
                    mode: mode
                )
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
            self.mode = mode
            _model = State(
                initialValue:
                    GitLabMergeRequestApprovalManagementModel(
                        route:
                            fixture
                            .mergeRequest
                            .route,
                        accountID:
                            accountID,
                        apiAccess:
                            mode.apiAccess,
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

                        Text(mode.title)
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
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

    private nonisolated enum
        GitLabMergeRequestApprovalFixtureMode:
        String,
        Sendable
    {
        case premium
        case basic
        case approved
        case readOnly
        case stale
        case permissionDenied
        case deliveryUnknown
        case detailsFailure

        static var current: Self {
            let arguments =
                ProcessInfo.processInfo
                    .arguments
            guard
                let keyIndex =
                    arguments.firstIndex(
                        of:
                            "-p3_08_approval_fixture_mode"
                    ),
                arguments.indices.contains(
                    keyIndex + 1
                ),
                let mode =
                    Self(
                        rawValue:
                            arguments[
                                keyIndex + 1
                            ]
                    )
            else {
                return .premium
            }
            return mode
        }

        var apiAccess:
            GitLabAPIAccess
        {
            self == .readOnly
                || self == .basic
                ? .readOnly
                : .readWrite
        }

        var title: String {
            switch self {
            case .premium:
                "Premium rules"
            case .basic:
                "Basic approvals"
            case .approved:
                "Current user approved"
            case .readOnly:
                "Read-only account"
            case .stale:
                "Stale revision"
            case .permissionDenied:
                "Permission denied"
            case .deliveryUnknown:
                "Unknown delivery"
            case .detailsFailure:
                "Rule refresh failure"
            }
        }
    }

    private nonisolated struct
        GitLabMergeRequestApprovalFixture:
        GitLabMergeRequestApprovalServing,
        Sendable
    {
        let mode:
            GitLabMergeRequestApprovalFixtureMode
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

        init(
            mode:
                GitLabMergeRequestApprovalFixtureMode
        ) {
            self.mode = mode
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
                    approved:
                        mode == .approved,
                    approvalsRequired: 2,
                    approvalsLeft:
                        mode == .approved
                        ? 0
                        : 1,
                    approvedBy:
                        (
                            mode == .approved
                            ? [
                                currentUser,
                                approver,
                            ]
                            : [approver]
                        )
                        .map {
                            GitLabMergeRequestApproval(
                                user: $0,
                                approvedAt:
                                    Date(
                                        timeIntervalSince1970:
                                            1_785_328_496
                                    )
                            )
                        }
                )
            mergeRequest =
                Self.mergeRequest(
                    author: currentUser,
                    headSHA: "fixture-head"
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
            if mode == .stale {
                return Self.mergeRequest(
                    author:
                        mergeRequest.author,
                    headSHA:
                        "new-fixture-head"
                )
            }
            return mergeRequest
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
            if mode == .detailsFailure {
                throw .api(
                    .server(
                        statusCode: 500
                    )
                )
            }
            if mode == .basic {
                return .unavailable
            }
            return .available(details)
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
            if mode == .detailsFailure {
                throw .api(
                    .server(
                        statusCode: 500
                    )
                )
            }
            await onResponse(
                GitLabAPIResponseEvent(
                    value:
                        mode == .basic
                        ? .unavailable
                        : .available(
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
            if mode == .permissionDenied {
                throw .api(.forbidden)
            }
            if mode == .deliveryUnknown {
                throw .api(
                    .connectivity(
                        .networkConnectionLost
                    )
                )
            }
            return summary
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

        private static func mergeRequest(
            author: GitLabAPIUser,
            headSHA: String
        ) -> GitLabMergeRequest {
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
                author: author,
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
                sha: headSHA,
                diffRefs: nil,
                changesCount: "3",
                detailedMergeStatus:
                    "mergeable",
                hasConflicts: false,
                blockingDiscussionsResolved:
                    true,
                headPipeline: nil
            )
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
