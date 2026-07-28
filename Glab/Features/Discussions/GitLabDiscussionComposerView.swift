import SwiftUI

struct GitLabDiscussionComposerView: View {
    @State private var model:
        GitLabDiscussionComposerModel
    @State private var sendTask:
        Task<Void, Never>?
    @FocusState private var editorIsFocused:
        Bool

    private let accountID: GitLabAccountID
    private let appSession: AppSession

    @Environment(\.dismiss) private var dismiss

    init(
        accountID: GitLabAccountID,
        resource: GitLabDiscussionResource,
        target:
            GitLabDiscussionComposerTarget,
        apiAccess: GitLabAPIAccess,
        mutator: any GitLabDiscussionMutating,
        draftStore:
            any GitLabDiscussionDraftStoring,
        appSession: AppSession,
        onSuccess:
            @escaping @MainActor (
                GitLabDiscussionComposerResult
            ) -> Void
    ) {
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabDiscussionComposerModel(
                    accountID: accountID,
                    resource: resource,
                    target: target,
                    apiAccess: apiAccess,
                    mutator: mutator,
                    draftStore: draftStore,
                    onSuccess: onSuccess
                )
        )
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    editor(model: $model)

                    if model.isSending {
                        Label(
                            "Sending to GitLab…",
                            systemImage:
                                "arrow.up.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(
                            .secondary
                        )
                        .accessibilityIdentifier(
                            "discussion.composer.sending"
                        )
                    }

                    if let failure = model.failure {
                        GitLabDiscussionComposerFailureView(
                            failure: failure,
                            retry: startSending
                        )
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(
                .interactively
            )
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    cancellationButton
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(actionTitle) {
                        startSending()
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        !model
                            .canSubmitFromToolbar
                    )
                    .accessibilityIdentifier(
                        "discussion.composer.send"
                    )
                }
            }
            .task {
                await model.restoreDraft()
                if !model.isSending {
                    editorIsFocused = true
                }
            }
            .onChange(
                of: model.didSucceed
            ) { _, didSucceed in
                if didSucceed {
                    dismiss()
                }
            }
            .onChange(
                of:
                    model
                        .authenticationFailure
            ) { _, error in
                guard let error else {
                    return
                }
                Task {
                    await appSession
                        .handleAuthenticationFailure(
                            error,
                            for: accountID
                        )
                }
            }
        }
        .interactiveDismissDisabled(
            model.isSending
        )
        .onDisappear {
            sendTask?.cancel()
            guard !model.didSucceed else {
                return
            }
            Task {
                _ = await model
                    .persistForDismissal()
            }
        }
        .accessibilityIdentifier(
            "discussion.composer"
        )
    }

    private func editor(
        model:
            Bindable<
                GitLabDiscussionComposerModel
            >
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text("Comment")
                .font(
                    .headline
                )

            ZStack(alignment: .topLeading) {
                if model.body.wrappedValue
                    .isEmpty
                {
                    Text(
                        "Write a comment using Markdown…"
                    )
                    .foregroundStyle(
                        .tertiary
                    )
                    .padding(.horizontal, 13)
                    .padding(.vertical, 15)
                    .accessibilityHidden(true)
                }

                TextEditor(
                    text: model.body
                )
                .focused(
                    $editorIsFocused
                )
                .scrollContentBackground(
                    .hidden
                )
                .padding(8)
                .frame(minHeight: 220)
                .disabled(
                    self.model.isSending
                )
                .accessibilityLabel(
                    "Comment"
                )
                .accessibilityIdentifier(
                    "discussion.composer.editor"
                )
            }
            .background(
                Color(
                    uiColor:
                        .secondarySystemGroupedBackground
                ),
                in: .rect(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16
                )
                .stroke(
                    Color.primary
                        .opacity(0.08),
                    lineWidth: 1
                )
            }

            Text(
                "Markdown is supported. Your draft is saved on this device."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cancellationButton: some View {
        if model.isSending {
            Button(
                "Cancel Sending",
                role: .destructive
            ) {
                sendTask?.cancel()
            }
            .accessibilityIdentifier(
                "discussion.composer.cancelSending"
            )
        } else {
            Button("Cancel") {
                Task {
                    guard
                        await model
                            .persistForDismissal()
                    else {
                        return
                    }
                    dismiss()
                }
            }
            .accessibilityIdentifier(
                "discussion.composer.cancel"
            )
        }
    }

    private var title: String {
        switch model.target {
        case .newDiscussion:
            "New comment"
        case .newDiffDiscussion:
            "New line comment"
        case .reply:
            "Reply"
        }
    }

    private var actionTitle: String {
        switch model.target {
        case .newDiscussion,
             .newDiffDiscussion:
            "Post"
        case .reply:
            "Reply"
        }
    }

    private func startSending() {
        guard
            sendTask == nil,
            !model.isSending
        else {
            return
        }

        editorIsFocused = false
        sendTask = Task {
            await model.send()
            sendTask = nil
        }
    }
}

private struct GitLabDiscussionComposerFailureView:
    View
{
    let failure:
        GitLabDiscussionComposerFailure
    let retry: () -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(title)
                        .font(
                            .callout
                                .weight(
                                    .semibold
                                )
                        )
                    Text(message)
                        .font(.caption)
                }
            } icon: {
                Image(systemName: systemImage)
            }

            if canRetry {
                Button("Try Again") {
                    retry()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier(
                    "discussion.composer.retry"
                )
            }
        }
        .foregroundStyle(color)
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            color.opacity(0.1),
            in: .rect(cornerRadius: 14)
        )
        .accessibilityElement(
            children: .contain
        )
        .accessibilityIdentifier(
            "discussion.composer.failure"
        )
    }

    private var title: String {
        switch failure {
        case .emptyBody:
            "Write a comment"
        case .readOnly:
            "Read-only access"
        case .draftStorage:
            "Draft not saved"
        case let .mutation(
            _,
            certainty
        ):
            certainty
                == .deliveryUnknown
                ? "Delivery may be unknown"
                : "Comment wasn’t posted"
        }
    }

    private var message: String {
        switch failure {
        case .emptyBody:
            "Enter some text before posting."
        case .readOnly:
            "The GitLab api scope is required to post comments."
        case .draftStorage:
            "Glab couldn’t protect this draft locally, so it did not post it. Try again to save and post."
        case let .mutation(
            error,
            certainty
        ):
            if
                certainty
                    == .deliveryUnknown
            {
                error.description
                    + " GitLab may have received the comment. "
                    + "Check the discussion before retrying to avoid a duplicate."
            } else {
                error.description
            }
        }
    }

    private var systemImage: String {
        failure.certainty
            == .deliveryUnknown
            ? "questionmark.circle"
            : "exclamationmark.triangle"
    }

    private var color: Color {
        failure.certainty
            == .deliveryUnknown
            ? .orange
            : .red
    }

    private var canRetry: Bool {
        guard
            case let .mutation(
                error,
                _
            ) = failure
        else {
            return false
        }

        if error.authenticationFailure?
            .requiresReauthentication
            == true
        {
            return false
        }
        return true
    }
}
