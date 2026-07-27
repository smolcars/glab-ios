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
    private enum Field: Hashable {
        case instanceURL
        case applicationID
    }

    @Bindable var model: GitLabOAuthSignInModel
    let appSession: AppSession
    let authenticationMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    @State private var showsAccessTokenSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction

                    if let authenticationMessage {
                        authenticationNotice(authenticationMessage)
                    }

                    instanceSection

                    if !model.usesCustomInstance,
                       !model.isGitLabDotComConfigured
                    {
                        missingGitLabDotComConfiguration
                    }

                    if let failure = model.failure {
                        failureCallout(failure)
                    }

                    actions
                    setupHelp
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showsAccessTokenSignIn) {
                PersonalAccessTokenSignInScene(
                    appSession: appSession,
                    showsCancelButton: true
                )
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func authenticationNotice(
        _ message: String
    ) -> some View {
        Label {
            Text(message)
                .font(.callout)
        } icon: {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
        }
        .foregroundStyle(.orange)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.1),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityIdentifier("oauth.sessionNotice")
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: 54, height: 54)
                .background(
                    Color.orange.opacity(0.12),
                    in: .rect(cornerRadius: 15)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Glab")
                    .font(.title2.bold())

                Text(
                    "Continue in GitLab’s secure web page. Passwords, "
                        + "2FA, and SSO never enter Glab."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var instanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("GitLab instance", systemImage: "server.rack")
                .font(.headline)

            Picker("GitLab instance", selection: $model.usesCustomInstance) {
                Text("GitLab.com").tag(false)
                Text("Self-managed").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("oauth.instancePicker")

            if model.usesCustomInstance {
                Divider()

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
                        "This is a public app identifier from your GitLab "
                            + "administrator—not a secret or API key."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .transition(
                    .opacity.combined(with: .move(edge: .top))
                )
            } else {
                Text("gitlab.com")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 20)
        )
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.28),
            value: model.usesCustomInstance
        )
    }

    private var missingGitLabDotComConfiguration: some View {
        Label {
            Text(
                "GitLab.com web sign-in is not configured in this build. "
                    + "You can still use an access token."
            )
            .font(.callout)
        } icon: {
            Image(systemName: "wrench.and.screwdriver.fill")
        }
        .foregroundStyle(.orange)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.1),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityIdentifier("oauth.missingConfiguration")
    }

    private func failureCallout(
        _ failure: GitLabOAuthSignInFailure
    ) -> some View {
        Label {
            Text(failure.description)
                .font(.callout)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.red.opacity(0.1),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityIdentifier("oauth.error")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                focusedField = nil
                Task {
                    await model.signIn()
                }
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
            .accessibilityIdentifier("oauth.submit")

            Button {
                focusedField = nil
                showsAccessTokenSignIn = true
            } label: {
                Label(
                    "Use access token / API key",
                    systemImage: "key.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 30)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityIdentifier("oauth.accessToken")
        }
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

        focusedField = nil
        Task {
            await model.signIn()
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
