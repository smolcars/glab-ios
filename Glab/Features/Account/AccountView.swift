import SwiftUI

struct AccountView: View {
    let session: GitLabStoredSession
    let appSession: AppSession

    @Environment(\.dismiss) private var dismiss
    @State private var showsAddAccount = false
    @State private var pendingRemoval:
        GitLabAccountSummary?
    @State private var isPerformingAccountAction = false
    @State private var accountActionError: String?

    var body: some View {
        NavigationStack {
            List {
                profileSection
                accountsSection
                accountSection
                privacySection

                if session.apiAccess == .readOnly {
                    readOnlySection
                }

                if let accountActionError {
                    errorSection(accountActionError)
                }

                appFooter
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(isPerformingAccountAction)
                    .accessibilityIdentifier("account.doneButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                removeCurrentAccountButton
            }
            .alert(
                removalTitle,
                isPresented: showsRemovalConfirmation,
                presenting: pendingRemoval
            ) {
                account in
                Button(
                    removalButtonTitle,
                    role: .destructive
                ) {
                    removeAccount(account)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                account in
                Text(removalMessage(for: account))
            }
            .sheet(isPresented: $showsAddAccount) {
                GitLabOAuthSignInScene(
                    appSession: appSession
                )
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                GitLabUserAvatar(
                    user: session.user,
                    size: 68
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.user.displayName)
                        .font(.title3.bold())

                    Text("@\(session.user.username)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private var accountsSection: some View {
        Section("Accounts") {
            ForEach(appSession.accounts) { account in
                Button {
                    switchAccount(account)
                } label: {
                    accountRow(account)
                }
                .buttonStyle(.plain)
                .disabled(isPerformingAccountAction)
                .swipeActions {
                    Button(
                        "Remove",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        pendingRemoval = account
                    }
                }
                .accessibilityIdentifier(
                    "account.row.\(account.id.userID)"
                )
            }

            Button {
                showsAddAccount = true
            } label: {
                Label(
                    "Add GitLab Account",
                    systemImage: "person.crop.circle.badge.plus"
                )
            }
            .disabled(isPerformingAccountAction)
            .accessibilityIdentifier("account.addButton")
        }
    }

    private func accountRow(
        _ account: GitLabAccountSummary
    ) -> some View {
        HStack(spacing: 12) {
            GitLabUserAvatar(
                user: account.user,
                size: 42
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.user.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    "@\(account.user.username) · "
                        + instanceName(for: account.host)
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if account.id == appSession.activeAccountID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Current account")
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }

    private var accountSection: some View {
        Section("GitLab account") {
            LabeledContent("Host", value: instanceName)
            LabeledContent("Authentication", value: authenticationMethod)
            LabeledContent("API access", value: apiAccessDescription)
        }
    }

    private var readOnlySection: some View {
        Section {
            Label {
                Text(
                    "This token can browse GitLab, but actions such as "
                        + "completing Todos will be disabled."
                )
            } icon: {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            NavigationLink {
                GitLabPrivacyAndAccessView(
                    presentation:
                        GitLabPrivacyAndAccessPresentation(
                            session: session
                        )
                )
            } label: {
                Label(
                    "Privacy & API access",
                    systemImage: "hand.raised.fill"
                )
            }
            .accessibilityIdentifier(
                "account.privacyAndAccess"
            )
        }
    }

    private func errorSection(
        _ message: String
    ) -> some View {
        Section {
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("account.error")
        }
    }

    private var appFooter: some View {
        Section {
            GlabAppFooter()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var removeCurrentAccountButton: some View {
        Button(role: .destructive) {
            pendingRemoval = currentAccount
        } label: {
            HStack(spacing: 9) {
                if isPerformingAccountAction {
                    ProgressView()
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }

                Text(
                    isPerformingAccountAction
                        ? "Removing account…"
                        : currentAccountRemovalTitle
                )
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(.red)
        .disabled(
            isPerformingAccountAction
                || currentAccount == nil
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier("account.signOutButton")
    }

    private var instanceName: String {
        instanceName(for: session.host)
    }

    private var authenticationMethod: String {
        switch session.credentialKind {
        case .oauth:
            "OAuth"
        case .personalAccessToken:
            "Personal access token"
        }
    }

    private var apiAccessDescription: String {
        switch session.apiAccess {
        case .readOnly:
            "Read-only"
        case .readWrite:
            "Read and write"
        }
    }

    private var currentAccount:
        GitLabAccountSummary?
    {
        appSession.accounts.first {
            $0.id == GitLabAccountID(session: session)
        }
    }

    private var currentAccountRemovalTitle: String {
        appSession.accounts.count == 1
            ? "Sign Out"
            : "Remove Current Account"
    }

    private var showsRemovalConfirmation:
        Binding<Bool>
    {
        Binding {
            pendingRemoval != nil
        } set: { isPresented in
            if !isPresented {
                pendingRemoval = nil
            }
        }
    }

    private var removalTitle: String {
        pendingRemoval == nil
            ? "Remove account?"
            : removalButtonTitle + "?"
    }

    private var removalButtonTitle: String {
        appSession.accounts.count == 1
            ? "Sign Out"
            : "Remove Account"
    }

    private func removalMessage(
        for account: GitLabAccountSummary
    ) -> String {
        "This removes @\(account.user.username) on "
            + "\(instanceName(for: account.host)) and its credentials "
            + "from this device."
    }

    private func instanceName(
        for host: GitLabHost
    ) -> String {
        host.siteURL.host(percentEncoded: false)
            ?? host.siteURL.absoluteString
    }

    private func switchAccount(
        _ account: GitLabAccountSummary
    ) {
        guard
            account.id != appSession.activeAccountID,
            !isPerformingAccountAction
        else {
            return
        }

        accountActionError = nil
        isPerformingAccountAction = true

        Task {
            do {
                try await appSession.switchAccount(
                    to: account.id
                )
                dismiss()
            } catch {
                accountActionError =
                    error.localizedDescription
                isPerformingAccountAction = false
            }
        }
    }

    private func removeAccount(
        _ account: GitLabAccountSummary
    ) {
        accountActionError = nil
        isPerformingAccountAction = true

        Task {
            do {
                try await appSession.removeAccount(
                    account.id
                )
                pendingRemoval = nil
                isPerformingAccountAction = false
            } catch {
                accountActionError =
                    error.localizedDescription
                isPerformingAccountAction = false
            }
        }
    }
}

struct GitLabUserAvatar: View {
    let user: GitLabUserSummary
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL = user.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(Color.orange.opacity(0.12))
        .clipShape(.circle)
        .overlay {
            Circle()
                .strokeBorder(.separator.opacity(0.35))
        }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(user.avatarInitial)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
