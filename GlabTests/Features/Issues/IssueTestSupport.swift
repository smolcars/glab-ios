import Foundation
@testable import Glab

nonisolated func makeTestIssue(
    id: Int = 101,
    iid: Int = 7,
    projectID: Int = 42,
    title: String = "Fix pagination",
    description: String? = "Follow the Link header.",
    state: String = "opened",
    confidential: Bool = false,
    labels: [String] = ["bug"],
    author: GitLabIssueUser = makeTestIssueUser(),
    assignees: [GitLabIssueUser] = [makeTestIssueUser(id: 2)],
    milestone: GitLabIssueMilestone? = nil,
    dueDate: String? = nil,
    userNotesCount: Int = 3,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    updatedAt: Date = Date(timeIntervalSince1970: 1_700_003_600),
    closedAt: Date? = nil,
    webURL: URL? = URL(
        string: "https://gitlab.example.com/group/project/-/issues/7"
    ),
    reference: String = "group/project#7"
) -> GitLabIssue {
    GitLabIssue(
        id: id,
        iid: iid,
        projectID: projectID,
        title: title,
        description: description,
        state: state,
        confidential: confidential,
        labels: labels,
        author: author,
        assignees: assignees,
        milestone: milestone,
        dueDate: dueDate,
        userNotesCount: userNotesCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
        closedAt: closedAt,
        webURL: webURL,
        references: GitLabIssueReferences(
            short: "#\(iid)",
            relative: reference,
            full: reference
        )
    )
}

nonisolated func makeTestIssueUser(
    id: Int = 1,
    username: String = "octocat",
    name: String = "The Octocat"
) -> GitLabIssueUser {
    GitLabIssueUser(
        id: id,
        username: username,
        name: name,
        avatarURL: nil,
        webURL: URL(
            string: "https://gitlab.example.com/\(username)"
        )
    )
}

