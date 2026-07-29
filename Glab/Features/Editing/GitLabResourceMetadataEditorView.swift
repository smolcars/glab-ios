import SwiftUI

struct GitLabResourceMetadataEditorView: View {
    let model:
        GitLabResourceMetadataEditorModel
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.dismiss) private var dismiss
    @State private var showsDiscard = false

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("Labels & People")
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
                await model.loadOptions()
            }
            .onChange(of: model.didSucceed) {
                _, didSucceed in
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
            .interactiveDismissDisabled(
                model.isDirty
                    || model.isBusy
                    || model
                        .requiresDeliveryCheck
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
                .font(.callout)
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
                        .font(.callout)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
        }
    }

    private func selectedPeopleSummary(
        _ ids: [Int]
    ) -> [String] {
        ids.compactMap { id in
            model.members.first {
                $0.id == id
            }?.name
        }
        + (
            ids.contains(where: { id in
                !model.members.contains {
                    $0.id == id
                }
            })
            ? ["\(ids.count) selected"]
            : []
        )
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

        List {
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
                                    .orange
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
            }
        }
        .navigationTitle("Labels")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text:
                $model
                .labelSearchText,
            prompt: "Search labels"
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

        List {
            if model.members.isEmpty,
                !model.isLoadingOptions
            {
                ContentUnavailableView(
                    "No assignable members",
                    systemImage: "person.slash"
                )
            } else {
                ForEach(model.members) { member in
                    choiceRow(
                        title: member.name,
                        subtitle:
                            "@\(member.username)",
                        isSelected:
                            isSelected(member)
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
        .searchable(
            text:
                $model
                .memberSearchText,
            prompt: "Search people"
        )
        .safeAreaInset(edge: .bottom) {
            if role == .reviewer {
                Text(
                    "Reviewers are separate from approval-rule approvers."
                )
                .font(.caption)
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
                        .font(.caption)
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
                .foregroundStyle(.orange)
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
