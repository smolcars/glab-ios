import SwiftUI

struct
    GitLabMergeRequestApprovalManagementView:
    View
{
    let approvalState:
        GitLabResourceDetailState<
            GitLabMergeRequestApprovalAvailability
        >
    let model:
        GitLabMergeRequestApprovalManagementModel
    let accountID: GitLabAccountID

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            summaryControl

            if isExpanded {
                Divider()
                    .padding(.leading, 44)

                expandedContent
            }
        }
        .background(
            Color.glabRaisedSurface,
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .alert(
            confirmationTitle,
            isPresented:
                confirmationIsPresented,
            presenting:
                model.confirmation
        ) { confirmation in
            Button(
                confirmation
                    .action
                    .confirmationButtonTitle,
                role:
                    confirmation.action
                        == .unapprove
                    ? .destructive
                    : nil
            ) {
                Task {
                    await model
                        .confirmAction()
                }
            }
            .accessibilityIdentifier(
                "mergeRequests.approvals.confirm"
            )
            Button(
                "Cancel",
                role: .cancel
            ) {
                model
                    .cancelConfirmation()
            }
        } message: { confirmation in
            Text(
                confirmation.action
                    .confirmationMessage
            )
        }
        .sheet(
            isPresented:
                approverPickerIsPresented
        ) {
            GitLabMergeRequestApproverPicker(
                model: model
            )
            .presentationDragIndicator(
                .visible
            )
        }
    }

    private var summaryControl:
        some View
    {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                summaryIcon
                    .frame(width: 22)
                    .accessibilityHidden(true)

                Text(summaryTitle)
                    .font(
                        .glabCallout.weight(
                            .semibold
                        )
                    )
                    .lineLimit(1)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                approverAvatars

                Image(
                    systemName:
                        isExpanded
                        ? "chevron.up"
                        : "chevron.down"
                )
                .font(
                    .glabCaption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel("Approvals")
        .accessibilityValue(
            summaryTitle
                + (
                    isExpanded
                    ? ", expanded"
                    : ", collapsed"
                )
        )
        .accessibilityHint(
            isExpanded
                ? "Collapses approval details."
                : "Expands approval details."
        )
        .accessibilityIdentifier(
            "mergeRequests.approvals.summary"
        )
    }

    @ViewBuilder
    private var summaryIcon:
        some View
    {
        switch approvalState {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(
                systemName:
                    "exclamationmark.circle.fill"
            )
            .foregroundStyle(.orange)
        case .loaded(.unavailable):
            Image(
                systemName:
                    "questionmark.circle"
            )
            .foregroundStyle(.secondary)
        case .loaded(.available):
            Image(
                systemName:
                    summaryStatus
                        .systemImage
            )
            .foregroundStyle(
                summaryStatus.tint
            )
        }
    }

    @ViewBuilder
    private var approverAvatars:
        some View
    {
        if !approvingUsers.isEmpty {
            HStack(spacing: -7) {
                ForEach(
                    Array(
                        approvingUsers
                            .prefix(3)
                    )
                ) { user in
                    GitLabUserAvatar(
                        user: user.summary,
                        size: 26
                    )
                }

                if approvingUsers.count > 3 {
                    Text(
                        "+\(approvingUsers.count - 3)"
                    )
                    .font(
                        .glabCaption2.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .padding(.leading, 10)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var expandedContent:
        some View
    {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            globalApprovals

            approvalAction

            if let failure = model.failure {
                failureRow(failure)
            }

            detailedRules
        }
        .padding(12)
    }

    @ViewBuilder
    private var globalApprovals:
        some View
    {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text("Approved")
                .font(
                    .glabCaption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(.secondary)

            if summaryPresentation?
                .approvals.isEmpty
                != false
            {
                Text("No approvals yet")
                    .font(.glabCallout)
                    .foregroundStyle(
                        .secondary
                    )
            } else if
                let approvals =
                    summaryPresentation?
                    .approvals
            {
                ForEach(
                    Array(
                        approvals
                            .enumerated()
                    ),
                    id: \.offset
                ) { _, approval in
                    if let user = approval.user {
                        HStack(spacing: 9) {
                            GitLabUserAvatar(
                                user:
                                    user.summary,
                                size: 30
                            )

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 1
                            ) {
                                Text(
                                    user.displayName
                                )
                                .font(
                                    .glabCallout
                                        .weight(
                                            .medium
                                        )
                                )
                                if
                                    let approvedAt =
                                        approval
                                        .approvedAt
                                {
                                    Text(
                                        approvedAt
                                            .formatted(
                                                date:
                                                    .abbreviated,
                                                time:
                                                    .shortened
                                            )
                                    )
                                    .font(.glabCaption2)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }

                            Spacer(minLength: 0)

                            Image(
                                systemName:
                                    "checkmark.circle.fill"
                            )
                            .foregroundStyle(
                                .green
                            )
                            .accessibilityHidden(
                                true
                            )
                        }
                        .accessibilityElement(
                            children: .combine
                        )
                        .accessibilityLabel(
                            user.displayName
                                + ", approved"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailedRules:
        some View
    {
        switch model.detailsModel.state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading rules")
                    .font(.glabCaption)
                    .foregroundStyle(
                        .secondary
                    )
            }
        case let .failed(error):
            detailRetryRow(error)
        case .loaded(.unavailable):
            EmptyView()
        case let .loaded(
            .available(details)
        ):
            if
                details
                    .approvalRulesOverwritten
                    == true
            {
                Label(
                    "Rules overridden for this merge request",
                    systemImage:
                        "arrow.triangle.branch"
                )
                .font(.glabCaption)
                .foregroundStyle(.secondary)
            }

            ForEach(
                Array(
                    details.rules
                        .enumerated()
                ),
                id: \.offset
            ) { _, rule in
                ruleRow(rule)
            }

            if let error =
                model.detailsModel
                    .refreshError
            {
                detailRetryRow(error)
            }
        }
    }

    private func ruleRow(
        _ rule:
            GitLabMergeRequestApprovalRule
    ) -> some View {
        let presentation =
            GitLabMergeRequestApprovalRulePresentation(
                rule: rule
            )

        return VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack(spacing: 8) {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(presentation.title)
                        .font(
                            .glabCallout.weight(
                                .semibold
                            )
                        )
                    Label(
                        presentation
                            .state.title,
                        systemImage:
                            presentation
                            .state
                            .systemImage
                    )
                    .font(.glabCaption)
                    .foregroundStyle(
                        presentation
                            .state.tint
                    )
                }

                Spacer(minLength: 0)

                if
                    case .editable =
                        presentation
                        .editability,
                    model.apiAccess.canWrite
                {
                    Button {
                        Task {
                            await model
                                .beginAddingApprover(
                                    to: rule
                                )
                        }
                    } label: {
                        if model.isLoadingRule {
                            ProgressView()
                                .controlSize(
                                    .small
                                )
                        } else {
                            Image(
                                systemName:
                                    "person.badge.plus"
                            )
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .disabled(
                        model.isLoadingRule
                            || model.isBusy
                    )
                    .accessibilityLabel(
                        "Add approver to \(presentation.title)"
                    )
                    .accessibilityIdentifier(
                        "mergeRequests.approvals.rule.add"
                    )
                }
            }

            ForEach(
                presentation.people,
                id: \.user.id
            ) { person in
                HStack(spacing: 8) {
                    GitLabUserAvatar(
                        user:
                            person.user
                            .summary,
                        size: 26
                    )
                    Text(
                        person.user
                            .displayName
                    )
                    .font(.glabCaption)
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(
                        person.state.title
                    )
                    .font(
                        .glabCaption2.weight(
                            .medium
                        )
                    )
                    .foregroundStyle(
                        person.state.tint
                    )
                }
                .accessibilityElement(
                    children: .combine
                )
            }

            if
                let lockMessage =
                    presentation
                    .editability
                    .lockMessage
            {
                Text(lockMessage)
                    .font(.glabCaption2)
                    .foregroundStyle(
                        .secondary
                    )
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var approvalAction:
        some View
    {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(model.phase.title)
                    .font(.glabCaption)
                    .foregroundStyle(
                        .secondary
                    )
            } else if
                model.hasUnresolvedMutation
            {
                Button(
                    "Check GitLab",
                    systemImage:
                        "arrow.triangle.2.circlepath"
                ) {
                    Task {
                        await model
                            .checkGitLab()
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier(
                    "mergeRequests.approvals.check"
                )
            } else if model.canUnapprove {
                Button(
                    "Remove approval",
                    systemImage:
                        "checkmark.circle.fill"
                ) {
                    model.requestUnapprove()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier(
                    "mergeRequests.approvals.unapprove"
                )
            } else if model.canApprove {
                Button(
                    "Approve",
                    systemImage:
                        "checkmark.circle"
                ) {
                    model.requestApprove()
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .controlSize(.small)
                .accessibilityIdentifier(
                    "mergeRequests.approvals.approve"
                )
            } else if
                model
                    .requiresGitLabReauthenticationForApproval
            {
                Label(
                    "GitLab sign-in required",
                    systemImage: "lock.fill"
                )
                .font(.glabCaption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier(
                    "mergeRequests.approvals.reauthentication"
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func detailRetryRow(
        _ error:
            GitLabSessionClientError
    ) -> some View {
        HStack(spacing: 8) {
            Image(
                systemName:
                    "exclamationmark.circle"
            )
            .foregroundStyle(.orange)

            Text(
                "Rules couldn’t be refreshed."
            )
            .font(.glabCaption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(
                "Retry",
                systemImage:
                    "arrow.clockwise"
            ) {
                Task {
                    await model
                        .refreshDetails()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.small)
            .frame(width: 44, height: 44)
            .accessibilityLabel(
                "Retry approval rules"
            )
            .accessibilityHint(
                error.localizedDescription
            )
        }
    }

    private func failureRow(
        _ failure:
            GitLabMergeRequestApprovalManagementFailure
    ) -> some View {
        Label(
            failure.userMessage,
            systemImage:
                "exclamationmark.circle"
        )
        .font(.glabCaption)
        .foregroundStyle(.orange)
        .accessibilityIdentifier(
            "mergeRequests.approvals.failure"
        )
    }

    private var summaryPresentation:
        GitLabMergeRequestApprovalSummaryPresentation?
    {
        guard
            case let .loaded(
                .available(summary)
            ) = approvalState
        else {
            return nil
        }
        return
            GitLabMergeRequestApprovalSummaryPresentation(
                summary: summary,
                currentUserID:
                    accountID.userID
            )
    }

    private var approvingUsers:
        [GitLabAPIUser]
    {
        summaryPresentation?
            .approvals
            .compactMap(\.user)
        ?? []
    }

    private var summaryStatus:
        GitLabMergeRequestApprovalSummaryStatus
    {
        summaryPresentation?
            .status
        ?? .none
    }

    private var summaryTitle: String {
        switch approvalState {
        case .idle, .loading:
            "Loading approvals"
        case .failed:
            "Approvals unavailable"
        case .loaded(.unavailable):
            "Approvals unavailable"
        case .loaded(.available):
            summaryStatus.title
        }
    }

    private var confirmationTitle: String {
        switch model.confirmation?.action {
        case .approve:
            "Approve merge request?"
        case .unapprove:
            "Remove your approval?"
        case nil:
            "Update approval?"
        }
    }

    private var confirmationIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                model.confirmation != nil
            },
            set: { _ in }
        )
    }

    private var approverPickerIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                model.selectedRule != nil
            },
            set: {
                if !$0 {
                    model
                        .cancelRuleAddition()
                }
            }
        )
    }
}

private struct
    GitLabMergeRequestApproverPicker:
    View
{
    let model:
        GitLabMergeRequestApprovalManagementModel

    @State private var searchText = ""
    @State private var hasStartedSearchTask =
        false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if
                    let failure =
                        model.failure,
                    model.memberOptionsError
                        == nil
                {
                    pickerFailure(failure)
                    Divider()
                }

                memberContent
            }
            .navigationTitle("Add approver")
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("Cancel") {
                        model
                            .cancelRuleAddition()
                    }
                }
            }
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                GitLabSearchField(
                    text: $searchText,
                    prompt:
                        "Search project members",
                    accessibilityIdentifier:
                        "approval.members.search"
                )
            }
            .ignoresSafeArea(
                .keyboard,
                edges: .bottom
            )
            .task(id: searchText) {
                guard hasStartedSearchTask else {
                    hasStartedSearchTask = true
                    return
                }
                do {
                    try await Task.sleep(
                        for:
                            .milliseconds(300)
                    )
                } catch {
                    return
                }
                await model.searchMembers(
                    searchText
                )
            }
        }
        .interactiveDismissDisabled(
            model.isBusy
        )
        .alert(
            "Add approver?",
            isPresented:
                additionConfirmationIsPresented,
            presenting:
                model
                .ruleAdditionConfirmation
        ) { confirmation in
            Button("Add") {
                Task {
                    await model
                        .confirmRuleAddition()
                    if model.failure == nil {
                        model
                            .cancelRuleAddition()
                    }
                }
            }
            .accessibilityIdentifier(
                "mergeRequests.approvals.rule.confirm"
            )
            Button(
                "Cancel",
                role: .cancel
            ) {
                model
                    .cancelRuleAdditionConfirmation()
            }
        } message: { confirmation in
            Text(
                "Add \(confirmation.member.name) to “\(confirmation.ruleName)”? Existing approvers, groups, and the required count will be preserved."
            )
        }
    }

    @ViewBuilder
    private var memberContent: some View {
        if
            model.availableMembers
                .isEmpty,
            model.isLoadingMembers
        {
            GitLabLoadingStateView(
                message:
                    "Loading project members"
            )
        } else if
            model.availableMembers
                .isEmpty,
            let error =
                model
                .memberOptionsError
        {
            GitLabRetryStateView(
                error: error
            ) {
                Task {
                    await model
                        .searchMembers(
                            searchText
                        )
                }
            }
        } else if
            model.availableMembers
                .isEmpty
        {
            ContentUnavailableView(
                "No available approvers",
                systemImage:
                    "person.crop.circle.badge.xmark",
                description:
                    Text(
                        "Everyone shown by this rule is already included."
                    )
            )
        } else {
            GlabList {
                ForEach(
                    model.availableMembers
                ) { member in
                    Button {
                        model
                            .selectApprover(
                                member
                            )
                    } label: {
                        HStack(
                            spacing: 12
                        ) {
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
                                alignment:
                                    .leading,
                                spacing: 2
                            ) {
                                Text(
                                    member
                                        .name
                                )
                                .foregroundStyle(
                                    .primary
                                )
                                Text(
                                    "@\(member.username)"
                                )
                                .font(.glabCaption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                            Spacer(
                                minLength: 0
                            )
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(member.name), @\(member.username)"
                    )
                    .accessibilityHint(
                        "Adds this person after confirmation."
                    )
                    .task {
                        if
                            member.id
                                == model
                                .availableMembers
                                .last?.id
                        {
                            await model
                                .loadNextMembersPage()
                        }
                    }
                }

                if model.isLoadingMembers {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(
                        .hidden
                    )
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func pickerFailure(
        _ failure:
            GitLabMergeRequestApprovalManagementFailure
    ) -> some View {
        HStack(spacing: 8) {
            Image(
                systemName:
                    "exclamationmark.circle"
            )
            .foregroundStyle(.orange)

            Text(failure.userMessage)
                .font(.glabCaption)
                .foregroundStyle(
                    .secondary
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            if model.hasUnresolvedMutation {
                Button {
                    Task {
                        await model
                            .checkGitLab()
                    }
                } label: {
                    if model.isBusy {
                        ProgressView()
                            .controlSize(
                                .small
                            )
                    } else {
                        Image(
                            systemName:
                                "arrow.triangle.2.circlepath"
                        )
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .frame(
                    width: 44,
                    height: 44
                )
                .disabled(model.isBusy)
                .accessibilityLabel(
                    "Check GitLab"
                )
                .accessibilityIdentifier(
                    "mergeRequests.approvals.rule.check"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var additionConfirmationIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                model
                    .ruleAdditionConfirmation
                    != nil
            },
            set: { _ in }
        )
    }
}

private extension
    GitLabMergeRequestApprovalSummaryStatus
{
    var title: String {
        switch self {
        case .notRequired:
            "No approval required"
        case .complete:
            "Approvals complete"
        case let .remaining(count):
            count == 1
                ? "1 approval remaining"
                : "\(count) approvals remaining"
        case let .recorded(count):
            count == 1
                ? "1 approval"
                : "\(count) approvals"
        case .none:
            "No approvals yet"
        }
    }

    var systemImage: String {
        switch self {
        case .notRequired, .complete:
            "checkmark.circle.fill"
        case .remaining:
            "clock.fill"
        case .recorded:
            "person.crop.circle.badge.checkmark"
        case .none:
            "person.crop.circle"
        }
    }

    var tint: Color {
        switch self {
        case .notRequired, .complete:
            .green
        case .remaining:
            .orange
        case .recorded:
            .blue
        case .none:
            .secondary
        }
    }
}

private extension
    GitLabMergeRequestApprovalRuleState
{
    var title: String {
        switch self {
        case .approved:
            return "Approved"
        case let .pending(remaining):
            if let remaining {
                return remaining == 1
                    ? "1 remaining"
                    : "\(remaining) remaining"
            }
            return "Pending"
        case .notRequired:
            return "Not required"
        case .unknown:
            return "Status unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .approved, .notRequired:
            "checkmark.circle.fill"
        case .pending:
            "clock.fill"
        case .unknown:
            "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .approved, .notRequired:
            .green
        case .pending:
            .orange
        case .unknown:
            .secondary
        }
    }
}

private extension
    GitLabMergeRequestApprovalPersonState
{
    var title: String {
        switch self {
        case .approved:
            "Approved"
        case .eligible:
            "Eligible"
        }
    }

    var tint: Color {
        switch self {
        case .approved:
            .green
        case .eligible:
            .secondary
        }
    }
}

private extension
    GitLabMergeRequestApprovalRuleEditability
{
    var lockMessage: String? {
        switch self {
        case .editable:
            nil
        case .locked(.hiddenGroups):
            "Hidden group membership; manage this rule in GitLab."
        case .locked(.systemRule):
            "GitLab manages this rule."
        case .locked(
            .unknownRuleType
        ):
            "This rule type is read-only."
        case .locked(.incomplete):
            "Complete rule membership is unavailable."
        }
    }
}

private extension
    GitLabMergeRequestApprovalManagementAction
{
    var confirmationButtonTitle: String {
        switch self {
        case .approve:
            "Approve"
        case .unapprove:
            "Remove Approval"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .approve:
            "Glab will recheck the current revision, then add your approval on GitLab."
        case .unapprove:
            "Glab will recheck the current revision, then remove only your approval on GitLab."
        }
    }
}

private extension
    GitLabMergeRequestApprovalManagementPhase
{
    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .preflighting:
            "Checking revision"
        case .mutating:
            "Updating GitLab"
        case .reconciling:
            "Confirming update"
        case .checkingGitLab:
            "Checking GitLab"
        }
    }
}

extension
    GitLabMergeRequestApprovalManagementFailure
{
    var userMessage: String {
        switch self {
        case let .load(error),
             let .memberOptions(error),
             let .rejected(error),
             let .reconciliation(error):
            error.localizedDescription
        case .readOnly:
            "This account has read-only API access."
        case .accountChanged:
            "The active GitLab account changed."
        case .unavailable:
            "Approval details are unavailable."
        case .staleRevision:
            "The merge request revision changed. Refresh before trying again."
        case .approvalSyncing:
            "GitLab is still syncing approvals."
        case .permissionDenied:
            "GitLab did not allow this approval change."
        case .gitLabReauthenticationRequired:
            "GitLab requires you to sign in again before approving. Open this merge request in GitLab to continue."
        case .unsafeRule(.hiddenGroups):
            "Hidden rule membership cannot be safely changed."
        case .unsafeRule(.systemRule):
            "GitLab manages this approval rule."
        case .unsafeRule(.unknownRuleType):
            "This approval rule type is read-only."
        case .unsafeRule(.incomplete):
            "Complete rule membership is unavailable."
        case .ruleChanged:
            "The approval rule changed. Open it again."
        case .memberUnavailable:
            "That person is already included or unavailable."
        case .deliveryUnknown:
            "GitLab may have received the change. Check GitLab before trying again."
        case .authoritativeMismatch:
            "GitLab returned a different merge request."
        case .notApplied:
            "GitLab did not apply the change."
        }
    }
}
