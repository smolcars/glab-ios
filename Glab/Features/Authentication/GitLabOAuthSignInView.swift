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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsAccessTokenSignIn = false
    @State private var showsPrivacyAndAccess = false
    @State private var showsSelfManagedSignIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            brand

                            VStack(spacing: 18) {
                                if let authenticationMessage {
                                    authenticationNotice(
                                        authenticationMessage
                                    )
                                }

                                if let failure = model.failure {
                                    failureCallout(failure)
                                }

                                signInSection
                            }
                            .padding(
                                .top,
                                dynamicTypeSize.isAccessibilitySize
                                    ? 28
                                    : 40
                            )

                            Spacer(minLength: 28)

                            signInFooter
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: proxy.size.height,
                            alignment: .top
                        )
                        .padding(
                            .horizontal,
                            dynamicTypeSize.isAccessibilitySize
                                ? 20
                                : 24
                        )
                        .padding(.top, 20)
                        .padding(.bottom, 14)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
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

    private var backdrop: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            RadialGradient(
                colors: [
                    Color.orange.opacity(
                        colorScheme == .dark ? 0.22 : 0.13
                    ),
                    .clear,
                ],
                center: UnitPoint(x: 0.02, y: 0.04),
                startRadius: 0,
                endRadius: 300
            )

            RadialGradient(
                colors: [
                    Color(
                        red: 0.46,
                        green: 0.20,
                        blue: 0.58
                    )
                    .opacity(colorScheme == .dark ? 0.20 : 0.10),
                    .clear,
                ],
                center: UnitPoint(x: 1.0, y: 0.62),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var brand: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                brandLogo
                brandCopy
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 16) {
                brandLogo
                brandCopy
                Spacer(minLength: 0)
            }
        }
    }

    private var brandLogo: some View {
        Image("GlabLogo")
            .resizable()
            .scaledToFit()
            .frame(
                width: dynamicTypeSize.isAccessibilitySize ? 72 : 82,
                height: dynamicTypeSize.isAccessibilitySize ? 72 : 82
            )
            .clipShape(.rect(cornerRadius: 20))
            .shadow(
                color: .orange.opacity(
                    colorScheme == .dark ? 0.22 : 0.12
                ),
                radius: 20,
                y: 8
            )
            .accessibilityHidden(true)
    }

    private var brandCopy: some View {
        VStack(
            alignment:
                dynamicTypeSize.isAccessibilitySize
                    ? .center
                    : .leading,
            spacing: 3
        ) {
            Text("Glab")
                .font(.largeTitle.bold())

            Text("Your GitLab, in your pocket.")
                .font(.headline)

            Text("Independent client for iPhone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in")
                    .font(.title2.bold())

                Text("Choose where your GitLab account lives.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            actionButtons

            privacyAndSecurityButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                actionButtonStack
            }
        } else {
            actionButtonStack
        }
    }

    private var actionButtonStack: some View {
        VStack(spacing: 12) {
            gitLabDotComButton
            selfManagedButton
            accessTokenButton
        }
        .frame(maxWidth: .infinity)
    }

    private var gitLabDotComButton: some View {
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
                        : "Continue with GitLab.com",
                systemImage: "safari.fill",
                showsProgress: model.isSubmitting
            )
        }
        .oauthPrimaryButtonStyle()
        .controlSize(.large)
        .disabled(
            !model.isGitLabDotComConfigured
                || model.isSubmitting
        )
        .accessibilityIdentifier("oauth.submit")
    }

    private var selfManagedButton: some View {
        Button {
            model.usesCustomInstance = true
            showsSelfManagedSignIn = true
        } label: {
            signInActionLabel(
                title: "Self-managed GitLab",
                subtitle: "Use your instance’s web sign-in",
                systemImage: "building.2.fill",
                usesAccentColor: true
            )
        }
        .oauthSecondaryButtonStyle()
        .controlSize(.large)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("oauth.selfManaged")
    }

    private var accessTokenButton: some View {
        Button {
            showsAccessTokenSignIn = true
        } label: {
            signInActionLabel(
                title: "Personal access token",
                subtitle: "Use an existing API token",
                systemImage: "key.fill",
                usesAccentColor: true
            )
        }
        .oauthSecondaryButtonStyle()
        .controlSize(.large)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("oauth.accessToken")
    }

    private var privacyAndSecurityButton: some View {
        Button {
            showsPrivacyAndAccess = true
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "lock.shield.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(gitLabDotComActionDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Privacy & API access")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityIdentifier("oauth.privacyAndAccess")
    }

    private var signInFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Made with ❤️ by Nitesh · v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: repositoryURL) {
                    Image("GitHubMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .frame(width: 28, height: 28)
                }
                .oauthFooterLinkStyle()
                .foregroundStyle(.primary)
                .accessibilityLabel("View Glab on GitHub")
                .accessibilityIdentifier("app.githubLink")
            }

            Text("Independent and not affiliated with GitLab Inc.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func signInActionLabel(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        showsProgress: Bool = false,
        usesAccentColor: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            actionIcon(
                systemImage: systemImage,
                showsProgress: showsProgress
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(
                usesAccentColor ? Color.orange : Color.white
            )
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(
                        usesAccentColor ? Color.primary : Color.white
                    )

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if !showsProgress {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(
                        usesAccentColor
                            ? Color.secondary
                            : Color.white.opacity(0.75)
                    )
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .frame(
            maxWidth: .infinity,
            minHeight: 44,
            alignment: .leading
        )
        .contentShape(.rect)
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

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/smolcars/glab-ios")!
    }

    private var gitLabDotComActionDetail: String {
        if model.isGitLabDotComConfigured {
            return "Passwords, 2FA, and SSO stay with GitLab."
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
            .navigationBarTitleDisplayMode(.inline)
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
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
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

private extension View {
    @ViewBuilder
    func oauthPrimaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(.orange)
        } else {
            buttonStyle(.borderedProminent)
                .tint(.orange)
        }
    }

    @ViewBuilder
    func oauthSecondaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func oauthFooterLinkStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
                .controlSize(.small)
        } else {
            buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

#Preview {
    GitLabOAuthSignInScene(
        appSession: AppSession(
            credentialStore: InMemoryGitLabCredentialStore()
        )
    )
}
