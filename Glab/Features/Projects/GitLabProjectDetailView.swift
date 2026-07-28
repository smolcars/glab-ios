import SwiftUI

struct GitLabProjectDetailView: View {
    let route: GitLabProjectRoute
    let accountID: GitLabAccountID
    let appSession: AppSession

    @State private var model:
        GitLabProjectDetailModel

    init(
        route: GitLabProjectRoute,
        loader: any GitLabProjectResolving,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.route = route
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabProjectDetailModel(
                    route: route,
                    loader: loader
                )
        )
    }

    var body: some View {
        content
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
            )
            .task {
                await load()
            }
            .accessibilityIdentifier(
                "project.detail"
            )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                GitLabLoadingStateView(
                    message: "Loading project"
                )
                .padding(20)
            }
        case let .failed(error):
            GitLabContentStateScrollView {
                GitLabRetryStateView(
                    error: error
                ) {
                    Task {
                        await retry()
                    }
                }
            }
        case let .loaded(project):
            projectContent(project)
        }
    }

    private func projectContent(
        _ project: GitLabProject
    ) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 24
            ) {
                projectHeader(project)

                GitLabDetailSection(
                    title: "Project"
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        metadataRow(
                            title: "Visibility",
                            value:
                                project
                                    .visibility
                                    .title,
                            systemImage:
                                project
                                    .visibility
                                    .systemImage
                        )
                        metadataRow(
                            title: "Stars",
                            value:
                                project.starCount
                                    .formatted(),
                            systemImage: "star"
                        )
                        metadataRow(
                            title: "Last activity",
                            value:
                                project
                                    .lastActivityAt
                                    .formatted(
                                        date:
                                            .abbreviated,
                                        time:
                                            .shortened
                                    ),
                            systemImage: "clock"
                        )
                    }
                }

                if
                    let destination =
                        project.safeWebURL
                {
                    GitLabOpenInGitLabLink(
                        destination:
                            destination,
                        accessibilityIdentifier:
                            "project.openInGitLab"
                    )
                    .padding(.horizontal, -20)
                }
            }
            .padding(20)
        }
        .refreshable {
            await retry()
        }
    }

    private func projectHeader(
        _ project: GitLabProject
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(
                url: project.safeAvatarURL
            ) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Text(project.avatarMark)
                        .font(
                            .headline.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 58, height: 58)
            .background(
                Color.orange.opacity(0.12)
            )
            .clipShape(
                .rect(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 14
                )
                .stroke(
                    Color.secondary
                        .opacity(0.18),
                    lineWidth: 0.5
                )
            }
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(project.name)
                    .font(.title2.bold())
                Text(
                    project.pathWithNamespace
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .accessibilityElement(
            children: .combine
        )
        .accessibilityIdentifier(
            "project.header"
        )
    }

    private func metadataRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(
                    .trailing
                )
        } label: {
            Label(
                title,
                systemImage: systemImage
            )
        }
    }

    private func load() async {
        await model.loadIfNeeded()
        await handleAuthenticationFailure()
    }

    private func retry() async {
        await model.retry()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                model.authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}
