import SwiftUI
import UIKit

struct GitLabUserProfileView: View {
    let appSession: AppSession

    @State private var model:
        GitLabUserProfileModel
    @State private var showsGPGKeys = false

    init(
        route: GitLabUserRoute,
        service: any GitLabUserServing,
        session: GitLabStoredSession,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabUserProfileModel(
                    route: route,
                    accountID: accountID,
                    apiAccess:
                        session.apiAccess,
                    currentUserID:
                        session.user.id,
                    service: service,
                    isAccountCurrent: {
                        appSession.activeAccountID
                            == accountID
                    }
                )
        )
    }

    var body: some View {
        content
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                profileMenu
            }
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
            .sheet(isPresented: $showsGPGKeys) {
                GitLabUserGPGKeysView(
                    model: model
                )
                .presentationDetents([
                    .medium,
                    .large,
                ])
                .presentationDragIndicator(
                    .visible
                )
            }
            .alert(
                "Couldn’t Update Follow",
                isPresented:
                    followFailureIsPresented
            ) {
                Button("OK", role: .cancel) {
                    model.dismissFollowFailure()
                }
            } message: {
                Text(
                    model.followFailure?
                        .localizedDescription
                        ?? ""
                )
            }
            .accessibilityIdentifier(
                "userProfile.screen"
            )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                loadingHeader
                    .padding(20)
            }
            .background(Color.glabCanvas)
        case let .failed(error):
            GitLabContentStateScrollView {
                GitLabRetryStateView(
                    error: error
                ) {
                    Task {
                        await model.refresh()
                        await
                            handleAuthenticationFailure()
                    }
                }
            }
        case let .loaded(profile):
            profileContent(profile)
        }
    }

    private var loadingHeader: some View {
        VStack(spacing: 20) {
            GitLabUserProfileIdentityHeader(
                summary: model.route.summary,
                pronouns: nil,
                status: nil,
                isBot: false,
                isLocked: false
            )

            ProgressView("Loading profile")
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
    }

    private func profileContent(
        _ profile: GitLabUserProfile
    ) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 22
            ) {
                GitLabUserProfileIdentityHeader(
                    summary: profile.summary,
                    pronouns: profile.pronouns,
                    status: model.status,
                    isBot: profile.isBot,
                    isLocked: profile.isLocked
                )

                if let bio = profile.bio {
                    Text(bio)
                        .font(.glabBody)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .textSelection(.enabled)
                }

                followerSummary(profile)

                actionControls(profile)

                if let refreshError = model.refreshError {
                    GitLabInlineRetryRow(
                        title: "Profile refresh failed",
                        error: refreshError,
                        accessibilityIdentifier:
                            "userProfile.refreshError"
                    ) {
                        Task {
                            await model.refresh()
                            await
                                handleAuthenticationFailure()
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                let information = informationItems(
                    for: profile
                )
                if !information.isEmpty {
                    GitLabUserProfileSection(
                        title: "Info"
                    ) {
                        GitLabUserProfileRows(
                            items: information
                        )
                    }
                }

                if !profile.contacts.isEmpty {
                    GitLabUserProfileSection(
                        title: "Contact"
                    ) {
                        GitLabUserContactRows(
                            contacts:
                                profile.contacts
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Color.glabCanvas)
        .refreshable {
            await model.refresh()
            await handleAuthenticationFailure()
        }
    }

    @ViewBuilder
    private func followerSummary(
        _ profile: GitLabUserProfile
    ) -> some View {
        if
            profile.followers != nil
                || profile.following != nil
        {
            HStack(spacing: 7) {
                if let followers = profile.followers {
                    countLabel(
                        followers,
                        singular: "follower",
                        plural: "followers"
                    )
                }

                if
                    profile.followers != nil,
                    profile.following != nil
                {
                    Text("·")
                        .foregroundStyle(.tertiary)
                }

                if let following = profile.following {
                    countLabel(
                        following,
                        singular: "following",
                        plural: "following"
                    )
                }
            }
            .font(.glabSubheadline)
            .foregroundStyle(.secondary)
            .accessibilityElement(
                children: .combine
            )
        }
    }

    private func countLabel(
        _ count: Int,
        singular: String,
        plural: String
    ) -> some View {
        HStack(spacing: 4) {
            Text(count.formatted())
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(count == 1 ? singular : plural)
        }
    }

    private func actionControls(
        _ profile: GitLabUserProfile
    ) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                followControl(profile)
                gpgKeyControl
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func followControl(
        _ profile: GitLabUserProfile
    ) -> some View {
        if
            !model.isCurrentUser,
            let isFollowed = profile.isFollowed
        {
            if isFollowed {
                followButton(
                    title: "Following",
                    systemImage:
                        model.apiAccess.canWrite
                        ? "checkmark"
                        : "lock.fill"
                )
                .buttonStyle(.glass)
            } else {
                followButton(
                    title: "Follow",
                    systemImage:
                        model.apiAccess.canWrite
                        ? "person.badge.plus"
                        : "lock.fill"
                )
                .buttonStyle(.glassProminent)
            }
        }
    }

    private func followButton(
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            Task {
                await model.toggleFollow()
                await handleAuthenticationFailure()
            }
        } label: {
            HStack(spacing: 8) {
                if model.isMutatingFollow {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.glabSubheadline.weight(.semibold))
            .padding(.horizontal, 4)
        }
        .buttonBorderShape(.capsule)
        .disabled(!model.canToggleFollow)
        .accessibilityHint(
            model.apiAccess.canWrite
                ? "Updates this profile on GitLab."
                : "GitLab API write access is required."
        )
        .accessibilityIdentifier(
            "userProfile.followButton"
        )
    }

    private var gpgKeyControl: some View {
        Button {
            showsGPGKeys = true
        } label: {
            Group {
                if case .loading = model.gpgKeysState {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "key.horizontal")
                }
            }
            .font(.glabBody.weight(.semibold))
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .contentShape(.circle)
        .accessibilityLabel(gpgKeyLabel)
        .accessibilityHint(
            "Shows this user’s public GPG keys."
        )
        .accessibilityIdentifier(
            "userProfile.gpgKeysButton"
        )
    }

    private var gpgKeyLabel: String {
        if case let .loaded(keys) = model.gpgKeysState {
            return "GPG keys, \(keys.count)"
        }
        return "GPG keys"
    }

    @ToolbarContentBuilder
    private var profileMenu: some ToolbarContent {
        if let url = model.profile?.safeWebURL {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: url,
                        subject: Text(
                            model.profile?
                                .displayName
                                ?? "GitLab profile"
                        )
                    ) {
                        Label(
                            "Share Profile",
                            systemImage: "square.and.arrow.up"
                        )
                    }

                    Button(
                        "Copy Profile Link",
                        systemImage: "doc.on.doc"
                    ) {
                        UIPasteboard.general.url = url
                    }

                    Link(destination: url) {
                        Label(
                            "Open in GitLab",
                            systemImage: "safari"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Profile actions")
                .accessibilityIdentifier(
                    "userProfile.actions"
                )
            }
        }
    }

    private func informationItems(
        for profile: GitLabUserProfile
    ) -> [GitLabUserProfileRowItem] {
        var items: [GitLabUserProfileRowItem] = []

        if let jobTitle = profile.jobTitle {
            items.append(
                .init(
                    id: "job",
                    title: "Job title",
                    value: jobTitle,
                    systemImage: "briefcase"
                )
            )
        }
        if let organization = profile.organization {
            items.append(
                .init(
                    id: "organization",
                    title: "Organization",
                    value: organization,
                    systemImage: "building.2"
                )
            )
        }
        if let workInformation = profile.workInformation {
            items.append(
                .init(
                    id: "work",
                    title: "Work",
                    value: workInformation,
                    systemImage: "person.crop.rectangle.stack"
                )
            )
        }
        if let location = profile.location {
            items.append(
                .init(
                    id: "location",
                    title: "Location",
                    value: location,
                    systemImage: "location"
                )
            )
        }
        if let localTime = profile.localTime {
            items.append(
                .init(
                    id: "time",
                    title: "Local time",
                    value: localTime,
                    systemImage: "clock"
                )
            )
        }
        if let createdAt = profile.createdAt {
            items.append(
                .init(
                    id: "created",
                    title: "Member since",
                    value: createdAt.formatted(
                        date: .long,
                        time: .omitted
                    ),
                    systemImage: "calendar"
                )
            )
        }

        return items
    }

    private var followFailureIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                model.followFailure != nil
            },
            set: { isPresented in
                if !isPresented {
                    model.dismissFollowFailure()
                }
            }
        )
    }

    private func handleAuthenticationFailure() async {
        guard let error = model.authenticationFailure else {
            return
        }
        await appSession.handleAuthenticationFailure(
            error,
            for: model.accountID
        )
    }
}

private struct GitLabUserProfileIdentityHeader:
    View
{
    let summary: GitLabUserSummary
    let pronouns: String?
    let status: GitLabUserStatus?
    let isBot: Bool
    let isLocked: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            GitLabUserAvatar(
                user: summary,
                size: 76
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.displayName)
                    .font(.glabTitle2.bold())
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("@\(summary.username)")
                    if let pronouns {
                        Text("·")
                        Text(pronouns)
                    }
                }
                .font(.glabSubheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

                if
                    isBot
                        || isLocked
                        || status?.availability == "busy"
                {
                    HStack(spacing: 6) {
                        if isBot {
                            badge(
                                "Bot",
                                systemImage: "gearshape.2"
                            )
                        }
                        if isLocked {
                            badge(
                                "Locked",
                                systemImage: "lock.fill"
                            )
                        }
                        if status?.availability == "busy" {
                            badge(
                                "Busy",
                                systemImage: "minus.circle.fill"
                            )
                        }
                    }
                }

                if let message = status?.message {
                    Label(
                        message,
                        systemImage: "message.fill"
                    )
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func badge(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.glabCaption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(Color.glabAccent)
            .background(
                Color.glabAccent.opacity(0.12),
                in: .capsule
            )
    }
}

private struct GitLabUserProfileSection<Content: View>:
    View
{
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.glabTitle3.bold())

            content
                .padding(.horizontal, 14)
                .background(
                    Color.glabSurface,
                    in: .rect(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            Color.primary.opacity(0.07),
                            lineWidth: 1
                        )
                }
        }
    }
}

