import SwiftUI

struct GitLabOAuthSignInScene: View {
    @State private var model: GitLabOAuthSignInModel
    private let appSession: AppSession
    private let authenticationMessage: String?

    init(
        appSession: AppSession,
        authenticationMessage: String? = nil
    ) {
        let transport = URLSessionGitLabHTTPTransport()
        let tokenClient = GitLabOAuthTokenClient(transport: transport)
        let authenticator = GitLabOAuthAuthenticator(
            pkceGenerator: GitLabOAuthPKCEGenerator(
                randomBytesProvider: SystemGitLabOAuthRandomBytesProvider()
            ),
            tokenExchanger: tokenClient,
            transport: transport,
            webAuthenticator:
                ASWebAuthenticationSessionGitLabOAuthAuthenticator()
        )

        self.appSession = appSession
        self.authenticationMessage = authenticationMessage
        _model = State(
            initialValue: GitLabOAuthSignInModel(
                authenticator: authenticator,
                appSession: appSession,
                applicationIDStore:
                    UserDefaultsGitLabOAuthApplicationIDStore(),
                gitLabDotComApplicationID:
                    GitLabOAuthRuntimeConfiguration
                        .gitLabDotComApplicationID()
            )
        )
    }

    var body: some View {
        GitLabOAuthSignInView(
            model: model,
            appSession: appSession,
            authenticationMessage: authenticationMessage
        )
    }
}

struct GitLabOAuthSignInView: View {
    @Bindable var model: GitLabOAuthSignInModel
    let appSession: AppSession
    let authenticationMessage: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsAccessTokenSignIn = false
    @State private var showsPrivacyAndAccess = false
    @State private var showsSelfManagedSignIn = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        brand

                        Spacer(
                            minLength:
                                dynamicTypeSize.isAccessibilitySize
                                    ? 20
                                    : 24
                        )

