import SwiftUI

struct GitLabEmojiReactionView: View {
    let allowsMutation: Bool
    let accountID: GitLabAccountID
    let appSession: AppSession

    @State private var model:
        GitLabEmojiReactionsModel
    @State private var
        isPickerPresented = false

    init(
        awardable: GitLabEmojiAwardable,
        currentUserID: Int,
        apiAccess: GitLabAPIAccess,
        loader:
            any GitLabEmojiReactionLoading,
        mutator:
            any GitLabEmojiReactionMutating,
        allowsMutation: Bool = true,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.allowsMutation = allowsMutation
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabEmojiReactionsModel(
                    awardable: awardable,
                    currentUserID:
                        currentUserID,
                    apiAccess: apiAccess,
                    loader: loader,
                    mutator: mutator
                )
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            if showsContent {
                reactionControls

                if let failure =
                    model.mutationFailure
                {
                    mutationFailureView(
                        failure
                    )
                } else if
                    let error =
                        model.loadError
                {
                    loadFailureView(error)
                }
            }
        }
        .accessibilityElement(
            children: .contain
        )
        .accessibilityIdentifier(
            targetIdentifier
        )
        .task {
            await model.loadIfNeeded()
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
    }

    private var showsContent: Bool {
        !model.groups.isEmpty
            || model.loadError != nil
            || (
                allowsMutation
                    && model.hasWriteAccess
            )
    }

