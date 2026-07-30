import SwiftUI

struct GitLabProjectMergeRequestsView: View {
    let project: GitLabProject
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

    @State private var model:
        ProjectMergeRequestsModel
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    init(
        project: GitLabProject,
        loader:
            any GitLabMergeRequestLoading
                & GitLabMergeRequestApprovalLoading
                & GitLabMergeRequestDiffLoading
                & GitLabMergeRequestDiffSummaryLoading,
        approvalService:
            any GitLabMergeRequestApprovalServing,
        mergeService:
            any GitLabMergeRequestMergeServing,
        pipelineLoader:
            any GitLabPipelineLoading,
        discussionLoader:
            any GitLabDiscussionLoading,
        discussionMutator:
            any GitLabDiscussionMutating,
        reactionService:
            any GitLabEmojiReactionLoading
                & GitLabEmojiReactionMutating,
        editService:
            any GitLabResourceEditing,
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.project = project
        self.loader = loader
        self.approvalService =
            approvalService
        self.mergeService =
            mergeService
        self.pipelineLoader =
            pipelineLoader
        self.discussionLoader =
            discussionLoader
        self.discussionMutator =
            discussionMutator
        self.reactionService =
            reactionService
        self.editService = editService
        self.accountID = accountID
        self.appSession = appSession
        self.onResourceEdited =
            onResourceEdited
        _model = State(
            initialValue:
                ProjectMergeRequestsModel(
                    projectID: project.id,
                    loader: loader
                )
        )
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            statePicker(model: $model)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Divider()

            mergeRequestList
        }
    }

    private var mergeRequestList: some View {
        GitLabMergeRequestListView(
            model: model.activeModel,
            configuration:
                GitLabMergeRequestListConfiguration(
                    title: "Merge Requests",
                    loadingMessage:
                        "Loading \(model.selectedState.title.lowercased()) merge requests",
                    emptyTitle:
                        "No \(model.selectedState.title.lowercased()) merge requests",
                    emptyMessage:
                        emptyMessage,
                    emptySystemImage:
                        model.selectedState
                            .systemImage,
                    accessibilityIdentifier:
                        "projectMergeRequests.list"
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
            editService: editService,
            accountID: accountID,
            appSession: appSession,
            onResourceEdited:
                reconcileEditedResource
        )
    }

    private func statePicker(
        model:
            Bindable<ProjectMergeRequestsModel>
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                statePickerContent(model: model)
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(
                        "projectMergeRequests.statePicker"
                    )
            } else {
                HStack(spacing: 4) {
                    ForEach(
                        GitLabProjectMergeRequestState
                            .allCases,
                        id: \.self
                    ) { state in
                        stateButton(
                            state,
                            model: model
                        )
                    }
                }
                .padding(3)
                .background(
                    Color(
                        uiColor:
                            .tertiarySystemFill
                    ),
                    in: .capsule
                )
            }
        }
    }

    private func stateButton(
        _ state:
            GitLabProjectMergeRequestState,
        model:
            Bindable<ProjectMergeRequestsModel>
    ) -> some View {
        let isSelected =
            model.wrappedValue
                .selectedState == state

        return Button {
            model.wrappedValue
                .selectedState = state
        } label: {
            Label(
                state.title,
                systemImage:
                    state.systemImage
            )
            .font(
                .subheadline.weight(
                    .semibold
                )
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 30
            )
            .foregroundStyle(
                isSelected
                    ? Color.black
                        .opacity(0.78)
                    : .secondary
            )
            .background(
                isSelected
                    ? state.tintColor
                    : .clear,
                in: .capsule
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            isSelected
                ? .isSelected
                : []
        )
        .accessibilityIdentifier(
            "projectMergeRequests.state.\(state.rawValue)"
        )
    }

    private func statePickerContent(
        model:
            Bindable<ProjectMergeRequestsModel>
    ) -> some View {
        Picker(
            "State",
            selection: model.selectedState
        ) {
            ForEach(
                GitLabProjectMergeRequestState
                    .allCases,
                id: \.self
            ) { state in
                Label(
                    state.title,
                    systemImage:
                        state.systemImage
                )
                .labelStyle(
                    .titleAndIcon
                )
                .tag(state)
            }
        }
    }

    private var emptyMessage: String {
        switch model.selectedState {
        case .opened:
            "Open merge requests in \(project.name) will appear here."
        case .merged:
            "Merged merge requests in \(project.name) will appear here."
        }
    }

    private func reconcileEditedResource(
        _ result: GitLabResourceEditResult
    ) {
        if
            case let .mergeRequest(
                mergeRequest
            ) = result,
            mergeRequest.projectID
                == project.id
        {
            model.reconcileEditedMergeRequest(
                mergeRequest
            )
        }
        onResourceEdited(result)
    }
}

private extension
    GitLabProjectMergeRequestState
{
    var tintColor: Color {
        switch self {
        case .opened:
            .green
        case .merged:
            .blue
        }
    }
}
