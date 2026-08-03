import SwiftUI

private struct
    GitLabIncomingLinkAccountContext:
    Equatable
{
    let accountIDs: [GitLabAccountID]
    let activeAccountID:
        GitLabAccountID?
}

private struct
    GitLabTodoNotificationRouteContext:
    Equatable
{
    let pendingAccountKey: String?
    let accountIDs: [GitLabAccountID]
    let activeAccountID: GitLabAccountID?
}

private struct
    GitLabClipboardSuggestionContext:
    Equatable,
    Hashable
{
    let isAppActive: Bool
    let accountIDs: [GitLabAccountID]
}

struct AppRootView: View {
    let incomingLinkModel:
        GitLabIncomingLinkModel

    @Environment(AppSession.self) private var appSession
    @Environment(GitLabTodoNotificationManager.self)
    private var todoNotificationManager
    @Environment(GitLabTodoNotificationRouteModel.self)
    private var todoNotificationRouteModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showsAddAccount = false
    @State private var addAccountBaseline:
        GitLabAccountID?
    @State private var didCompleteAddAccount = false
    @State private var showsAccountChoices = false
    @State private var accountActionError: String?
    @State private var clipboardLinkSuggestionModel =
        GitLabClipboardLinkSuggestionModel()

    var body: some View {
        content
            .onChange(
                of: accountContext,
                initial: true
            ) { previous, current in
                accountContextDidChange(
                    from: previous,
                    to: current
                )
            }
            .onChange(
                of: incomingLinkModel.decision,
                initial: true
            ) { _, decision in
                showsAccountChoices =
                    decision?
                        .isAccountChoice
                        == true
            }
            .onChange(
                of: showsAccountChoices
            ) { wasPresented, isPresented in
                guard
                    wasPresented,
                    !isPresented
                else {
                    return
                }

                Task { @MainActor in
                    await Task.yield()
                    if
                        incomingLinkModel
                            .decision?
                            .isAccountChoice
                            == true
                    {
                        incomingLinkModel.clear()
                    }
                }
            }
            .task(
                id: todoNotificationRouteContext
            ) {
                await handleTodoNotificationRoute()
            }
            .task(
                id: clipboardSuggestionContext
            ) {
                guard
                    clipboardSuggestionContext
                        .isAppActive
                else {
                    return
                }

                await clipboardLinkSuggestionModel
                    .refresh(
                        hasSavedAccounts:
                            !clipboardSuggestionContext
                                .accountIDs
                                .isEmpty
                    )
            }
            .overlay(alignment: .bottom) {
                if showsClipboardLinkSuggestion {
                    GitLabClipboardLinkSuggestionView(
                        onPaste:
                            handlePastedClipboardLinks,
                        onDismiss:
                            clipboardLinkSuggestionModel
                                .dismiss
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 72)
                }
            }
            .alert(
                incomingAlertTitle,
                isPresented:
                    incomingAlertIsPresented,
                presenting:
                    incomingLinkModel.decision
            ) { decision in
                incomingAlertActions(
                    for: decision
                )
            } message: { decision in
                Text(
                    incomingAlertMessage(
                        for: decision
                    )
                )
            }
            .confirmationDialog(
                "Choose GitLab Account",
                isPresented:
                    $showsAccountChoices,
                titleVisibility: .visible
            ) {
                accountChoiceActions
            } message: {
                Text(
                    "Choose the saved account that "
                        + "should open this link."
                )
            }
            .sheet(
                isPresented: $showsAddAccount,
                onDismiss:
                    addAccountSheetDidDismiss
            ) {
                GitLabOAuthSignInScene(
                    appSession: appSession
                )
                .presentationDragIndicator(
                    .visible
                )
            }
            .alert(
                "Couldn’t Switch Account",
                isPresented:
                    accountActionErrorIsPresented
            ) {
                Button("Try Again") {
                    accountActionError = nil
                    reevaluateIncomingLink()
                }

                Button(
                    "Cancel",
                    role: .cancel
                ) {
                    accountActionError = nil
                    incomingLinkModel.clear()
                }
            } message: {
                Text(accountActionError ?? "")
            }
            .alert(
                "Can’t Open Copied Link",
                isPresented:
                    unavailableClipboardLinkIsPresented
            ) {
                Button("OK") {
                    clipboardLinkSuggestionModel
                        .clearUnavailablePasteMessage()
                }
            } message: {
                Text(
                    clipboardLinkSuggestionModel
                        .unavailablePasteMessage
                        ?? ""
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch appSession.state {
        case .restoring:
            restoringView
        case .signedOut:
            GitLabOAuthSignInScene(
                appSession: appSession,
                authenticationMessage:
                    appSession.authenticationNotice?.description
            )
        case let .failed(error):
            GitLabOAuthSignInScene(
                appSession: appSession,
                authenticationMessage:
                    appSession.authenticationNotice?.description
                    ?? error.description
            )
        case let .signedIn(session):
            SignedInShellView(
                session: session,
                appSession: appSession,
                incomingLinkModel:
                    incomingLinkModel,
                todoNotificationManager:
                    todoNotificationManager
            )
            .id(GitLabAccountID(session: session))
        }
    }

    private var restoringView: some View {
        VStack(spacing: 16) {
            Image("GlabLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 22))
                .accessibilityHidden(true)
            ProgressView("Restoring GitLab session…")
        }
        .gitLabAccessibilityAnnouncement(
            "Restoring GitLab session"
        )
        .accessibilityIdentifier("app.restoringSession")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.glabCanvas)
    }

    private var accountContext:
        GitLabIncomingLinkAccountContext
    {
        GitLabIncomingLinkAccountContext(
            accountIDs:
                appSession.accounts.map(\.id),
            activeAccountID:
                appSession.activeAccountID
        )
    }

    private var todoNotificationRouteContext:
        GitLabTodoNotificationRouteContext
    {
        GitLabTodoNotificationRouteContext(
            pendingAccountKey:
                todoNotificationRouteModel
                    .pendingAccountKey,
            accountIDs:
                appSession.accounts.map(\.id),
            activeAccountID:
                appSession.activeAccountID
        )
    }

    private var clipboardSuggestionContext:
        GitLabClipboardSuggestionContext
    {
        GitLabClipboardSuggestionContext(
            isAppActive:
                scenePhase == .active,
            accountIDs:
                appSession.accounts.map(\.id)
        )
    }

    private var showsClipboardLinkSuggestion: Bool {
        guard case .signedIn = appSession.state else {
            return false
        }
        return clipboardLinkSuggestionModel
            .isSuggestionPresented
    }

    private var unavailableClipboardLinkIsPresented:
        Binding<Bool>
    {
        Binding {
            clipboardLinkSuggestionModel
                .unavailablePasteMessage
                != nil
        } set: { isPresented in
            if !isPresented {
                clipboardLinkSuggestionModel
                    .clearUnavailablePasteMessage()
            }
        }
    }

    private var incomingAlertIsPresented:
        Binding<Bool>
    {
        Binding {
            guard
                let decision =
                    incomingLinkModel.decision
            else {
                return false
            }

            return decision.showsAlert
        } set: { _ in }
    }

    private var incomingAlertTitle: String {
        guard
            let decision =
                incomingLinkModel.decision
        else {
            return "Open GitLab Link"
        }

        return switch decision {
        case .confirmSwitch:
            "Switch GitLab Account?"
        case .signedOut:
            "Sign In to Open Link"
        case .addAccount:
            "Add GitLab Account?"
        case .browserFallback:
            "Open in GitLab?"
        case .open, .chooseAccount, .rejected:
            "Open GitLab Link"
        }
    }

    @ViewBuilder
    private func incomingAlertActions(
        for decision: GitLabDeepLinkDecision
    ) -> some View {
        switch decision {
        case let .confirmSwitch(
            accountID,
            _,
            _
        ):
            Button("Switch Account") {
                switchAccount(to: accountID)
            }
            .accessibilityIdentifier(
                "deepLink.switchAccount"
            )

            cancelIncomingLinkButton
        case let .signedOut(sourceURL):
            Button("Continue to Sign In") {
                incomingLinkModel
                    .preserveForAccountTransition()
            }
            .accessibilityIdentifier(
                "deepLink.continueSignIn"
            )

            Button("Open in GitLab") {
                openInGitLab(sourceURL)
            }

            cancelIncomingLinkButton
        case let .addAccount(sourceURL):
            Button("Add Account") {
                beginAddingAccount()
            }
            .accessibilityIdentifier(
                "deepLink.addAccount"
            )

            Button("Open in GitLab") {
                openInGitLab(sourceURL)
            }

            cancelIncomingLinkButton
        case let .browserFallback(
            sourceURL
        ):
            Button("Open in GitLab") {
                openInGitLab(sourceURL)
            }
            .accessibilityIdentifier(
                "deepLink.openInGitLab"
            )

            cancelIncomingLinkButton
        case .open, .chooseAccount, .rejected:
            cancelIncomingLinkButton
        }
    }

    private var cancelIncomingLinkButton:
        some View
    {
        Button("Cancel", role: .cancel) {
            incomingLinkModel.clear()
        }
        .accessibilityIdentifier(
            "deepLink.cancel"
        )
    }

    @ViewBuilder
    private var accountChoiceActions:
        some View
    {
        if
            case let .chooseAccount(
                accountIDs,
                _,
                _
            ) = incomingLinkModel.decision
        {
            ForEach(
                matchingAccounts(
                    accountIDs
                )
            ) { account in
                Button(
                    accountChoiceLabel(
                        for: account
                    )
                ) {
                    switchAccount(
                        to: account.id
                    )
                }
                .accessibilityIdentifier(
                    "deepLink.account."
                        + "\(account.id.userID)"
                )
            }
        }

        Button("Cancel", role: .cancel) {
            incomingLinkModel.clear()
        }
    }

    private func incomingAlertMessage(
        for decision: GitLabDeepLinkDecision
    ) -> String {
        switch decision {
        case let .confirmSwitch(
            accountID,
            _,
            sourceURL
        ):
            let accountDescription =
                accountSummary(for: accountID)
                    .map {
                        "@\($0.user.username) on "
                            + instanceName(
                                for: $0.host
                            )
                    }
                    ?? instanceName(
                        for: accountID.host
                    )
            return
                "This link belongs to "
                + "\(accountDescription). Switch "
                + "accounts and open it?\n\n"
                + sourceURL.absoluteString
        case let .signedOut(sourceURL):
            return
                "Sign in to an account for "
                + "\(sourceURL.displayHost) to "
                + "open this link.\n\n"
                + sourceURL.absoluteString
        case let .addAccount(sourceURL):
            return
                "No saved account matches "
                + "\(sourceURL.displayHost). Add "
                + "one, or open this validated "
                + "link in GitLab.\n\n"
                + sourceURL.absoluteString
        case let .browserFallback(sourceURL):
            return
                "Glab can’t open this path "
                + "natively. You can open the "
                + "validated link in GitLab.\n\n"
                + sourceURL.absoluteString
        case .open, .chooseAccount, .rejected:
            return ""
        }
    }

    private var accountActionErrorIsPresented:
        Binding<Bool>
    {
        Binding {
            accountActionError != nil
        } set: { isPresented in
            if !isPresented {
                accountActionError = nil
            }
        }
    }

    private func accountContextDidChange(
        from previous:
            GitLabIncomingLinkAccountContext,
        to current:
            GitLabIncomingLinkAccountContext
    ) {
        if
            showsAddAccount,
            current.activeAccountID != nil,
            current.activeAccountID
                != addAccountBaseline
        {
            didCompleteAddAccount = true
            showsAddAccount = false
        }

        guard previous != current else {
            return
        }

        incomingLinkModel.reevaluate(
            accounts: current.accountIDs,
            activeAccountID:
                current.activeAccountID
        )
    }

    private func reevaluateIncomingLink() {
        incomingLinkModel.reevaluate(
            accounts: accountContext.accountIDs,
            activeAccountID:
                accountContext.activeAccountID
        )
    }

    private func handlePastedClipboardLinks(
        _ candidates:
            [GitLabClipboardLinkCandidate]
    ) {
        guard
            let candidate = candidates.first,
            case let .accepted(targetURL) =
                GitLabClipboardLinkClassifier
                    .classify(
                        candidate.url,
                        accounts:
                            accountContext
                                .accountIDs
                    )
        else {
            clipboardLinkSuggestionModel
                .didPasteUnavailableLink()
            return
        }

        clipboardLinkSuggestionModel
            .didAcceptPastedLink()
        _ = incomingLinkModel.receive(
            targetURL,
            accounts:
                accountContext.accountIDs,
            activeAccountID:
                accountContext.activeAccountID
        )
    }

    private func handleTodoNotificationRoute()
        async
    {
        guard
            let accountKey =
                todoNotificationRouteModel
                    .pendingAccountKey
        else {
            return
        }
        guard
            let account =
                appSession.accounts.first(
                    where: {
                        GitLabTodoNotificationManager
                            .accountKey(
                                for: $0.id
                            ) == accountKey
                    }
                )
        else {
            if case .restoring = appSession.state {
                return
            }
            todoNotificationRouteModel.clear()
            return
        }
        guard
            account.id
                != appSession.activeAccountID
        else {
            return
        }

        do {
            try await appSession.switchAccount(
                to: account.id
            )
        } catch {
            accountActionError =
                error.localizedDescription
            todoNotificationRouteModel.clear()
        }
    }

    private func switchAccount(
        to accountID: GitLabAccountID
    ) {
        incomingLinkModel
            .preserveForAccountTransition()

        Task {
            do {
                try await appSession
                    .switchAccount(
                        to: accountID
                    )
                reevaluateIncomingLink()
            } catch {
                accountActionError =
                    error.localizedDescription
            }
        }
    }

    private func beginAddingAccount() {
        addAccountBaseline =
            appSession.activeAccountID
        didCompleteAddAccount = false
        incomingLinkModel
            .preserveForAccountTransition()
        showsAddAccount = true
    }

    private func addAccountSheetDidDismiss() {
        if !didCompleteAddAccount {
            incomingLinkModel.clear()
        }

        addAccountBaseline = nil
        didCompleteAddAccount = false
    }

    private func openInGitLab(
        _ sourceURL: URL
    ) {
        incomingLinkModel.clear()
        openURL(sourceURL)
    }

    private func matchingAccounts(
        _ accountIDs: [GitLabAccountID]
    ) -> [GitLabAccountSummary] {
        let identifiers = Set(accountIDs)
        return appSession.accounts.filter {
            identifiers.contains($0.id)
        }
    }

    private func accountSummary(
        for accountID: GitLabAccountID
    ) -> GitLabAccountSummary? {
        appSession.accounts.first {
            $0.id == accountID
        }
    }

    private func accountChoiceLabel(
        for account: GitLabAccountSummary
    ) -> String {
        "@\(account.user.username) · "
            + instanceName(for: account.host)
    }

    private func instanceName(
        for host: GitLabHost
    ) -> String {
        let hostName =
            host.siteURL.host(
                percentEncoded: false
            )
            ?? host.siteURL.absoluteString
        let path = host.siteURL.path
        guard
            !path.isEmpty,
            path != "/"
        else {
            return hostName
        }

        return hostName + path
    }
}

#Preview("Restoring") {
    AppRootView(
        incomingLinkModel:
            GitLabIncomingLinkModel()
    )
        .environment(
            AppSession(
                credentialStore: InMemoryGitLabCredentialStore()
            )
        )
        .environment(
            GitLabTodoNotificationManager()
        )
        .environment(
            GitLabTodoNotificationRouteModel()
        )
}

private extension GitLabDeepLinkDecision {
    var showsAlert: Bool {
        switch self {
        case .confirmSwitch,
             .signedOut,
             .addAccount,
             .browserFallback:
            true
        case .open, .chooseAccount, .rejected:
            false
        }
    }

    var isAccountChoice: Bool {
        guard case .chooseAccount = self else {
            return false
        }
        return true
    }
}

private extension URL {
    var displayHost: String {
        host(percentEncoded: false)
            ?? absoluteString
    }
}
