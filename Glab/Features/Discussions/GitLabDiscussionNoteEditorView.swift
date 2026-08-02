import SwiftUI

struct GitLabDiscussionNoteEditorView: View {
    let note: GitLabDiscussionNote
    let discussionID: String
    let resource: GitLabDiscussionResource
    let accountID: GitLabAccountID
    let mutator: any GitLabDiscussionMutating
    let appSession: AppSession
    let onSuccess:
        @MainActor (GitLabDiscussionNote) -> Void

    @State private var bodyText: String
    @State private var isSaving = false
    @State private var failure:
        GitLabDiscussionMutationError?
    @FocusState private var editorIsFocused:
        Bool

    @Environment(\.dismiss) private var dismiss

    init(
        note: GitLabDiscussionNote,
        discussionID: String,
        resource: GitLabDiscussionResource,
        accountID: GitLabAccountID,
        mutator: any GitLabDiscussionMutating,
        appSession: AppSession,
        onSuccess:
            @escaping @MainActor (
                GitLabDiscussionNote
            ) -> Void
    ) {
        self.note = note
        self.discussionID = discussionID
        self.resource = resource
        self.accountID = accountID
        self.mutator = mutator
        self.appSession = appSession
        self.onSuccess = onSuccess
        _bodyText = State(
            initialValue: note.body
        )
    }

    var body: some View {
        NavigationStack {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                editor

                if let failure {
                    Label(
                        failure.description,
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(
                        "discussion.noteEditor.failure"
                    )
                }

                Text(
                    "Markdown, mentions, quick actions, and other GitLab formatting are preserved."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
            )
            .navigationTitle("Edit comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier(
                        "discussion.noteEditor.cancel"
                    )
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Save") {
                        editorIsFocused = false
                        Task {
                            await save()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .accessibilityIdentifier(
                        "discussion.noteEditor.save"
                    )
                }

                ToolbarItemGroup(
                    placement: .keyboard
                ) {
                    if editorIsFocused {
                        Spacer()
                        GitLabKeyboardDismissButton {
                            editorIsFocused = false
                        }
                    }
                }
            }
            .task {
                editorIsFocused = true
            }
        }
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier(
            "discussion.noteEditor"
        )
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if bodyText.isEmpty {
                Text(
                    "Write a comment using Markdown…"
                )
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 13)
                .padding(.vertical, 15)
                .accessibilityHidden(true)
            }

            TextEditor(text: $bodyText)
                .focused($editorIsFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 240,
                    maxHeight: .infinity
                )
                .disabled(isSaving)
                .scrollDismissesKeyboard(
                    .interactively
                )
                .accessibilityLabel(
                    "Comment"
                )
                .accessibilityHint(
                    "Edits the original GitLab Flavored Markdown comment."
                )
                .accessibilityIdentifier(
                    "discussion.noteEditor.editor"
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
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    private var canSave: Bool {
        !isSaving
            && bodyText != note.body
            && !bodyText
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
    }

    private func save() async {
        guard
            canSave,
            let body = try? GitLabDiscussionCommentBody(
                bodyText
            )
        else {
            return
        }

        isSaving = true
        failure = nil
        defer {
            isSaving = false
        }

        do {
            let updatedNote =
                try await mutator.updateNote(
                    note.id,
                    in: discussionID,
                    for: resource,
                    body: body
                )
            onSuccess(updatedNote)
            dismiss()
        } catch {
            failure = error
            if
                let authenticationFailure =
                    error.authenticationFailure,
                authenticationFailure
                    .requiresReauthentication
            {
                await appSession
                    .handleAuthenticationFailure(
                        authenticationFailure,
                        for: accountID
                    )
            }
        }
    }
}
