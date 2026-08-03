#if DEBUG
    import Observation
    import SwiftUI

    struct
        GitLabMergeRequestMergeFixtureView:
        View
    {
        private let summary:
            GitLabMergeRequestApprovalSummary
        private let mode:
            GitLabMergeRequestMergeFixtureMode
        @State private var state:
            GitLabMergeRequestMergeFixtureState
        @State private var model:
            GitLabMergeRequestMergeModel

        @MainActor
        init() {
            let mode =
                GitLabMergeRequestMergeFixtureMode
                .current
            let mergeRequest =
                mode.mergeRequest
            let summary =
                GitLabMergeRequestApprovalSummary(
                    approved: true,
                    approvalsRequired: 1,
                    approvalsLeft: 0,
                    approvedBy: []
                )
            let state =
                GitLabMergeRequestMergeFixtureState(
                    mergeRequest:
                        mergeRequest,
                    approvalSummary:
                        summary
                )
            self.mode = mode
            self.summary = summary
            _state = State(
                initialValue: state
            )
            _model = State(
                initialValue:
                    GitLabMergeRequestMergeModel(
                        accountID:
                            mode.accountID,
                        route:
                            mergeRequest.route,
                        apiAccess:
                            .readWrite,
                        service:
                            GitLabMergeRequestMergeFixtureService(
                                mergeRequest:
                                    mergeRequest,
                                approvalSummary:
                                    summary
                            ),
                        currentMergeRequest: {
                            state.mergeRequest
                        },
                        currentApprovalSummary: {
                            state.approvalSummary
                        },
                        isAccountCurrent: {
                            true
                        },
                        onMergeRequestReconciled: {
                            state.mergeRequest =
                                $0
                        },
                        onApprovalSummaryReconciled: {
                            state.approvalSummary =
                                $0
                        },
                        onResourceEdited: {
                            guard
                                case let .mergeRequest(
                                    mergeRequest
                                ) = $0
                            else {
                                return
                            }
                            state.mergeRequest =
                                mergeRequest
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
                            "Safe merge fixture"
                        )
                        .font(.glabTitle2.bold())
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                        Text(mode.title)
                            .font(.glabCaption)
                            .foregroundStyle(
                                .secondary
                            )

                        GitLabMergeRequestReadinessView(
                            readiness:
                                GitLabMergeRequestReadiness(
                                    mergeRequest:
                                        state
                                        .mergeRequest,
                                    approvalState:
                                        .loaded(
                                            .available(
                                                summary
                                            )
                                        )
                                ),
                            approvalError: nil,
                            mergeModel:
                                model,
                            retryApproval: {},
                            openPipelines: {}
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
                    Color.glabCanvas
                )
            }
            .gitLabMergeRequestMergeAlerts(
                model: model
            )
        }
    }

    @MainActor
    @Observable
    private final class
        GitLabMergeRequestMergeFixtureState
    {
        var mergeRequest:
            GitLabMergeRequest
        var approvalSummary:
            GitLabMergeRequestApprovalSummary

        init(
            mergeRequest:
                GitLabMergeRequest,
            approvalSummary:
                GitLabMergeRequestApprovalSummary
        ) {
            self.mergeRequest =
                mergeRequest
            self.approvalSummary =
                approvalSummary
        }
    }

    private nonisolated enum
        GitLabMergeRequestMergeFixtureMode:
        String,
        Sendable
    {
        case immediate
        case auto
        case blocked
        case checking
        case alreadyAutoMerging

        static var current: Self {
            let arguments =
                ProcessInfo.processInfo
                    .arguments
            guard
                let keyIndex =
                    arguments.firstIndex(
                        of:
                            "-p3_12_merge_fixture_mode"
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
                return .immediate
            }
            return mode
        }

        var title: String {
            switch self {
            case .immediate:
                "Ready to merge"
            case .auto:
                "Pipeline in progress"
            case .blocked:
                "Blocked by conflicts"
            case .checking:
                "GitLab is checking"
            case .alreadyAutoMerging:
                "Auto-merge enabled"
            }
        }

        var accountID:
            GitLabAccountID
        {
            GitLabAccountID(
                host:
                    try! GitLabHost(
                        "gitlab.example.com"
                    ),
                userID: 7
            )
        }

        var mergeRequest:
            GitLabMergeRequest
        {
            let detailedStatus:
                String
            let pipelineStatus:
                String
            let hasConflicts:
                Bool
            let autoMerge:
                Bool
            switch self {
            case .immediate:
                detailedStatus =
                    "mergeable"
                pipelineStatus = "success"
                hasConflicts = false
                autoMerge = false
            case .auto:
                detailedStatus =
                    "ci_still_running"
                pipelineStatus = "running"
                hasConflicts = false
                autoMerge = false
            case .blocked:
                detailedStatus =
                    "conflict"
                pipelineStatus = "success"
                hasConflicts = true
                autoMerge = false
            case .checking:
                detailedStatus =
                    "checking"
                pipelineStatus = "success"
                hasConflicts = false
                autoMerge = false
            case .alreadyAutoMerging:
                detailedStatus =
                    "ci_still_running"
                pipelineStatus = "running"
                hasConflicts = false
                autoMerge = true
            }
            return Self.makeMergeRequest(
                detailedStatus:
                    detailedStatus,
                pipelineStatus:
                    pipelineStatus,
                hasConflicts:
                    hasConflicts,
                autoMerge:
                    autoMerge
            )
        }

        private static func makeMergeRequest(
            detailedStatus: String,
            pipelineStatus: String,
            hasConflicts: Bool,
            autoMerge: Bool
        ) -> GitLabMergeRequest {
            GitLabMergeRequest(
                id: 101,
                iid: 7,
                projectID: 42,
                title:
                    "Ship safe merge actions",
                description: nil,
                state: "opened",
                draft: false,
                legacyWorkInProgress: nil,
                labels: [],
                author:
                    GitLabAPIUser(
                        id: 7,
                        username: "nitesh",
                        name: "Nitesh",
                        avatarURL: nil,
                        webURL: nil
                    ),
                assignees: [],
                reviewers: [],
                sourceBranch:
                    "feature/safe-merge",
                targetBranch: "main",
                userNotesCount: 0,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                closedAt: nil,
                mergedAt: nil,
                webURL: nil,
                references:
                    GitLabMergeRequestReferences(
                        short: "!7",
                        relative:
                            "project!7",
                        full:
                            "group/project!7"
                    ),
                sha: "fixture-head-sha",
                diffRefs: nil,
                changesCount: "2",
                detailedMergeStatus:
                    detailedStatus,
                hasConflicts:
                    hasConflicts,
                blockingDiscussionsResolved:
                    true,
                headPipeline:
                    GitLabMergeRequestHeadPipeline(
                        id: 501,
                        status:
                            pipelineStatus,
                        webURL: nil
                    ),
                mergeWhenPipelineSucceeds:
                    autoMerge,
                userPermissions:
                    GitLabMergeRequestUserPermissions(
                        canMerge: true
                    )
            )
        }
    }

    private actor
        GitLabMergeRequestMergeFixtureService:
        GitLabMergeRequestMergeServing
    {
        private var mergeRequest:
            GitLabMergeRequest
        private let approvalSummary:
            GitLabMergeRequestApprovalSummary

        init(
            mergeRequest:
                GitLabMergeRequest,
            approvalSummary:
                GitLabMergeRequestApprovalSummary
        ) {
            self.mergeRequest =
                mergeRequest
            self.approvalSummary =
                approvalSummary
        }

        func preflight(
            at route:
                GitLabMergeRequestRoute
        ) throws(GitLabSessionClientError)
            -> GitLabMergeRequestMergePreflight
        {
            guard
                mergeRequest.route
                    == route
            else {
                throw .api(.invalidResponse)
            }
            return GitLabMergeRequestMergePreflight(
                mergeRequest:
                    mergeRequest,
                approvalSummary:
                    approvalSummary
            )
        }

        func merge(
            at route:
                GitLabMergeRequestRoute,
            sha: String,
            action:
                GitLabMergeRequestMergeAction
        ) throws(GitLabSessionClientError)
            -> GitLabMergeRequest
        {
            guard
                mergeRequest.route
                    == route,
                mergeRequest.diffHeadSHA
                    == sha
            else {
                throw .api(
                    .validation(
                        statusCode: 409
                    )
                )
            }
            mergeRequest =
                GitLabMergeRequest(
                    id:
                        mergeRequest.id,
                    iid:
                        mergeRequest.iid,
                    projectID:
                        mergeRequest.projectID,
                    title:
                        mergeRequest.title,
                    description:
                        mergeRequest
                        .description,
                    state:
                        action == .mergeNow
                        ? "merged"
                        : "opened",
                    draft: false,
                    legacyWorkInProgress:
                        nil,
                    labels:
                        mergeRequest.labels,
                    author:
                        mergeRequest.author,
                    assignees:
                        mergeRequest.assignees,
                    reviewers:
                        mergeRequest.reviewers,
                    sourceBranch:
                        mergeRequest
                        .sourceBranch,
                    targetBranch:
                        mergeRequest
                        .targetBranch,
                    userNotesCount:
                        mergeRequest
                        .userNotesCount,
                    createdAt:
                        mergeRequest
                        .createdAt,
                    updatedAt: .now,
                    closedAt: nil,
                    mergedAt:
                        action == .mergeNow
                        ? .now
                        : nil,
                    webURL: nil,
                    references:
                        mergeRequest
                        .references,
                    sha:
                        mergeRequest.sha,
                    diffRefs: nil,
                    changesCount:
                        mergeRequest
                        .changesCount,
                    detailedMergeStatus:
                        action == .mergeNow
                        ? "not_open"
                        : "ci_still_running",
                    hasConflicts: false,
                    blockingDiscussionsResolved:
                        true,
                    headPipeline:
                        mergeRequest
                        .headPipeline,
                    mergeWhenPipelineSucceeds:
                        action
                            == .autoMerge,
                    userPermissions:
                        mergeRequest
                        .userPermissions
                )
            return mergeRequest
        }
    }
#endif
