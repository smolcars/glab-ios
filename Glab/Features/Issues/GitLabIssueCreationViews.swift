import SwiftUI

private enum GitLabIssueCreationEditorMode:
    String,
    CaseIterable,
    Hashable
{
    case edit = "Edit"
    case preview = "Preview"
}

struct GitLabIssueCreationView: View {
    private enum Field: Hashable {
        case title
        case description
    }

    let model: GitLabIssueCreationModel
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer
    @FocusState private var focusedField: Field?
    @State private var editorMode =
        GitLabIssueCreationEditorMode.edit
    @State private var isClosing = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                if model.apiAccess == .readOnly {
                    readOnlyCallout
                }

                projectSection
                issueSection(model: $model)
                descriptionSection(model: $model)
                metadataSection(model: $model)
            }
            .navigationTitle("New Issue")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        close()
                    }
                    .disabled(
                        model.isSubmitting
                            || isClosing
                    )
                    .accessibilityIdentifier(
                        "issueCreation.cancel"
                    )
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Create") {
                        focusedField = nil
                        Task {
                            await model.submit()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!model.canCreate)
                    .accessibilityHint(
                        createAccessibilityHint
                    )
                    .accessibilityIdentifier(
                        "issueCreation.create"
                    )
                }

                ToolbarItemGroup(
                    placement: .keyboard
                ) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                statusArea
            }
            .interactiveDismissDisabled(true)
            .task {
                await model.restoreDraft()
                guard !Task.isCancelled else {
                    return
                }
                await model.loadProjectsIfNeeded()
            }
            .task(
                id: model.selectedProject?.id
            ) {
                await model
                    .loadSelectedProjectMetadata()
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
                        "Issue created"
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

    private var projectSection: some View {
        Section("Project") {
            NavigationLink {
                GitLabIssueCreationProjectPicker(
                    model: model,
                    accountID: accountID,
                    appSession: appSession
                )
            } label: {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            model.selectedProject
                                == nil
                            ? "square.stack"
                            : "square.stack.fill"
                    )
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            model.selectedProject?
                                .name
                                ?? "Choose a project"
                        )
                        .foregroundStyle(.primary)

                        if
                            let path =
                                model.selectedProject?
                                .pathWithNamespace
                        {
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(1)
                        }
                    }
                }
            }
            .accessibilityLabel(
                model.selectedProject.map {
                    "Project, \($0.nameWithNamespace)"
                }
                    ?? "Choose a project"
            )
            .accessibilityHint(
                "Opens project search."
            )
            .accessibilityIdentifier(
                "issueCreation.project"
            )
        }
    }

    private func issueSection(
        model: Bindable<GitLabIssueCreationModel>
    ) -> some View {
        Section("Issue") {
            TextField(
                "Title",
                text: model.title,
                axis: .vertical
            )
            .lineLimit(1...4)
            .focused(
                $focusedField,
                equals: .title
            )
            .submitLabel(.done)
            .onSubmit {
                focusedField = nil
            }
            .accessibilityLabel("Issue title")
            .accessibilityIdentifier(
                "issueCreation.title"
            )
        }
    }

    private func descriptionSection(
        model: Bindable<GitLabIssueCreationModel>
    ) -> some View {
        Section {
            modePicker

            if !model.wrappedValue.hasRestoredDraft {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Restoring draft…")
                        .foregroundStyle(.secondary)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 180
                )
                .accessibilityElement(
                    children: .combine
                )
            } else {
                switch editorMode {
                case .edit:
                    TextEditor(
                        text:
                            model.rawDescription
                    )
                    .frame(minHeight: 180)
                    .scrollContentBackground(
                        .hidden
                    )
                    .focused(
                        $focusedField,
                        equals: .description
                    )
                    .accessibilityLabel(
                        "Markdown description"
                    )
                    .accessibilityHint(
                        "Edits raw GitLab Flavored Markdown."
                    )
                    .accessibilityIdentifier(
                        "issueCreation.description"
                    )
                case .preview:
                    markdownPreview
                }
            }
        } header: {
            Text("Description")
        } footer: {
            Text(
                "\(model.wrappedValue.rawDescription.count.formatted()) of \(GitLabIssueCreationInput.maximumDescriptionLength.formatted()) characters"
            )
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(
                "Description mode",
                selection: $editorMode
            ) {
                editorModeOptions
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(
                "issueCreation.descriptionMode"
            )
        } else {
            Picker(
                "Description mode",
                selection: $editorMode
            ) {
                editorModeOptions
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(
                "issueCreation.descriptionMode"
            )
        }
    }

    private var editorModeOptions: some View {
        ForEach(
            GitLabIssueCreationEditorMode
                .allCases,
            id: \.self
        ) { mode in
            Text(mode.rawValue)
                .tag(mode)
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        if model.rawDescription.isEmpty {
            ContentUnavailableView(
                "Nothing to preview",
                systemImage: "doc.text"
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 180
            )
        } else {
            GitLabMarkdownContentView(
                request: GitLabMarkdownRequest(
                    accountID: accountID,
                    resource:
                        .issue(
                            projectID:
                                model
                                .selectedProject?
                                .id
                                ?? 0,
                            issueIID: 0
                        ),
                    source:
                        model.rawDescription,
                    webURL: nil
                ),
                revision: Date(
                    timeIntervalSinceReferenceDate:
                        TimeInterval(
                            model.draftRevision
                        )
                ),
                kind: .description,
                renderer: markdownRenderer
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 180,
                alignment: .topLeading
            )
            .accessibilityIdentifier(
                "issueCreation.preview"
            )
        }
    }

    private func metadataSection(
        model: Bindable<GitLabIssueCreationModel>
    ) -> some View {
        Section("Details") {
            NavigationLink {
                GitLabIssueCreationLabelPicker(
                    model: model.wrappedValue,
                    accountID: accountID,
                    appSession: appSession
                )
            } label: {
                metadataRow(
                    title: "Labels",
                    systemImage: "tag",
                    value:
                        countValue(
                            model.wrappedValue
                                .selectedLabelNames
                                .count
                        )
                )
            }
            .disabled(
                model.wrappedValue
                    .selectedProject == nil
            )
            .accessibilityIdentifier(
                "issueCreation.labels"
            )

            NavigationLink {
                GitLabIssueCreationAssigneePicker(
                    model: model.wrappedValue,
                    accountID: accountID,
                    appSession: appSession
                )
            } label: {
                metadataRow(
                    title: "Assignees",
                    systemImage:
                        "person.2",
                    value:
                        countValue(
                            model.wrappedValue
                                .selectedAssigneeIDs
                                .count
                        )
                )
            }
            .disabled(
                model.wrappedValue
                    .selectedProject == nil
            )
            .accessibilityIdentifier(
                "issueCreation.assignees"
            )

            Toggle(
                isOn: model.confidential
            ) {
                Label(
                    "Confidential",
                    systemImage: "lock"
                )
            }
            .tint(.orange)
            .accessibilityHint(
                "Limits visibility according to GitLab project permissions."
            )
            .accessibilityIdentifier(
                "issueCreation.confidential"
            )

            Toggle(
                isOn: dueDateEnabled
            ) {
                Label(
                    "Due date",
                    systemImage: "calendar"
                )
            }
            .tint(.orange)
            .accessibilityIdentifier(
                "issueCreation.dueDateToggle"
            )

            if model.wrappedValue.dueDate != nil {
                DatePicker(
                    "Date",
                    selection: dueDateSelection,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .accessibilityIdentifier(
                    "issueCreation.dueDate"
                )
            }
        }
    }

    private func metadataRow(
        title: String,
        systemImage: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var dueDateEnabled:
        Binding<Bool>
    {
        Binding {
            model.dueDate != nil
        } set: { isEnabled in
            model.dueDate =
                isEnabled
                ? GitLabIssueCreationDateBridge
                    .dueDate(from: Date())
                : nil
        }
    }

    private var dueDateSelection:
        Binding<Date>
    {
        Binding {
            guard
                let dueDate = model.dueDate,
                let date =
                    GitLabIssueCreationDateBridge
                    .date(from: dueDate)
            else {
                return Date()
            }
            return date
        } set: { date in
            model.dueDate =
                GitLabIssueCreationDateBridge
                .dueDate(from: date)
        }
    }

    private var readOnlyCallout: some View {
        Section {
            Label(
                "Read-only — Create disabled",
                systemImage: "eye.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .accessibilityLabel(
                "Read-only account. You can compose and keep a local draft, but Create is disabled."
            )
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if model.isSubmitting {
            issueStatus(
                title: "Creating issue…",
                message:
                    "Waiting for GitLab. This request will not retry automatically.",
                systemImage:
                    "arrow.triangle.2.circlepath",
                showsProgress: true,
                action: nil
            )
        } else if
            model.isVerifyingRestoredProject,
            !model.isSelectedProjectVerified
        {
            issueStatus(
                title: "Checking project…",
                message:
                    "Confirming this account can still access the saved project.",
                systemImage: "folder",
                showsProgress: true,
                action: nil
            )
        } else if let failure = model.failure {
            let presentation =
                GitLabIssueCreationFailurePresentation(
                    failure: failure
                )
            issueStatus(
                title: presentation.title,
                message: presentation.message,
                systemImage:
                    presentation.systemImage,
                showsProgress: false,
                action: presentation.action
            )
        }
    }

    private func issueStatus(
        title: String,
        message: String,
        systemImage: String,
        showsProgress: Bool,
        action: GitLabIssueCreationRecoveryAction?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
            }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let action {
                    Button(
                        actionTitle(action)
                    ) {
                        perform(action)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.top, 3)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(
            children: .contain
        )
        .accessibilityIdentifier(
            "issueCreation.status"
        )
    }

    private func actionTitle(
        _ action:
            GitLabIssueCreationRecoveryAction
    ) -> String {
        switch action {
        case .retryDraftStorage:
            "Try Saving Draft"
        case .retryProjectVerification:
            "Try Again"
        case .confirmCheckedGitLab:
            "I Checked GitLab"
        }
    }

    private func perform(
        _ action:
            GitLabIssueCreationRecoveryAction
    ) {
        Task {
            switch action {
            case .retryDraftStorage:
                _ = await model
                    .persistForDismissal()
            case .retryProjectVerification:
                await model
                    .verifyRestoredProject()
            case .confirmCheckedGitLab:
                _ = await model
                    .acknowledgeDeliveryCheck()
            }
        }
    }

    private func close() {
        guard !isClosing else {
            return
        }
        isClosing = true
        focusedField = nil
        Task {
            let didPersist =
                await model.persistForDismissal()
            isClosing = false
            if didPersist {
                dismiss()
            }
        }
    }

    private func countValue(
        _ count: Int
    ) -> String {
        count == 0
            ? "None"
            : count.formatted()
    }

    private var createAccessibilityHint:
        String
    {
        if model.apiAccess == .readOnly {
            return
                "Creating requires OAuth or an API token with write access."
        }
        if model.requiresDeliveryCheck {
            return
                "Check GitLab before allowing another creation attempt."
        }
        if !model.hasRestoredDraft {
            return
                "Wait for the local draft to finish restoring."
        }
        if model.selectedProject == nil {
            return "Choose a project first."
        }
        if !model.isSelectedProjectVerified {
            return
                "Wait for the saved project to be verified."
        }
        if
            model.title
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        {
            return "Enter an issue title first."
        }
        return "Creates one issue in the selected project."
    }
}

private struct GitLabIssueCreationProjectPicker:
    View
{
    let model: GitLabIssueCreationModel
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.dismiss) private var dismiss
    @State private var pendingProject:
        GitLabProject?
    @State private var
        showsProjectChangeAlert = false

    var body: some View {
        @Bindable var model = model

        content
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.projectSearchText,
                prompt: "Search projects"
            )
            .task {
                await model.loadProjectsIfNeeded()
                await handleAuthenticationFailure()
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
            .alert(
                "Change project?",
                isPresented:
                    $showsProjectChangeAlert,
                presenting: pendingProject
            ) { project in
                Button("Change Project") {
                    choose(project)
                }
                Button(
                    "Cancel",
                    role: .cancel
                ) {
                    pendingProject = nil
                }
            } message: { _ in
                Text(
                    "Selected labels and assignees will be cleared. Your title and description will stay."
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        let projectsModel =
            model.projectsModel

        if
            projectsModel.isLoadingInitial,
            projectsModel.items.isEmpty
        {
            GitLabLoadingStateView(
                message: "Loading projects"
            )
        } else if
            projectsModel.items.isEmpty,
            let error =
                projectsModel.loadError
        {
            GitLabRetryStateView(
                error: error
            ) {
                Task {
                    await projectsModel
                        .refresh()
                }
            }
        } else if
            projectsModel.items.isEmpty,
            projectsModel.hasLoaded
        {
            ContentUnavailableView.search(
                text:
                    model.projectSearchText
            )
        } else {
            List {
                ForEach(
                    projectsModel.items
                ) { project in
                    Button {
                        select(project)
                    } label: {
                        projectRow(project)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        model.selectedProject?
                            .id == project.id
                        ? "Selected"
                        : "Not selected"
                    )
                    .accessibilityIdentifier(
                        "issueCreation.project.\(project.id)"
                    )
                    .task {
                        await projectsModel
                            .loadNextPageIfNeeded(
                                after: project
                            )
                        await handleAuthenticationFailure()
                    }
                }

                if projectsModel.isLoadingNextPage {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if
                    projectsModel
                        .didFailNextPage,
                    let error =
                        projectsModel
                        .loadError
                {
                    GitLabInlineRetryRow(
                        title:
                            "Couldn’t load more projects",
                        error: error,
                        accessibilityIdentifier:
                            "issueCreation.projects.nextPageError"
                    ) {
                        Task {
                            await projectsModel
                                .retryNextPage()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func projectRow(
        _ project: GitLabProject
    ) -> some View {
        HStack(spacing: 12) {
            Text(project.avatarMark)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(
                    Color.orange.opacity(0.12),
                    in: .rect(
                        cornerRadius: 9
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(project.name)
                    .foregroundStyle(.primary)
                Text(
                    project.pathWithNamespace
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if
                model.selectedProject?.id
                    == project.id
            {
                Image(
                    systemName: "checkmark"
                )
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(
            children: .combine
        )
    }

    private func select(
        _ project: GitLabProject
    ) {
        let changesProject =
            model.selectedProject?.id
                != project.id
        let clearsMetadata =
            !model.selectedLabelNames.isEmpty
                || !model
                    .selectedAssigneeIDs
                    .isEmpty
        if changesProject && clearsMetadata {
            pendingProject = project
            showsProjectChangeAlert = true
        } else {
            choose(project)
        }
    }

    private func choose(
        _ project: GitLabProject
    ) {
        model.selectProject(project)
        pendingProject = nil
        dismiss()
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                model.authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}

private struct GitLabIssueCreationLabelPicker:
    View
{
    let model: GitLabIssueCreationModel
    let accountID: GitLabAccountID
    let appSession: AppSession

    var body: some View {
        if let labelsModel = model.labelsModel {
            GitLabIssueCreationLabelList(
                model: model,
                labelsModel: labelsModel,
                accountID: accountID,
                appSession: appSession
            )
        } else {
            ContentUnavailableView(
                "Choose a project",
                systemImage: "tag"
            )
        }
    }
}

private struct GitLabIssueCreationLabelList:
    View
{
    let model: GitLabIssueCreationModel
    let labelsModel:
        GitLabPaginatedResourceModel<
            GitLabProjectLabel,
            Int
        >
    let accountID: GitLabAccountID
    let appSession: AppSession

    var body: some View {
        @Bindable var labelsModel =
            labelsModel

        listContent
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $labelsModel.searchText,
                prompt: "Search loaded labels"
            )
            .task {
                await labelsModel
                    .loadIfNeeded()
                await handleAuthenticationFailure()
            }
    }

    @ViewBuilder
    private var listContent: some View {
        if
            labelsModel.isLoadingInitial,
            labelsModel.items.isEmpty
        {
            GitLabLoadingStateView(
                message: "Loading labels"
            )
        } else if
            labelsModel.items.isEmpty,
            let error = labelsModel.loadError
        {
            GitLabRetryStateView(error: error) {
                Task {
                    await labelsModel.refresh()
                }
            }
        } else if
            labelsModel.displayedItems.isEmpty
        {
            ContentUnavailableView.search(
                text: labelsModel.searchText
            )
        } else {
            List {
                ForEach(
                    labelsModel.displayedItems
                ) { label in
                    Button {
                        model.toggleLabel(label)
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName:
                                    "tag.fill"
                            )
                            .foregroundStyle(
                                .orange
                            )
                            Text(label.name)
                                .foregroundStyle(
                                    .primary
                                )
                            Spacer()
                            if
                                model
                                    .selectedLabelNames
                                    .contains(
                                        label.name
                                    )
                            {
                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .fontWeight(
                                    .semibold
                                )
                                .foregroundStyle(
                                    .orange
                                )
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        label.archived == true
                    )
                    .accessibilityValue(
                        model.selectedLabelNames
                            .contains(label.name)
                        ? "Selected"
                        : "Not selected"
                    )
                    .task {
                        await labelsModel
                            .loadNextPageIfNeeded(
                                after: label
                            )
                    }
                }

                paginationFooter(
                    model: labelsModel,
                    title: "labels"
                )
            }
            .listStyle(.insetGrouped)
        }
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                labelsModel
                .authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}

private struct GitLabIssueCreationAssigneePicker:
    View
{
    let model: GitLabIssueCreationModel
    let accountID: GitLabAccountID
    let appSession: AppSession

    var body: some View {
        if let membersModel = model.membersModel {
            GitLabIssueCreationAssigneeList(
                model: model,
                membersModel: membersModel,
                accountID: accountID,
                appSession: appSession
            )
        } else {
            ContentUnavailableView(
                "Choose a project",
                systemImage: "person.2"
            )
        }
    }
}

private struct GitLabIssueCreationAssigneeList:
    View
{
    let model: GitLabIssueCreationModel
    let membersModel:
        GitLabPaginatedResourceModel<
            GitLabProjectMember,
            Int
        >
    let accountID: GitLabAccountID
    let appSession: AppSession

    var body: some View {
        @Bindable var membersModel =
            membersModel

        listContent
            .navigationTitle("Assignees")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $membersModel.searchText,
                prompt: "Search loaded members"
            )
            .safeAreaInset(edge: .bottom) {
                if
                    model.selectedAssigneeIDs
                        .count > 1
                {
                    Text(
                        "Multiple assignees require GitLab Premium or Ultimate."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.bar)
                }
            }
            .task {
                await membersModel
                    .loadIfNeeded()
                await handleAuthenticationFailure()
            }
    }

    @ViewBuilder
    private var listContent: some View {
        if
            membersModel.isLoadingInitial,
            membersModel.items.isEmpty
        {
            GitLabLoadingStateView(
                message: "Loading members"
            )
        } else if
            membersModel.items.isEmpty,
            let error = membersModel.loadError
        {
            GitLabRetryStateView(error: error) {
                Task {
                    await membersModel.refresh()
                }
            }
        } else if
            membersModel.displayedItems.isEmpty
        {
            ContentUnavailableView.search(
                text: membersModel.searchText
            )
        } else {
            List {
                ForEach(
                    model
                        .displayedAssignableMembers
                ) { member in
                    Button {
                        model.toggleAssignee(
                            member
                        )
                    } label: {
                        HStack(spacing: 12) {
                            GitLabUserAvatar(
                                user:
                                    GitLabUserSummary(
                                        id:
                                            member.id,
                                        username:
                                            member
                                            .username,
                                        name:
                                            member.name,
                                        avatarURL:
                                            member
                                            .avatarURL
                                    ),
                                size: 34
                            )
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    member.name
                                )
                                .foregroundStyle(
                                    .primary
                                )
                                Text(
                                    "@\(member.username)"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                            Spacer()
                            if
                                model
                                    .selectedAssigneeIDs
                                    .contains(
                                        member.id
                                    )
                            {
                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .fontWeight(
                                    .semibold
                                )
                                .foregroundStyle(
                                    .orange
                                )
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        model.selectedAssigneeIDs
                            .contains(member.id)
                        ? "Selected"
                        : "Not selected"
                    )
                    .task {
                        await model
                            .loadNextAssignableMembersPageIfNeeded(
                                after: member
                            )
                    }
                }

                paginationFooter(
                    model: membersModel,
                    title: "members"
                )
            }
            .listStyle(.insetGrouped)
        }
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                membersModel
                .authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}

@ViewBuilder
private func paginationFooter<Item>(
    model:
        GitLabPaginatedResourceModel<
            Item,
            Int
        >,
    title: String
) -> some View where Item: Sendable {
    if model.isLoadingNextPage {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    } else if
        model.didFailNextPage,
        let error = model.loadError
    {
        GitLabInlineRetryRow(
            title:
                "Couldn’t load more \(title)",
            error: error,
            accessibilityIdentifier:
                "issueCreation.\(title).nextPageError"
        ) {
            Task {
                await model.retryNextPage()
            }
        }
    }
}
