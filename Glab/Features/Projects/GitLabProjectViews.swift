import SwiftUI

struct ProjectsView: View {
    let mode: GitLabProjectListMode
    let appSession: AppSession

    @State private var model: ProjectsModel

    init(
        mode: GitLabProjectListMode,
        loader: any GitLabProjectLoading,
        appSession: AppSession
    ) {
        self.mode = mode
        self.appSession = appSession
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
                Color(uiColor: .systemGroupedBackground)
            )
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $model.searchText,
                placement:
                    .navigationBarDrawer(
                        displayMode: .always
                    ),
                prompt: "Search loaded projects"
            )
            .refreshable {
                await refresh()
            }
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
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
                    message: error.description
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
        List {
            if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title: "Couldn’t refresh projects",
                    message: error.description,
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
                        .font(.footnote)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if model.didFailNextPage {
                Button {
                    Task {
                        await model.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                } label: {
                    Label(
                        "Try loading more projects again",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(
            "projects.\(mode.rawValue).list"
        )
    }

    @ViewBuilder
    private func projectRow(
        _ project: GitLabProject
    ) -> some View {
        if let destination = project.safeWebURL {
            Link(destination: destination) {
                GitLabProjectRow(
                    project: project,
                    showsExternalLink: true
                )
            }
            .buttonStyle(.plain)
        } else {
            GitLabProjectRow(
                project: project,
                showsExternalLink: false
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
        await appSession.handleAuthenticationFailure(error)
    }
}

private struct GitLabProjectRow: View {
    let project: GitLabProject
    let showsExternalLink: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GitLabProjectAvatar(project: project)

            VStack(alignment: .leading, spacing: 5) {
                Text(project.namespaceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(project.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(project.pathWithNamespace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                metadata
            }

            Spacer(minLength: 4)

            if showsExternalLink {
                Image(
                    systemName:
                        "arrow.up.right.square"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            showsExternalLink
                ? "Opens in GitLab"
                : "A safe GitLab link is unavailable"
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
        .font(.caption2)
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
        .background(Color.orange.opacity(0.12))
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
            .font(.caption.weight(.bold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
