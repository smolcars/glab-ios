import Foundation
@testable import Glab

nonisolated func makeTestProject(
    id: Int = 42,
    name: String = "Glab iOS",
    nameWithNamespace: String = "Mobile / Glab iOS",
    pathWithNamespace: String = "mobile/glab-ios",
    webURL: URL? = URL(
        string: "https://gitlab.example.com/mobile/glab-ios"
    ),
    avatarURL: URL? = nil,
    starCount: Int = 17,
    lastActivityAt: Date = Date(
        timeIntervalSince1970: 1_785_139_200
    ),
    visibility: GitLabProjectVisibility = .privateAccess,
    namespace: GitLabProjectNamespace? = GitLabProjectNamespace(
        id: 7,
        name: "Mobile",
        path: "mobile",
        kind: "group",
        fullPath: "mobile"
    ),
    issuesAccessLevel:
        GitLabProjectFeatureAccessLevel? =
            .enabled,
    mergeRequestsAccessLevel:
        GitLabProjectFeatureAccessLevel? =
            .enabled
) -> GitLabProject {
    GitLabProject(
        id: id,
        name: name,
        nameWithNamespace: nameWithNamespace,
        pathWithNamespace: pathWithNamespace,
        webURL: webURL,
        avatarURL: avatarURL,
        starCount: starCount,
        lastActivityAt: lastActivityAt,
        visibility: visibility,
        namespace: namespace,
        issuesAccessLevel:
            issuesAccessLevel,
        mergeRequestsAccessLevel:
            mergeRequestsAccessLevel
    )
}
