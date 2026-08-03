import SwiftUI

struct YourIssuesView: View {
    let assignedModel: IssuesModel
    let createdModel: IssuesModel
    let loader: any GitLabIssueLoading
    let discussionLoader:
        any GitLabDiscussionLoading
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let editService:
        any GitLabResourceEditing
    let issueStatusService:
        any GitLabIssueStatusServing
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    @State private var selectedMode:
        GitLabIssueListMode = .assigned

    var body: some View {
        selectedList
            .navigationTitle(
                "Your Issues"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                Picker(
                    "Issue list",
                    selection: $selectedMode
                ) {
                    ForEach(
                        GitLabIssueListMode.allCases,
                        id: \.self
                    ) {
                        Text($0.title)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityIdentifier(
                    "issues.scopePicker"
                )
            }
    }

    private var selectedModel:
        IssuesModel
    {
        switch selectedMode {
        case .assigned:
            assignedModel
        case .created:
            createdModel
        }
    }

    private var selectedList: some View {
        GitLabIssueListView(
            model: selectedModel,
            configuration:
                GitLabIssueListConfiguration(
                    title: "Your Issues",
                    loadingMessage:
                        "Loading \(selectedMode.title.lowercased()) issues",
                    emptyTitle:
                        selectedMode.emptyTitle,
                    emptyMessage:
                        selectedMode.emptyMessage,
                    accessibilityIdentifier:
                        "issues.\(selectedMode.rawValue).list",
                    referenceStyle: .full,
                    prefersInlineTitle: true
                ),
            loader: loader,
            discussionLoader:
                discussionLoader,
            discussionMutator:
                discussionMutator,
            reactionService:
                reactionService,
            editService:
                editService,
            issueStatusService:
                issueStatusService,
            accountID: accountID,
            appSession: appSession,
            onResourceEdited:
                onResourceEdited
        )
    }
}

struct YourMergeRequestsView: View {
    let assignedModel: MergeRequestsModel
    let createdModel: MergeRequestsModel
    let reviewsModel: MergeRequestsModel
    let loader:
        any GitLabMergeRequestLoading
            & GitLabMergeRequestApprovalLoading
            & GitLabMergeRequestDiffLoading
            & GitLabMergeRequestDiffSummaryLoading
    let approvalService:
        any GitLabMergeRequestApprovalServing
    let mergeService:
        any GitLabMergeRequestMergeServing
    let pipelineLoader:
        any GitLabPipelineLoading
    let discussionLoader:
        any GitLabDiscussionLoading
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let editService:
        any GitLabResourceEditing
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    @State private var selectedMode:
        GitLabMergeRequestListMode =
        .assigned

    var body: some View {
        selectedList
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                Picker(
                    "Merge request list",
                    selection: $selectedMode
                ) {
                    ForEach(
                        GitLabMergeRequestListMode
                            .allCases,
                        id: \.self
                    ) {
                        Text($0.title)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityIdentifier(
                    "mergeRequests.scopePicker"
                )
            }
    }

    private var selectedModel:
        MergeRequestsModel
    {
        switch selectedMode {
        case .assigned:
            assignedModel
        case .created:
            createdModel
        case .reviewRequested:
            reviewsModel
        }
    }

    private var selectedList: some View {
        GitLabMergeRequestListView(
            model: selectedModel,
            configuration:
                GitLabMergeRequestListConfiguration(
                    title: "Your Merge Requests",
                    loadingMessage:
                        "Loading \(selectedMode.title.lowercased()) merge requests",
                    emptyTitle:
                        selectedMode.emptyTitle,
                    emptyMessage:
                        selectedMode.emptyMessage,
                    emptyGitLabIcon:
                        selectedMode.emptyGitLabIcon,
                    accessibilityIdentifier:
                        "mergeRequests.\(selectedMode.rawValue).list"
                ),
            loader: loader,
            approvalService:
                approvalService,
            mergeService:
                mergeService,
            pipelineLoader:
                pipelineLoader,
            discussionLoader:
                discussionLoader,
            discussionMutator:
                discussionMutator,
            reactionService:
                reactionService,
            editService:
                editService,
            accountID: accountID,
            appSession: appSession,
            onResourceEdited:
                onResourceEdited
        )
    }
}
