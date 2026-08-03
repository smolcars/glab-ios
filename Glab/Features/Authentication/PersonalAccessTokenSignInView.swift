import SwiftUI

struct PersonalAccessTokenSignInScene: View {
    @State private var model: PersonalAccessTokenSignInModel
    private let showsCancelButton: Bool

    init(
        appSession: AppSession,
        showsCancelButton: Bool = false
    ) {
        let authenticator = GitLabPersonalAccessTokenAuthenticator(
            transport: URLSessionGitLabHTTPTransport()
        )
        self.showsCancelButton = showsCancelButton
        _model = State(
            initialValue: PersonalAccessTokenSignInModel(
                authenticator: authenticator,
                appSession: appSession
            )
        )
    }

    var body: some View {
        PersonalAccessTokenSignInView(
            model: model,
            showsCancelButton: showsCancelButton
        )
    }
}

struct PersonalAccessTokenSignInView: View {
    private enum Field: Hashable {
        case instanceURL
        case token
    }

    @Bindable var model: PersonalAccessTokenSignInModel
    let showsCancelButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?
    @State private var signInTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    instanceCard
                    tokenCard

                    if let failure = model.failure {
                        failureCallout(failure)
                    }

                    signInButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color.glabCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Sign in with a token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if showsCancelButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            cancelSignIn()
                            dismiss()
                        }
                    }
                }
            }
        }
        .onDisappear {
            cancelSignIn()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.glabBrandWarm)
                .accessibilityHidden(true)

            Text("Connect your GitLab account")
                .font(.glabTitle2.bold())

            Text(
                "Use a personal access token when web sign-in is unavailable "
                    + "or your GitLab administrator has not registered Glab."
            )
            .font(.glabBody)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        }
    }

    private var instanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("GitLab instance", systemImage: "server.rack")
                .font(.glabHeadline)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    instancePicker
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)
                } else {
                    instancePicker
                        .pickerStyle(.segmented)
                }
            }

            if model.usesCustomInstance {
                Divider()

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
                    focusedField = .token
                }
                .accessibilityLabel("Self-managed GitLab URL")
                .accessibilityIdentifier("signIn.instanceURL")

                Text("HTTPS with a system-trusted certificate is required.")
                    .font(.glabFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            } else {
                Text("gitlab.com")
                    .font(.glabSubheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .signInCard()
    }

    private var instancePicker: some View {
        Picker(
            "Instance",
            selection: $model.usesCustomInstance
        ) {
            Text("GitLab.com").tag(false)
            Text("Self-managed").tag(true)
        }
        .accessibilityIdentifier(
            "signIn.instancePicker"
        )
    }

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Access token / API key", systemImage: "key.fill")
                .font(.glabHeadline)

            SecureField("Personal access token", text: $model.token)
                .focused($focusedField, equals: .token)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .privacySensitive()
                .onSubmit {
                    submitIfPossible()
                }
                .accessibilityIdentifier("signIn.token")

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                scopeRow(
                    scope: "api",
                    detail: "Full access, including completing Todos",
                    symbol: "checkmark.shield.fill",
                    color: .green
                )
                scopeRow(
                    scope: "read_api",
                    detail: "Browse-only; changes are disabled",
                    symbol: "eye.fill",
                    color: .secondary
                )
            }

            if let setupURL = model.personalAccessTokenSetupURL {
                Link(destination: setupURL) {
                    Label(
                        "Create a personal access token",
                        systemImage: "arrow.up.right"
                    )
                    .font(.glabCallout.weight(.semibold))
                }
                .accessibilityIdentifier("signIn.createToken")
            } else if model.usesCustomInstance {
                Text("Enter a valid HTTPS instance to create a token there.")
                    .font(.glabFootnote)
                    .foregroundStyle(.secondary)
            }
        }
        .signInCard()
    }

    private func scopeRow(
        scope: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(scope)
                    .font(.callout.monospaced().weight(.semibold))
                Text(detail)
                    .font(.glabFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
        }
    }

    private func failureCallout(
        _ failure: PersonalAccessTokenSignInFailure
    ) -> some View {
        Label {
            Text(failure.description)
                .font(.glabCallout)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
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
        .accessibilityIdentifier("signIn.error")
    }

    private var signInButton: some View {
        Button {
            startSignIn()
        } label: {
            ZStack {
                Text("Connect GitLab")
                    .opacity(model.isSubmitting ? 0 : 1)

                if model.isSubmitting {
                    ProgressView()
                }
            }
            .font(.glabHeadline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Color.glabAccent)
        .disabled(!model.canSubmit)
        .accessibilityLabel(
            model.isSubmitting ? "Connecting to GitLab" : "Connect GitLab"
        )
        .accessibilityIdentifier("signIn.submit")
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

private extension View {
    func signInCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.glabRaisedSurface,
                in: .rect(cornerRadius: 20)
            )
    }
}

#Preview {
    PersonalAccessTokenSignInScene(
        appSession: AppSession(
            credentialStore: InMemoryGitLabCredentialStore()
        )
    )
}
