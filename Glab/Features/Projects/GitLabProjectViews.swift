import SwiftUI

struct ProjectsView: View {
    let mode: GitLabProjectListMode
    let accountID: GitLabAccountID
    let appSession: AppSession
    let projectStarChange:
        GitLabProjectStarChange?

    @State private var model: ProjectsModel

    init(
        mode: GitLabProjectListMode,
        loader: any GitLabProjectLoading,
        accountID: GitLabAccountID,
        appSession: AppSession,
        projectStarChange:
            GitLabProjectStarChange?
    ) {
        self.mode = mode
        self.accountID = accountID
        self.appSession = appSession
        self.projectStarChange =
            projectStarChange
        _model = State(
            initialValue: ProjectsModel(
                mode: mode,
                loader: loader
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        content
            .background(
                Color.glabCanvas
            )
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                GitLabSearchField(
                    text: $model.searchText,
                    prompt:
                        "Search loaded projects",
                    accessibilityIdentifier:
                        "projects.search"
                )
            }
            .ignoresSafeArea(
                .keyboard,
                edges: .bottom
            )
            .refreshable {
                await refresh()
            }
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
            .onChange(
                of: projectStarChange?.id
            ) { _, _ in
                guard let projectStarChange else {
                    return
                }
                reconcile(projectStarChange)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingInitial {
            ScrollView {
                GitLabLoadingStateView(
                    message:
                        "Loading \(mode.title.lowercased())"
                )
                .padding(20)
            }
        } else if
            model.projects.isEmpty,
            let error = model.loadError
        {
            GitLabContentStateScrollView {
                GitLabRetryStateView(
                    error: error
                ) {
                    Task {
                        await refresh()
                    }
                }
            }
        } else if
            model.projects.isEmpty,
            model.hasLoaded
        {
            GitLabContentStateScrollView {
                GitLabEmptyStateView(
                    title: mode.emptyTitle,
                    message: mode.emptyMessage,
                    systemImage: mode.systemImage
                )
            }
        } else {
            projectList
        }
    }

    private var projectList: some View {
        GlabList {
            if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title: "Couldn’t refresh projects",
                    error: error,
                    accessibilityIdentifier:
                        "projects.refreshError"
                ) {
                    Task {
                        await refresh()
                    }
                }
            }

            if
                model.displayedProjects.isEmpty,
                !model.searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            {
                ContentUnavailableView.search(
                    text: model.searchText
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(model.displayedProjects) {
                    project in
                    projectRow(project)
                        .accessibilityIdentifier(
                            "projects.row.\(project.id)"
                        )
                        .task {
                            await model
                                .loadNextPageIfNeeded(
                                    after: project
                                )
                            await handleAuthenticationFailure()
                        }
                }
            }

            if model.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more…")
                        .font(.glabFootnote)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if
                model.didFailNextPage,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title: "Couldn’t load more projects",
                    error: error,
                    accessibilityIdentifier:
                        "projects.nextPageError"
                ) {
                    Task {
                        await model.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(
            "projects.\(mode.rawValue).list"
        )
    }

    private func projectRow(
        _ project: GitLabProject
    ) -> some View {
        NavigationLink(
            value: GitLabNativeRoute.project(
                GitLabProjectRoute(
                    pathWithNamespace:
                        project.pathWithNamespace
                )
            )
        ) {
            GitLabProjectRow(
                project: project
            )
        }
    }

    private func refresh() async {
        await model.refresh()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure() async {
        guard
            let error = model.authenticationFailure
        else {
            return
        }
        await appSession.handleAuthenticationFailure(
            error,
            for: accountID
        )
    }

    private func reconcile(
        _ change: GitLabProjectStarChange
    ) {
        switch mode {
        case .recent:
            model.reconcileItemIfPresent(
                change.project
            )
        case .starred:
            if change.isStarred {
                model.reconcileItemAtStart(
                    change.project,
                    countAdjustmentIfInserted: 1
                )
            } else {
                model.removeItemIfPresent(
                    change.project
                )
            }
        }
    }
}

private struct GitLabProjectRow: View {
    let project: GitLabProject

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        GitLabProjectAvatar(
                            project: project
                        )
                        namespace
                        Spacer(minLength: 4)
                    }

                    name
                    path
                    accessibilityMetadata
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    GitLabProjectAvatar(
                        project: project
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        namespace
                        name
                        path
                        metadata
                    }

                    Spacer(minLength: 4)
                }
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            "Opens project details"
        )
    }

    private var namespace: some View {
        Text(project.namespaceTitle)
            .font(.glabCaption)
            .foregroundStyle(.secondary)
            .lineLimit(
                dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 1
            )
            .fixedSize(
                horizontal: false,
                vertical: dynamicTypeSize.isAccessibilitySize
            )
    }

    private var name: some View {
        Text(project.name)
            .font(.glabBody.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(
                dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 2
            )
            .fixedSize(
                horizontal: false,
                vertical: dynamicTypeSize.isAccessibilitySize
            )
    }

    private var path: some View {
        Text(project.pathWithNamespace)
            .font(.glabCaption)
            .foregroundStyle(.secondary)
            .lineLimit(
                dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 1
            )
            .fixedSize(
                horizontal: false,
                vertical: dynamicTypeSize.isAccessibilitySize
            )
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                visibilityMetadata
                starsMetadata
                activityMetadata
            }

            VStack(alignment: .leading, spacing: 3) {
                visibilityMetadata
                starsMetadata
                activityMetadata
            }
        }
        .font(.glabCaption2)
        .foregroundStyle(.secondary)
    }

    private var accessibilityMetadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            visibilityMetadata
            starsMetadata
            activityMetadata
        }
        .font(.glabCaption2)
        .foregroundStyle(.secondary)
    }

    private var visibilityMetadata: some View {
        Label(
            project.visibility.title,
            systemImage:
                project.visibility.systemImage
        )
    }

    private var starsMetadata: some View {
        Label(
            "\(project.starCount)",
            systemImage: "star"
        )
    }

    private var activityMetadata: some View {
        Text(
            "Activity "
                + GitLabRelativeTimeFormatter.string(
                    from: project.lastActivityAt
                )
        )
        .accessibilityLabel(
            "Last recorded activity "
                + project.lastActivityAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
        )
    }

    private var accessibilityLabel: String {
        let starDescription =
            project.starCount == 1
            ? "1 star"
            : "\(project.starCount) stars"
        return [
            project.name,
            project.pathWithNamespace,
            project.visibility.title,
            starDescription,
            "Last recorded activity "
                + project.lastActivityAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                ),
        ]
        .joined(separator: ", ")
    }
}

private struct GitLabProjectAvatar: View {
    let project: GitLabProject

    var body: some View {
        AsyncImage(url: project.safeAvatarURL) {
            image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            fallback
        }
        .frame(width: 44, height: 44)
        .background(Color.glabBrandWarm.opacity(0.12))
        .clipShape(.rect(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    Color.secondary.opacity(0.18),
                    lineWidth: 0.5
                )
        }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(project.avatarMark)
            .font(.glabCaption.weight(.bold))
            .foregroundStyle(Color.glabBrandWarm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