private nonisolated struct GitLabUserProfileRowItem:
    Identifiable,
    Sendable
{
    let id: String
    let title: String
    let value: String
    let systemImage: String
}

private struct GitLabUserProfileRows: View {
    let items: [GitLabUserProfileRowItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) {
                index,
                item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: item.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.glabCaption)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.glabBody)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 34)
                }
            }
        }
    }
}

private struct GitLabUserContactRows: View {
    let contacts: [GitLabUserContact]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(contacts.enumerated()),
                id: \.element.id
            ) { index, contact in
                contactRow(contact)
                    .padding(.vertical, 11)

                if index < contacts.count - 1 {
                    Divider()
                        .padding(.leading, 34)
                }
            }
        }
    }

    @ViewBuilder
    private func contactRow(
        _ contact: GitLabUserContact
    ) -> some View {
        if let destination = contact.destination {
            Link(destination: destination) {
                rowLabel(contact, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                "Opens \(contact.title)."
            )
        } else {
            rowLabel(contact, showsChevron: false)
                .textSelection(.enabled)
        }
    }

    private func rowLabel(
        _ contact: GitLabUserContact,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            contactIcon(contact.icon)

            VStack(alignment: .leading, spacing: 2) {
                if contact.showsTitle {
                    Text(contact.title)
                        .font(.glabCaption)
                        .foregroundStyle(.secondary)
                }
                Text(contact.value)
                    .font(.glabBody)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "arrow.up.right")
                    .font(.glabCaption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(contact.title), \(contact.value)"
        )
    }

    @ViewBuilder
    private func contactIcon(
        _ icon: GitLabUserContact.Icon
    ) -> some View {
        switch icon {
        case let .asset(name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        case let .system(name):
            Image(systemName: name)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
        }
    }
}

private struct GitLabUserGPGKeysView: View {
    let model: GitLabUserProfileModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("GPG Keys")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(
                        placement: .confirmationAction
                    ) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.gpgKeysState {
        case .idle, .loading:
            GitLabContentStateScrollView {
                ProgressView("Loading GPG keys")
            }
        case let .failed(error):
            GitLabContentStateScrollView {
                GitLabRetryStateView(error: error) {
                    Task {
                        await model.retryGPGKeys()
                    }
                }
            }
        case let .loaded(keys) where keys.isEmpty:
            GitLabContentStateScrollView {
                GitLabEmptyStateView(
                    title: "No Public GPG Keys",
                    message:
                        "This user has not published a GPG key on GitLab.",
                    systemImage: "key.horizontal"
                )
            }
        case let .loaded(keys):
            GlabList {
                Section {
                    ForEach(keys) { key in
                        NavigationLink {
                            GitLabUserGPGKeyDetailView(
                                key: key
                            )
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Label(
                                    "GPG key #\(key.id)",
                                    systemImage: "key.horizontal"
                                )
                                .font(.glabBody.weight(.semibold))

                                if let createdAt = key.createdAt {
                                    Text(
                                        "Added "
                                            + createdAt.formatted(
                                                date: .abbreviated,
                                                time: .omitted
                                            )
                                    )
                                    .font(.glabCaption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } footer: {
                    Text(
                        "GitLab’s public API does not provide a cryptographic fingerprint."
                    )
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct GitLabUserGPGKeyDetailView: View {
    let key: GitLabUserGPGKey

    var body: some View {
        ScrollView {
            Text(key.key)
                .font(
                    .system(
                        .caption,
                        design: .monospaced
                    )
                )
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(16)
                .background(
                    Color.glabSurface,
                    in: .rect(cornerRadius: 14)
                )
                .padding(16)
        }
        .background(Color.glabCanvas)
        .navigationTitle("GPG Key #\(key.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(
                placement: .topBarTrailing
            ) {
                Button {
                    UIPasteboard.general.string = key.key
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy public key")

                ShareLink(item: key.key) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share public key")
            }
        }
    }
}