                        VStack(spacing: 18) {
                            if let authenticationMessage {
                                authenticationNotice(
                                    authenticationMessage
                                )
                            }

                            if let failure = model.failure {
                                failureCallout(failure)
                            }

                            actions
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: proxy.size.height,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        dynamicTypeSize.isAccessibilitySize ? 20 : 24
                    )
                    .padding(
                        .top,
                        dynamicTypeSize.isAccessibilitySize ? 12 : 24
                    )
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsSelfManagedSignIn) {
                SelfManagedGitLabOAuthView(model: model)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsAccessTokenSignIn) {
                PersonalAccessTokenSignInScene(
                    appSession: appSession,
                    showsCancelButton: true
                )
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsPrivacyAndAccess) {
                GitLabPrivacyAndAccessSheet(
                    presentation: .oauthSignIn
                )
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var brand: some View {
        VStack(spacing: 8) {
            Image("GitLabLogo")
                .resizable()
                .scaledToFit()
                .frame(
                    width:
                        dynamicTypeSize.isAccessibilitySize
                            ? 120
                            : 220,
                    height:
                        dynamicTypeSize.isAccessibilitySize
                            ? 120
                            : 220
                )
                .accessibilityHidden(true)

            Text("Glab")
                .font(.largeTitle.bold())

            Text("An unofficial GitLab client for iPhone")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Independent and not affiliated with GitLab Inc.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button {
                model.usesCustomInstance = false
                Task {
                    await model.signIn()
                }
            } label: {
                signInActionLabel(
                    title:
                        model.isSubmitting
                            ? "Opening GitLab…"
                            : "Sign in to GitLab.com",
                    systemImage: "safari.fill",
                    showsProgress: model.isSubmitting
                )
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.orange)
            .disabled(
                !model.isGitLabDotComConfigured
                    || model.isSubmitting
            )
            .accessibilityIdentifier("oauth.submit")

            Text(gitLabDotComActionDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(
                    model.isGitLabDotComConfigured
                        ? "oauth.securityDetail"
                        : "oauth.missingConfiguration"
                )

            Button {
                showsPrivacyAndAccess = true
            } label: {
                Label(
                    "Privacy & API access",
                    systemImage: "hand.raised.fill"
                )
                .font(.callout.weight(.semibold))
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier(
                "oauth.privacyAndAccess"
            )

            Button {
                model.usesCustomInstance = true
                showsSelfManagedSignIn = true
            } label: {
                signInActionLabel(
                    title: "Sign in to self-managed GitLab",
                    systemImage: "building.2.fill"
                )
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("oauth.selfManaged")

            Button {
                showsAccessTokenSignIn = true
            } label: {
                fallbackActionLabel
            }
            .buttonStyle(.plain)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("oauth.accessToken")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func signInActionLabel(
        title: String,
        systemImage: String,
        showsProgress: Bool = false
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    actionIcon(
                        systemImage: systemImage,
                        showsProgress: showsProgress
                    )
                    Text(title)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 9) {
                    actionIcon(
                        systemImage: systemImage,
                        showsProgress: showsProgress
                    )
                    Text(title)
                }
            }
        }
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private func actionIcon(
        systemImage: String,
        showsProgress: Bool
    ) -> some View {
        if showsProgress {
            ProgressView()
        } else {
            Image(systemName: systemImage)
        }
    }

    @ViewBuilder
    private var fallbackActionLabel: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                    Text("Use access token / API key")
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            } else {
                Label(
                    "Use access token / API key",
                    systemImage: "key.fill"
                )
            }
        }
        .font(.callout.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
    }

    private var gitLabDotComActionDetail: String {
        if model.isGitLabDotComConfigured {
            return "Passwords, 2FA, and SSO stay on GitLab’s secure web page."
        }

        return "GitLab.com web sign-in is not configured in this build."
    }

    private func authenticationNotice(
        _ message: String
    ) -> some View {
        GitLabOAuthCallout(
            message: message,
            systemImage:
                "person.crop.circle.badge.exclamationmark",
            color: .orange
        )
        .accessibilityIdentifier("oauth.sessionNotice")
    }

    private func failureCallout(
        _ failure: GitLabOAuthSignInFailure
    ) -> some View {
        GitLabOAuthCallout(
            message: failure.description,
            systemImage: "exclamationmark.triangle.fill",
            color: .red
        )
        .accessibilityIdentifier("oauth.error")
    }
}

private struct SelfManagedGitLabOAuthView: View {
    private enum Field: Hashable {
        case instanceURL
        case applicationID
    }

    @Bindable var model: GitLabOAuthSignInModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var signInTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    configuration

                    if let failure = model.failure {
                        GitLabOAuthCallout(
                            message: failure.description,
                            systemImage:
                                "exclamationmark.triangle.fill",
                            color: .red
                        )
                        .accessibilityIdentifier("oauth.error")
                    }

                    signInButton
                    setupHelp
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Self-managed GitLab")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelSignIn()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            model.usesCustomInstance = true
        }
        .onDisappear {
            cancelSignIn()
        }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 16) {
            Image("GitLabLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text(
                "Use your instance’s normal web sign-in. Passwords, "
                    + "2FA, and SSO never enter Glab."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("GitLab instance", systemImage: "server.rack")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Instance URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "gitlab.example.com",
                    text: $model.customInstanceURL
                )
                .focused($focusedField, equals: .instanceURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .applicationID
                }
                .accessibilityLabel("Self-managed GitLab URL")
                .accessibilityIdentifier("oauth.instanceURL")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("OAuth Application ID")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Application ID",
                    text: $model.customApplicationID
                )
                .focused($focusedField, equals: .applicationID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit {
                    submitIfPossible()
                }
                .accessibilityIdentifier("oauth.applicationID")

                Text(
                    "A public identifier from your GitLab "
                        + "administrator—not a secret or API key."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 20)
        )
    }

    private var signInButton: some View {
        Button {
            startSignIn()
        } label: {
            HStack(spacing: 9) {
                if model.isSubmitting {
                    ProgressView()
                } else {
                    Image(systemName: "safari.fill")
                }

                Text(
                    model.isSubmitting
                        ? "Opening GitLab…"
                        : "Continue in GitLab"
                )
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(.orange)
        .disabled(!model.canSubmit)
        .accessibilityIdentifier("oauth.selfManagedSubmit")
    }

    private var setupHelp: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Register Glab as a public, non-confidential OAuth "
                        + "application with the api scope."
                )

                LabeledContent("Redirect URI") {
                    Text(model.redirectURI)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                Text(
                    "An administrator can register one shared application "
                        + "for everyone on a self-managed instance."
                )
                .foregroundStyle(.secondary)

                if let setupURL = model.applicationSetupURL {
                    Link(destination: setupURL) {
                        Label(
                            "Open GitLab OAuth applications",
                            systemImage: "arrow.up.right"
                        )
                        .font(.callout.weight(.semibold))
                    }
                }
            }
            .font(.callout)
            .padding(.top, 12)
        } label: {
            Label(
                "Self-managed setup",
                systemImage: "questionmark.circle"
            )
            .font(.headline)
        }
        .padding(.horizontal, 2)
        .accessibilityIdentifier("oauth.setupHelp")
    }

    private func submitIfPossible() {
        guard model.canSubmit else {
            return
        }

        startSignIn()
    }

    private func startSignIn() {
        focusedField = nil
        signInTask?.cancel()
        signInTask = Task {
            await model.signIn()
            signInTask = nil
        }
    }

    private func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
    }
}

private struct GitLabOAuthCallout: View {
    let message: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(color)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            color.opacity(0.1),
            in: .rect(cornerRadius: 16)
        )
    }
}

#Preview {
    GitLabOAuthSignInScene(
        appSession: AppSession(
            credentialStore: InMemoryGitLabCredentialStore()
        )
    )
}
