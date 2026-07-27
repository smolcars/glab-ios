import SwiftUI

struct AccountView: View {
    let session: GitLabStoredSession
    let appSession: AppSession

    @Environment(\.dismiss) private var dismiss
    @State private var showsSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var signOutError: String?

    var body: some View {
        NavigationStack {
            List {
                profileSection
                accountSection

                if session.apiAccess == .readOnly {
                    readOnlySection
                }

                if let signOutError {
                    errorSection(signOutError)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(isSigningOut)
                    .accessibilityIdentifier("account.doneButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                signOutButton
            }
            .confirmationDialog(
                "Sign out of Glab?",
                isPresented: $showsSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    performSignOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This removes the account and its credentials from "
                        + "this device."
                )
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

    private var signOutButton: some View {
        Button(role: .destructive) {
            showsSignOutConfirmation = true
        } label: {
            HStack(spacing: 9) {
                if isSigningOut {
                    ProgressView()
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }

                Text(isSigningOut ? "Signing out…" : "Sign Out")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(.red)
        .disabled(isSigningOut)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier("account.signOutButton")
    }

    private var instanceName: String {
        session.host.siteURL.host(percentEncoded: false)
            ?? session.host.siteURL.absoluteString
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

    private func performSignOut() {
        signOutError = nil
        isSigningOut = true

        Task {
            do {
                try await appSession.signOut()
            } catch {
                signOutError = error.localizedDescription
                isSigningOut = false
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
