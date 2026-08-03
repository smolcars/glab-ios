import SwiftUI

struct GitLabResourceMetadataEditorView: View {
    let model:
        GitLabResourceMetadataEditorModel
    let accountID: GitLabAccountID
    let appSession: AppSession
    let issueStatusModel:
        GitLabIssueStatusModel?
    let planningModel:
        GitLabIssuePlanningModel?
    let statusActionDidFinish:
        () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsDiscard = false

    init(
        model:
            GitLabResourceMetadataEditorModel,
        accountID: GitLabAccountID,
        appSession: AppSession,
        issueStatusModel:
            GitLabIssueStatusModel? = nil,
        planningModel:
            GitLabIssuePlanningModel? = nil,
        statusActionDidFinish:
            @escaping () -> Void = {}
    ) {
        self.model = model
        self.accountID = accountID
        self.appSession = appSession
        self.issueStatusModel =
            issueStatusModel
        self.planningModel = planningModel
        self.statusActionDidFinish =
            statusActionDidFinish
    }

    var body: some View {
        NavigationStack {
            GlabList {
                issueFieldsSection
                statusSection

                Section {
                    NavigationLink {
                        GitLabMetadataLabelPicker(
                            model: model
                        )
                    } label: {
                        metadataSummary(
                            title: "Labels",
                            value:
                                model
                                .selectedLabelNames,
                            systemImage: "tag"
                        )
                    }
                    .accessibilityIdentifier(
                        "metadata.labels"
                    )

                    NavigationLink {
                        GitLabMetadataMemberPicker(
                            model: model,
                            role: .assignee
                        )
                    } label: {
                        metadataSummary(
                            title: "Assignees",
                            value:
                                selectedPeopleSummary(
                                    model
                                        .selectedAssigneeIDs
                                ),
                            systemImage:
                                "person"
                        )
                    }
                    .accessibilityIdentifier(
                        "metadata.assignees"
                    )

                    if model.supportsReviewers {
                        NavigationLink {
                            GitLabMetadataMemberPicker(
                                model: model,
                                role: .reviewer
                            )
                        } label: {
                            metadataSummary(
                                title: "Reviewers",
                                value:
                                    selectedPeopleSummary(
                                        model
                                            .selectedReviewerIDs
                                    ),
                                systemImage:
                                    "person.crop.circle.badge.checkmark"
                            )
                        }
                        .accessibilityIdentifier(
                            "metadata.reviewers"
                        )
                    }
                }
            }
            .navigationTitle(
                planningModel == nil
                    && issueStatusModel == nil
                ? "Labels & People"
                : "Issue Details"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        requestDismissal()
                    }
                    .disabled(
                        model.isBusy
                            || model
                                .requiresDeliveryCheck
                            || (
                                planningModel?
                                    .isBusy
                                ?? false
                            )
                            || (
                                planningModel?
                                    .requiresDeliveryCheck
                                ?? false
                            )
                            || (
                                issueStatusModel?
                                    .isBusy
                                ?? false
                            )
                            || (
                                issueStatusModel?
                                    .requiresDeliveryCheck
                                ?? false
                            )
                    )
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Save") {
                        Task {
                            await model.save()
                        }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier(
                        "metadata.save"
                    )
                }
            }
            .task {
                async let metadata: Void =
                    model.loadOptions()
                async let planning: Void =
                    planningModel?.load()
                    ?? ()
                await metadata
                await planning
            }
            .onChange(of: model.didSucceed) {
                _, didSucceed in
                if didSucceed {
                    dismiss()
                }
            }
            .onChange(
                of:
                    authenticationFailure
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
            .interactiveDismissDisabled(
                model.isDirty
                    || model.isBusy
                    || model
                        .requiresDeliveryCheck
                    || (
                        planningModel?
                            .isBusy
                        ?? false
                    )
                    || (
                        planningModel?
                            .requiresDeliveryCheck
                        ?? false
                    )
                    || (
                        issueStatusModel?
                            .isBusy
                        ?? false
                    )
                    || (
                        issueStatusModel?
                            .requiresDeliveryCheck
                        ?? false
                    )
            )
            .alert(
                "Discard metadata changes?",
                isPresented: $showsDiscard
            ) {
                Button(
                    "Discard",
                    role: .destructive
                ) {
                    dismiss()
                }
                Button(
                    "Keep Editing",
                    role: .cancel
                ) {}
            } message: {
                Text(
                    "Your label and people selections have not been saved."
                )
            }
        }
    }

    @ViewBuilder
    private var issueFieldsSection:
        some View
    {
        if
            issueStatusModel != nil
                || planningModel != nil
        {
            Section {
                if let issueStatusModel {
                    HStack(spacing: 12) {
                        issueFieldLabel(
                            "Status",
                            systemImage:
                                "circle.dotted.circle"
                        )
                        Spacer(minLength: 12)
                        switch
                            issueStatusModel.state
                        {
                        case .idle, .loading:
                            ProgressView()
                                .controlSize(
                                    .small
                                )
                        case .unavailable:
                            Text("Unavailable")
                                .foregroundStyle(
                                    .secondary
                                )
                        case .supported:
                            GitLabIssueStatusControl(
                                model:
                                    issueStatusModel,
                                isExternallyDisabled:
                                    model.isBusy
                                    || (
                                        planningModel?
                                            .isBusy
                                        ?? false
                                    ),
                                actionDidFinish:
                                    statusActionDidFinish
                            )
                        }
                    }
                    .accessibilityIdentifier(
                        "metadata.status"
                    )
                }

                if let planningModel {
                    NavigationLink {
                        GitLabIssueMilestonePicker(
                            model:
                                planningModel
                        )
                    } label: {
                        issueFieldSummary(
                            title: "Milestone",
                            value:
                                planningModel
                                .selectedMilestoneTitle,
                            systemImage:
                                "signpost.right"
                        )
                    }
                    .disabled(
                        !planningModel.canEdit
                            || (
                                issueStatusModel?
                                    .isBusy
                                ?? false
                            )
                            || (
                                issueStatusModel?
                                    .requiresDeliveryCheck
                                ?? false
                            )
                    )
                    .accessibilityIdentifier(
                        "metadata.milestone"
                    )

                    NavigationLink {
                        GitLabIssueIterationPicker(
                            model:
                                planningModel
                        )
                    } label: {
                        issueFieldSummary(
                            title: "Iteration",
                            value:
                                planningModel
                                .selectedIterationTitle,
                            systemImage:
                                "repeat"
                        )
                    }
                    .disabled(
                        !planningModel.canEdit
                            || (
                                issueStatusModel?
                                    .isBusy
                                ?? false
                            )
                            || (
                                issueStatusModel?
                                    .requiresDeliveryCheck
                                ?? false
                            )
                    )
                    .accessibilityIdentifier(
                        "metadata.iteration"
                    )

                    if planningModel.isBusy {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(
                                    .small
                                )
                            Text(
                                planningModel
                                    .isSaving
                                ? "Saving planning change"
                                : "Loading planning fields"
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    if
                        let failure =
                            planningModel
                                .failure
                    {
                        Label(
                            failure.description,
                            systemImage:
                                planningModel
                                    .requiresDeliveryCheck
                                ? "questionmark.circle"
                                : "exclamationmark.triangle"
                        )
                        .font(.glabCallout)
                        .foregroundStyle(.orange)

                        if
                            planningModel
                                .requiresDeliveryCheck
                        {
                            Button("Check GitLab") {
                                Task {
                                    await planningModel
                                        .checkGitLab()
                                }
                            }
                            .disabled(
                                planningModel
                                    .isCheckingGitLab
                            )
                            .accessibilityIdentifier(
                                "metadata.planning.checkGitLab"
                            )
                        }
                    } else if
                        planningModel
                            .optionsError != nil
                    {
                        Button("Retry planning fields") {
                            Task {
                                await planningModel
                                    .load()
                            }
                        }
                    }
                }
            } header: {
                Text("Issue fields")
            } footer: {
                Text(
                    "Status, milestone, and iteration changes save immediately. Labels and people save with the toolbar button."
                )
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.isLoadingOptions {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading options")
                        .foregroundStyle(
                            .secondary
                        )
                }
            }
        }

        if let failure = model.failure {
            Section {
                Label(
                    failure.description,
                    systemImage:
                        model
                            .requiresDeliveryCheck
                        ? "questionmark.circle"
                        : "exclamationmark.triangle"
                )
                .font(.glabCallout)
                .foregroundStyle(.orange)

                if model.requiresDeliveryCheck {
                    Button("Check GitLab") {
                        Task {
                            await model
                                .checkGitLab()
                        }
                    }
                    .disabled(
                        model.isCheckingDelivery
                    )
                    .accessibilityIdentifier(
                        "metadata.checkDelivery"
                    )
                }
            }
        } else if let error = model.optionsError {
            Section {
                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text(error.description)
                        .font(.glabCallout)
                        .foregroundStyle(
                            .secondary
                        )
                    Button("Retry") {
                        Task {
                            await model
                                .loadOptions()
                        }
                    }
                }
            }
        }

        if !model.apiAccess.canWrite {
            Section {
                Label(
                    "Read-only account",
                    systemImage: "lock"
                )
                .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "Sign in with OAuth or an API token with the api scope to save metadata."
                )
            }
        }
    }

    private var authenticationFailure:
        GitLabSessionClientError?
    {
        model.authenticationFailure
            ?? planningModel?
                .authenticationFailure
            ?? issueStatusModel?
                .authenticationFailure
    }

    private func issueFieldLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.glabAccent)
        }
    }

    private func issueFieldSummary(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                Text(value)
                    .font(.glabCaption)
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.glabAccent)
        }
    }

    private func metadataSummary(
        title: String,
        value: [String],
        systemImage: String
    ) -> some View {
        Label {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                Text(
                    value.isEmpty
                        ? "None"
                        : value.joined(
                            separator: ", "
                        )
                )
                .font(.glabCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.glabAccent)
        }
    }

    private func selectedPeopleSummary(
        _ ids: [Int]
    ) -> [String] {
        let names = ids.compactMap { id in
            model.members.first {
                $0.id == id
            }?.name
        }
        return names.count == ids.count
            ? names
            : ["\(ids.count) selected"]
    }

    private func requestDismissal() {
        guard model.isDirty else {
            dismiss()
            return
        }
        showsDiscard = true
    }
}

