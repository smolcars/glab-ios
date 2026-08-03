import SwiftUI

private enum GitLabResourceEditorMode:
    String,
    CaseIterable,
    Hashable
{
    case edit = "Edit"
    case preview = "Preview"
}

struct GitLabResourceEditorView: View {
    private enum Field: Hashable {
        case title
        case description
    }

    let model: GitLabResourceEditorModel
    let accountID: GitLabAccountID
    let appSession: AppSession
    let webURL: URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer
    @FocusState private var focusedField: Field?
    @State private var mode =
        GitLabResourceEditorMode.edit
    @State private var
        showsDismissalConfirmation = false
    @State private var isClosing = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            VStack(spacing: 0) {
                editorHeader(model: $model)

                Divider()

                editorContent(model: $model)
            }
            .background(
                Color.glabCanvas
            )
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        model.operation == nil
                            ? "Cancel"
                            : "Stop"
                    ) {
                        cancelOrClose()
                    }
                    .disabled(isClosing)
                    .accessibilityIdentifier(
                        "resourceEditor.cancel"
                    )
                    .accessibilityHint(
                        cancelAccessibilityHint
                    )
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Save") {
                        focusedField = nil
                        Task {
                            await model.save()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        !model.canSave
                            || isClosing
                    )
                    .accessibilityIdentifier(
                        "resourceEditor.save"
                    )
                    .accessibilityHint(
                        saveAccessibilityHint
                    )
                }

                ToolbarItemGroup(
                    placement: .keyboard
                ) {
                    if focusedField == .description {
                        Spacer()
                        GitLabKeyboardDismissButton {
                            focusedField = nil
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                statusArea
            }
            .interactiveDismissDisabled(
                model.isDirty
                    || model.operation != nil
            )
            .confirmationDialog(
                "Close editor?",
                isPresented:
                    $showsDismissalConfirmation,
                titleVisibility: .visible
            ) {
                Button("Keep Draft and Close") {
                    keepDraftAndClose()
                }

                if model.canDiscardDraft {
                    Button(
                        "Discard Changes",
                        role: .destructive
                    ) {
                        discardAndClose()
                    }
                }

                Button(
                    "Continue Editing",
                    role: .cancel
                ) {}
            } message: {
                Text(dismissalMessage)
            }
            .task {
                await model.restoreDraft()
                guard !Task.isCancelled else {
                    return
                }
                focusedField = .title
            }
            .onDisappear {
                Task {
                    _ = await model
                        .persistForDismissal()
                }
            }
            .onChange(of: model.didSucceed) {
                _, didSucceed in
                guard didSucceed else {
                    return
                }
                AccessibilityNotification
                    .Announcement(
                        "Changes saved to GitLab"
                    )
                    .post()
                dismiss()
            }
            .onChange(
                of: model.authenticationFailure
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
    }

    private func editorHeader(
        model: Bindable<GitLabResourceEditorModel>
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(
                "Title",
                text: model.title,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .font(.glabHeadline)
            .lineLimit(1...4)
            .focused(
                $focusedField,
                equals: .title
            )
            .submitLabel(.done)
            .onSubmit {
                focusedField = nil
            }
            .disabled(
                !model.wrappedValue.canEdit
            )
            .accessibilityLabel("Title")
            .accessibilityIdentifier(
                "resourceEditor.title"
            )

            modePicker
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(
                "Description mode",
                selection: $mode
            ) {
                modeOptions
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(
                "resourceEditor.mode"
            )
        } else {
            Picker(
                "Description mode",
                selection: $mode
            ) {
                modeOptions
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(
                "resourceEditor.mode"
            )
        }
    }

    @ViewBuilder
    private var modeOptions: some View {
        ForEach(
            GitLabResourceEditorMode.allCases,
            id: \.self
        ) { mode in
            Text(mode.rawValue)
                .tag(mode)
        }
    }

    @ViewBuilder
    private func editorContent(
        model: Bindable<GitLabResourceEditorModel>
    ) -> some View {
        if !model.wrappedValue.hasRestoredDraft {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Restoring draft…")
                    .font(.glabHeadline)
                Text(
                    "Your account-scoped draft is loading."
                )
                .font(.glabSubheadline)
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .accessibilityElement(children: .combine)
            .gitLabAccessibilityAnnouncement(
                "Restoring editor draft"
            )
            .accessibilityIdentifier(
                "resourceEditor.restoring"
            )
        } else {
            switch mode {
            case .edit:
                GitLabMentionTextEditor(
                    text: model.rawDescription,
                    projectID:
                        model.wrappedValue
                            .baseline.target
                            .projectID
                ) { text, selection in
                    TextEditor(
                        text: text,
                        selection: selection
                    )
                    .font(.glabBody)
                    .padding(12)
                    .scrollContentBackground(
                        .hidden
                    )
                    .focused(
                        $focusedField,
                        equals: .description
                    )
                    .background(
                        Color.glabRaisedSurface
                    )
                    .disabled(
                        !model.wrappedValue
                            .canEdit
                    )
                    .scrollDismissesKeyboard(
                        .interactively
                    )
                    .accessibilityLabel(
                        "Markdown description"
                    )
                    .accessibilityHint(
                        "Edits the raw GitLab Flavored Markdown description."
                    )
                    .accessibilityIdentifier(
                        "resourceEditor.description"
                    )
                }
            case .preview:
                preview
            }
        }
    }

    private var preview: some View {
        ScrollView {
            if model.rawDescription.isEmpty {
                GitLabEmptyStateView(
                    title: "Nothing to preview",
                    message:
                        "The description is empty.",
                    systemImage: "doc.text"
                )
                .frame(minHeight: 320)
            } else {
                GitLabMarkdownContentView(
                    request: GitLabMarkdownRequest(
                        accountID: accountID,
                        resource:
                            markdownResource,
                        source:
                            model.rawDescription,
                        webURL: webURL
                    ),
                    revision:
                        model.baseline.updatedAt,
                    kind: .description,
                    renderer: markdownRenderer
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
        }
        .padding(20)
        .accessibilityIdentifier(
            "resourceEditor.preview"
        )
    }

    @ViewBuilder
    private var statusArea: some View {
        if let status = editorStatus {
            GitLabResourceEditorStatusView(
                status: status,
                retryDraftStorage: {
                    Task {
                        _ = await model
                            .persistForDismissal()
                    }
                },
                checkGitLab: {
                    Task {
                        await model.checkGitLab()
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .gitLabAccessibilityAnnouncement(
                status.announcement
            )
        }
    }

    private var editorStatus:
        GitLabResourceEditorStatus?
    {
        if let operation = model.operation {
            return switch operation {
            case .saving:
                .progress(
                    title:
                        "Checking GitLab and saving…",
                    message:
                        "Glab checks for newer changes before it updates this \(resourceName)."
                )
            case .checkingGitLab:
                .progress(
                    title: "Checking GitLab…",
                    message:
                        "Glab is confirming whether the previous save reached GitLab."
                )
            }
        }

        if let failure = model.failure {
            return status(for: failure)
        }

        if model.requiresDeliveryCheck {
            return unknownDeliveryStatus
        }

        if model.apiAccess == .readOnly {
            return .notice(
                title:
                    dynamicTypeSize
                    .isAccessibilitySize
                    ? "Read-only"
                    : "Read-only account",
                message:
                    dynamicTypeSize
                    .isAccessibilitySize
                    ? "Save is unavailable. Preview and local drafts still work."
                    : "You can edit, preview, and keep a local draft. Sign in with OAuth or an API token with the api scope to save.",
                systemImage: "eye.fill",
                tint: .orange,
                action: nil
            )
        }

        return nil
    }

    private func status(
        for failure: GitLabResourceEditorFailure
    ) -> GitLabResourceEditorStatus {
        switch failure {
        case let .validation(error):
            .notice(
                title: "Check your changes",
                message: error.description,
                systemImage:
                    "exclamationmark.triangle.fill",
                tint: .orange,
                action: nil
            )
        case .readOnly:
            .notice(
                title: "Read-only account",
                message:
                    "This account cannot save changes. Your local draft is preserved.",
                systemImage: "eye.fill",
                tint: .orange,
                action: nil
            )
        case .draftStorage:
            .notice(
                title: "Draft not saved",
                message:
                    "Glab could not protect this draft on this device. Try again before closing or saving to GitLab.",
                systemImage:
                    "externaldrive.badge.exclamationmark",
                tint: .red,
                action: .retryDraftStorage
            )
        case let .freshness(error):
            .notice(
                title: "Couldn’t check for newer changes",
                message:
                    GitLabRecoveryPresentation(
                        error: error
                    ).message,
                systemImage:
                    "arrow.triangle.2.circlepath",
                tint: .red,
                action: nil
            )
        case let .conflict(conflict):
            .notice(
                title: "Changed on GitLab",
                message:
                    conflictMessage(conflict),
                systemImage:
                    "exclamationmark.arrow.triangle.2.circlepath",
                tint: .orange,
                action:
                    model.canCheckGitLab
                    ? .checkGitLab
                    : nil
            )
        case let .mutation(error, certainty):
            switch certainty {
            case .rejected:
                .notice(
                    title: "Changes not saved",
                    message:
                        GitLabRecoveryPresentation(
                            error: error
                        ).message,
                    systemImage:
                        "exclamationmark.triangle.fill",
                    tint: .red,
                    action: nil
                )
            case .deliveryUnknown:
                unknownDeliveryStatus
            }
        case let .reconciliation(error):
            .notice(
                title: "Couldn’t confirm the save",
                message:
                    GitLabRecoveryPresentation(
                        error: error
                    ).message,
                systemImage:
                    "questionmark.circle.fill",
                tint: .orange,
                action:
                    model.canCheckGitLab
                    ? .checkGitLab
                    : nil
            )
        }
    }

    private func conflictMessage(
        _ conflict: GitLabResourceEditConflict
    ) -> String {
        if model.requiresDeliveryCheck {
            if
                conflict.fields.contains(
                    .resourceIdentity
                )
            {
                return
                    "GitLab returned a different resource while checking the earlier save. Its delivery is still unresolved and your draft is preserved."
            }
            return
                "GitLab now has a different \(conflictFieldNames(conflict)). Glab cannot determine the earlier save’s result, so your draft is preserved."
        }

        if
            conflict.fields.contains(
                .resourceIdentity
            )
        {
            return
                "This resource no longer matches the version you began editing. Your draft was not sent."
        }

        return
            "The \(conflictFieldNames(conflict)) changed on GitLab after you began editing. Your draft was not sent."
    }

    private func conflictFieldNames(
        _ conflict: GitLabResourceEditConflict
    ) -> String {
        conflict.fields
            .compactMap {
                switch $0 {
                case .title:
                    "title"
                case .description:
                    "description"
                case .resourceIdentity:
                    nil
                }
            }
            .sorted()
            .joined(separator: " and ")
    }

    private var unknownDeliveryStatus:
        GitLabResourceEditorStatus
    {
        .notice(
            title: "Save status unknown",
            message:
                "GitLab may already have accepted these changes. Check GitLab before editing or trying to save again.",
            systemImage: "questionmark.circle.fill",
            tint: .orange,
            action:
                model.canCheckGitLab
                ? .checkGitLab
                : nil
        )
    }

    private var navigationTitle: String {
        switch model.baseline.target {
        case .issue:
            "Edit Issue"
        case .mergeRequest:
            "Edit Merge Request"
        }
    }

    private var resourceName: String {
        switch model.baseline.target {
        case .issue:
            "issue"
        case .mergeRequest:
            "merge request"
        }
    }

    private var markdownResource:
        GitLabMarkdownResourceID
    {
        switch model.baseline.target {
        case let .issue(route):
            .issue(
                projectID: route.projectID,
                issueIID: route.issueIID
            )
        case let .mergeRequest(route):
            .mergeRequest(
                projectID: route.projectID,
                mergeRequestIID:
                    route.mergeRequestIID
            )
        }
    }

    private var cancelAccessibilityHint: String {
        if model.operation != nil {
            return
                "Stops the current request and preserves the draft."
        }
        if model.isDirty {
            return
                "Offers to keep or discard this draft before closing."
        }
        return "Closes the editor."
    }

    private var saveAccessibilityHint: String {
        if model.apiAccess == .readOnly {
            return
                "Saving requires OAuth or an API token with the api scope. Local editing and preview remain available."
        }
        if model.requiresDeliveryCheck {
            return
                "Check GitLab before editing or saving again."
        }
        if !model.hasRestoredDraft {
            return
                "Waits until the local draft is restored."
        }
        if !model.isDirty {
            return
                "Make a change before saving."
        }
        return
            "Checks GitLab for newer changes, then saves."
    }

    private var dismissalMessage: String {
        if model.canDiscardDraft {
            return
                "Keep this account-scoped draft for later, or permanently discard your local changes."
        }
        return
            "The previous save may have reached GitLab. Keep the draft so its status can be checked later."
    }

    private func cancelOrClose() {
        focusedField = nil
        guard model.operation == nil else {
            model.cancelActiveOperation()
            return
        }
        guard model.isDirty else {
            keepDraftAndClose()
            return
        }
        showsDismissalConfirmation = true
    }

    private func keepDraftAndClose() {
        guard !isClosing else {
            return
        }
        isClosing = true
        Task {
            let didPersist =
                await model.persistForDismissal()
            isClosing = false
            if didPersist {
                dismiss()
            }
        }
    }

    private func discardAndClose() {
        guard !isClosing else {
            return
        }
        isClosing = true
        Task {
            let didDiscard =
                await model.discardDraft()
            isClosing = false
            if didDiscard {
                dismiss()
            }
        }
    }
}

private enum GitLabResourceEditorStatusAction {
    case retryDraftStorage
    case checkGitLab
}

private struct GitLabResourceEditorStatus {
    let title: String
    let message: String
    let systemImage: String?
    let tint: Color
    let showsProgress: Bool
    let action:
        GitLabResourceEditorStatusAction?

    static func progress(
        title: String,
        message: String
    ) -> Self {
        Self(
            title: title,
            message: message,
            systemImage: nil,
            tint: .orange,
            showsProgress: true,
            action: nil
        )
    }

    static func notice(
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        action:
            GitLabResourceEditorStatusAction?
    ) -> Self {
        Self(
            title: title,
            message: message,
            systemImage: systemImage,
            tint: tint,
            showsProgress: false,
            action: action
        )
    }

    var announcement: String {
        "\(title). \(message)"
    }
}

private struct GitLabResourceEditorStatusView: View {
    let status: GitLabResourceEditorStatus
    let retryDraftStorage: () -> Void
    let checkGitLab: () -> Void

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if status.showsProgress {
                ProgressView()
                    .tint(status.tint)
            } else if let systemImage =
                status.systemImage,
                !dynamicTypeSize
                    .isAccessibilitySize
            {
                Image(systemName: systemImage)
                    .foregroundStyle(status.tint)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.glabCallout.weight(.semibold))

                Text(status.message)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)

                switch status.action {
                case .retryDraftStorage:
                    Button(
                        "Try Saving Draft Again",
                        action: retryDraftStorage
                    )
                    .font(.glabCallout.weight(.semibold))
                    .accessibilityIdentifier(
                        "resourceEditor.retryDraft"
                    )
                case .checkGitLab:
                    Button(
                        "Check GitLab",
                        action: checkGitLab
                    )
                    .font(.glabCallout.weight(.semibold))
                    .accessibilityIdentifier(
                        "resourceEditor.checkGitLab"
                    )
                case nil:
                    EmptyView()
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(12)
        .background(
            status.tint.opacity(0.1),
            in: .rect(cornerRadius: 14)
        )
        .accessibilityElement(
            children: .contain
        )
        .accessibilityIdentifier(
            "resourceEditor.status"
        )
    }
}