    private var reactionControls:
        some View
    {
        HStack(spacing: 8) {
            if !model.groups.isEmpty {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 8) {
                        ForEach(model.groups) {
                            group in
                            groupControl(group)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if
                allowsMutation,
                model.hasWriteAccess
            {
                reactionPicker
            }
        }
        .accessibilityLabel("Emoji reactions")
        .accessibilityHint(
            readOnlyAccessibilityHint
        )
    }

    @ViewBuilder
    private func groupControl(
        _ group:
            GitLabEmojiReactionGroup
    ) -> some View {
        if
            allowsMutation,
            model.hasWriteAccess
        {
            Button {
                Task {
                    await model
                        .toggleReaction(
                            named:
                                group.name
                        )
                    await handleAuthenticationFailure()
                }
            } label: {
                reactionChip(group)
            }
            .buttonStyle(.plain)
            .disabled(
                !model.canMutate
                    || group.isPending
                    || model.requiresRefresh(
                        name: group.name
                    )
            )
            .accessibilityLabel(
                accessibilityLabel(
                    for: group
                )
            )
            .accessibilityHint(
                accessibilityHint(
                    for: group
                )
            )
            .accessibilityIdentifier(
                targetIdentifier
                    + ".group."
                    + group.name
            )
        } else {
            reactionChip(group)
                .accessibilityElement()
                .accessibilityLabel(
                    accessibilityLabel(
                        for: group
                    )
                )
                .accessibilityIdentifier(
                    targetIdentifier
                        + ".group."
                        + group.name
                )
        }
    }

    private func reactionChip(
        _ group:
            GitLabEmojiReactionGroup
    ) -> some View {
        HStack(spacing: 5) {
            Text(group.display)
                .lineLimit(1)

            Text(
                group.count,
                format: .number
            )
            .font(.caption.monospacedDigit())

            if group.isPending {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
        }
        .font(.callout)
        .foregroundStyle(
            group.isSelectedByCurrentUser
                ? Color.orange
                : Color.primary
        )
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(
            group.isSelectedByCurrentUser
                ? Color.orange.opacity(0.14)
                : Color.secondary.opacity(0.1),
            in: .capsule
        )
        .overlay {
            Capsule()
                .stroke(
                    group.isSelectedByCurrentUser
                        ? Color.orange
                            .opacity(0.5)
                        : Color.primary
                            .opacity(0.08),
                    lineWidth: 1
                )
        }
        .contentShape(.capsule)
    }

    private var reactionPicker: some View {
        Button {
            isPickerPresented = true
        } label: {
            Text("🙂")
                .font(.title3)
                .frame(
                    width: 44,
                    height: 44
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!model.canMutate)
        .accessibilityLabel("Add reaction")
        .accessibilityHint(
            model.canMutate
                ? "Opens common emoji below this comment."
                : "Wait for reactions to finish loading."
        )
        .accessibilityIdentifier(
            targetIdentifier + ".picker"
        )
        .popover(
            isPresented:
                $isPickerPresented,
            attachmentAnchor:
                .point(.bottomLeading),
            arrowEdge: .top
        ) {
            reactionPickerPopover
                .presentationCompactAdaptation(
                    .popover
                )
        }
    }

    private var reactionPickerPopover:
        some View
    {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 6) {
                ForEach(
                    GitLabEmojiPickerItem.common
                ) { item in
                    reactionPickerItem(item)
                }
            }
            .padding(10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(
            horizontal: true,
            vertical: true
        )
        .accessibilityElement(
            children: .contain
        )
        .accessibilityLabel(
            "Choose a reaction"
        )
    }

    private func reactionPickerItem(
        _ item: GitLabEmojiPickerItem
    ) -> some View {
        let isPending =
            model.isPending(name: item.name)
        let requiresRefresh =
            model.requiresRefresh(
                name: item.name
            )
        let isSelected =
            model.groups.first {
                $0.name == item.name
            }?
            .isSelectedByCurrentUser
            == true
        let isDisabled =
            !model.canMutate
            || isPending
            || requiresRefresh

        return Button {
            isPickerPresented = false
            Task {
                await model
                    .toggleReaction(
                        named: item.name
                    )
                await handleAuthenticationFailure()
            }
        } label: {
            ZStack {
                Text(item.display)
                    .font(.title2)

                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(
                            true
                        )
                }
            }
            .frame(
                width: 40,
                height: 40
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(
            isDisabled
                ? 0.45
                : 1
        )
        .accessibilityLabel(item.title)
        .accessibilityValue(
            pickerAccessibilityValue(
                isSelected: isSelected,
                isPending: isPending,
                requiresRefresh:
                    requiresRefresh
            )
        )
        .accessibilityHint(
            isSelected
                ? "Removes your reaction."
                : "Adds this reaction."
        )
        .accessibilityIdentifier(
            targetIdentifier
                + ".picker."
                + item.name
        )
    }

    private func pickerAccessibilityValue(
        isSelected: Bool,
        isPending: Bool,
        requiresRefresh: Bool
    ) -> String {
        var values: [String] = []
        if isSelected {
            values.append("Selected")
        }
        if isPending {
            values.append("Updating")
        } else if requiresRefresh {
            values.append(
                "Refresh required"
            )
        }
        return values.joined(
            separator: ", "
        )
    }

    private func mutationFailureView(
        _ failure:
            GitLabEmojiReactionMutationFailure
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(
                    failure.certainty
                        == .deliveryUnknown
                        ? "Reaction update uncertain. Refresh to verify it before trying again."
                        : failure.error.description
                )
            } icon: {
                Image(
                    systemName:
                        failure.certainty
                            == .deliveryUnknown
                            ? "questionmark.circle"
                            : "exclamationmark.triangle"
                )
            }
            .font(.caption)
            .foregroundStyle(.orange)

            Spacer(minLength: 8)

            if
                failure.certainty
                    == .deliveryUnknown
            {
                Button("Refresh") {
                    Task {
                        await model.refresh()
                        await handleAuthenticationFailure()
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
            } else {
                Button {
                    model.dismissMutationFailure()
                } label: {
                    Image(
                        systemName: "xmark"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Dismiss reaction error"
                )
            }
        }
        .accessibilityIdentifier(
            targetIdentifier
                + ".mutationFailure"
        )
    }

    private func loadFailureView(
        _ error: GitLabSessionClientError
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(
                "Couldn’t load reactions",
                systemImage:
                    "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button("Retry") {
                Task {
                    await model.refresh()
                    await handleAuthenticationFailure()
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.glass)
            .accessibilityHint(
                error.description
            )
        }
        .accessibilityIdentifier(
            targetIdentifier + ".loadFailure"
        )
    }

    private func accessibilityLabel(
        for group:
            GitLabEmojiReactionGroup
    ) -> String {
        let name =
            GitLabEmojiPickerItem
            .item(named: group.name)?
            .title
            ?? GitLabEmojiPickerItem
            .display(for: group.name)
        var parts = [
            name,
            "\(group.count) "
                + (
                    group.count == 1
                        ? "reaction"
                        : "reactions"
                ),
        ]
        if group.isSelectedByCurrentUser {
            parts.append("reacted by you")
        }
        if group.isPending {
            parts.append("updating")
        }
        return parts.joined(separator: ", ")
    }

    private func accessibilityHint(
        for group:
            GitLabEmojiReactionGroup
    ) -> String {
        guard
            allowsMutation,
            model.hasWriteAccess
        else {
            return readOnlyAccessibilityHint
        }
        if
            model.requiresRefresh(
                name: group.name
            )
        {
            return "Refresh reactions before trying this action again."
        }
        return group.isSelectedByCurrentUser
            ? "Removes your reaction."
            : "Adds this reaction."
    }

    private var readOnlyAccessibilityHint:
        String
    {
        if
            !model.hasWriteAccess
        {
            return "Read-only access. The api scope is required to change reactions."
        }
        if !allowsMutation {
            return "Reactions on system activity cannot be changed here."
        }
        return ""
    }

    private var targetIdentifier: String {
        var value: String
        switch model.awardable.resource {
        case let .issue(route):
            value =
                "reactions.issue."
                + "\(route.projectID)."
                + "\(route.issueIID)"
        case let .mergeRequest(route):
            value =
                "reactions.mergeRequest."
                + "\(route.projectID)."
                + "\(route.mergeRequestIID)"
        }
        if let noteID =
            model.awardable.noteID
        {
            value += ".note.\(noteID)"
        } else {
            value += ".resource"
        }
        return value
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