private struct GitLabMetadataLabelPicker: View {
    let model:
        GitLabResourceMetadataEditorModel

    @State private var showsCreateLabel = false

    var body: some View {
        @Bindable var model = model

        GlabList {
            if
                !model
                    .selectedLabelNames
                    .isEmpty
            {
                Section("Selected") {
                    ForEach(
                        model.selectedLabelNames,
                        id: \.self
                    ) { name in
                        Button {
                            model.removeLabel(
                                named: name
                            )
                        } label: {
                            HStack {
                                Text(name)
                                    .foregroundStyle(
                                        .primary
                                    )
                                Spacer()
                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )
                                .foregroundStyle(
                                    Color.glabAccent
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Remove label \(name)"
                        )
                    }
                }
            }

            Section("Project Labels") {
                if canCreateLabel {
                    Button {
                        showsCreateLabel = true
                    } label: {
                        Label(
                            "Create “\(normalizedSearch)”",
                            systemImage: "plus"
                        )
                    }
                    .accessibilityIdentifier(
                        "metadata.createLabel"
                    )
                }

                ForEach(availableLabels) {
                    label in
                    choiceRow(
                        title: label.name,
                        subtitle:
                            label.labelDescription,
                        isSelected:
                            model
                                .selectedLabelNames
                                .contains(
                                    label.name
                                )
                    ) {
                        model.toggleLabel(label)
                    }
                    .task {
                        if
                            label.id
                                == availableLabels
                                .last?.id
                        {
                            await model
                                .loadNextLabelsPage()
                        }
                    }
                }

                if
                    availableLabels.isEmpty,
                    model.canLoadMoreLabels
                {
                    Button {
                        Task {
                            await model
                                .loadNextLabelsPage()
                        }
                    } label: {
                        Label(
                            "Load more labels",
                            systemImage:
                                "arrow.down.circle"
                        )
                    }
                    .accessibilityIdentifier(
                        "metadata.labels.loadMore"
                    )
                }
            }
        }
        .navigationTitle("Labels")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(
            edge: .top,
            spacing: 0
        ) {
            GitLabSearchField(
                text:
                    $model
                    .labelSearchText,
                prompt: "Search labels",
                accessibilityIdentifier:
                    "metadata.labels.search"
            )
        }
        .ignoresSafeArea(
            .keyboard,
            edges: .bottom
        )
        .alert(
            "Create label?",
            isPresented: $showsCreateLabel
        ) {
            Button("Create") {
                model.addLabel(
                    named:
                        model
                        .labelSearchText
                )
            }
            Button(
                "Cancel",
                role: .cancel
            ) {}
        } message: {
            Text(
                "GitLab will create “\(normalizedSearch)” in this project when you save."
            )
        }
    }

    private var normalizedSearch: String {
        model.labelSearchText
            .trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var availableLabels:
        [GitLabProjectLabel]
    {
        model.labels.filter {
            !model.selectedLabelNames
                .contains($0.name)
        }
    }

    private var canCreateLabel: Bool {
        !normalizedSearch.isEmpty
            && !(
                model.labels.map(\.name)
                    + model
                    .selectedLabelNames
            ).contains {
                $0.localizedCaseInsensitiveCompare(
                        normalizedSearch
                    ) == .orderedSame
            }
    }
}

private enum GitLabMetadataMemberRole:
    Equatable
{
    case assignee
    case reviewer

    var title: String {
        switch self {
        case .assignee:
            "Assignees"
        case .reviewer:
            "Reviewers"
        }
    }
}

private struct GitLabMetadataMemberPicker: View {
    let model:
        GitLabResourceMetadataEditorModel
    let role: GitLabMetadataMemberRole

    var body: some View {
        @Bindable var model = model

        GlabList {
            if model.members.isEmpty,
                !model.isLoadingOptions
            {
                ContentUnavailableView(
                    "No assignable members",
                    systemImage: "person.slash"
                )
            } else {
                ForEach(model.members) { member in
                    let selected =
                        isSelected(member)
                    memberChoiceRow(
                        member: member,
                        isSelected: selected,
                        isEnabled:
                            selected
                            || model
                                .canSelectMember(
                                    member
                                )
                    ) {
                        toggle(member)
                    }
                    .task {
                        if
                            member.id
                                == model
                                .members.last?.id
                        {
                            await model
                                .loadNextMembersPage()
                        }
                    }
                }
            }
        }
        .navigationTitle(role.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(
            edge: .top,
            spacing: 0
        ) {
            GitLabSearchField(
                text:
                    $model
                    .memberSearchText,
                prompt: "Search people",
                accessibilityIdentifier:
                    "metadata.members.search"
            )
        }
        .safeAreaInset(edge: .bottom) {
            if role == .reviewer {
                Text(
                    "Reviewers are separate from approval-rule approvers."
                )
                .font(.glabCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .background(.bar)
            }
        }
        .ignoresSafeArea(
            .keyboard,
            edges: .bottom
        )
    }

    private func isSelected(
        _ member: GitLabProjectMember
    ) -> Bool {
        switch role {
        case .assignee:
            model.selectedAssigneeIDs
                .contains(member.id)
        case .reviewer:
            model.selectedReviewerIDs
                .contains(member.id)
        }
    }

    private func toggle(
        _ member: GitLabProjectMember
    ) {
        switch role {
        case .assignee:
            model.toggleAssignee(member)
        case .reviewer:
            model.toggleReviewer(member)
        }
    }
}

private func memberChoiceRow(
    member: GitLabProjectMember,
    isSelected: Bool,
    isEnabled: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 12) {
            GitLabUserAvatar(
                user: GitLabUserSummary(
                    id: member.id,
                    username: member.username,
                    name: member.name,
                    avatarURL: member.avatarURL
                ),
                size: 34
            )
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(member.name)
                    .foregroundStyle(.primary)
                Text("@\(member.username)")
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected {
                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(Color.glabAccent)
            }
        }
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(
        "\(member.name), @\(member.username)"
    )
    .accessibilityValue(
        isSelected
            ? "Selected"
            : "Not selected"
    )
    .accessibilityHint(
        isEnabled
            ? "Double-tap to \(isSelected ? "remove" : "select")."
            : "This person is no longer an active project member."
    )
}

private func choiceRow(
    title: String,
    subtitle: String?,
    isSelected: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 10) {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .foregroundStyle(.primary)
                if
                    let subtitle,
                    !subtitle.isEmpty
                {
                    Text(subtitle)
                        .font(.glabCaption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                }
            }
            Spacer()
            if isSelected {
                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(Color.glabAccent)
            }
        }
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityValue(
        isSelected
            ? "Selected"
            : "Not selected"
    )
}
