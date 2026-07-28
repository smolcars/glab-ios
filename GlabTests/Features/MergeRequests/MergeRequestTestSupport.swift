import Foundation
@testable import Glab

nonisolated func makeTestMergeRequest(
    id: Int = 101,
    iid: Int = 7,
    projectID: Int = 42,
    title: String = "Review pagination",
    description: String? = "Follow the Link header.",
    state: String = "opened",
    draft: Bool? = false,
    legacyWorkInProgress: Bool? = nil,
    labels: [String] = ["backend"],
    author: GitLabAPIUser = makeTestAPIUser(),
    assignees: [GitLabAPIUser] = [],
    reviewers: [GitLabAPIUser] = [],
    sourceBranch: String = "feature/pagination",
    targetBranch: String = "main",
    userNotesCount: Int = 3,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    updatedAt: Date = Date(timeIntervalSince1970: 1_700_003_600),
    closedAt: Date? = nil,
    mergedAt: Date? = nil,
    webURL: URL? = URL(
        string:
            "https://gitlab.example.com/group/project/-/merge_requests/7"
    ),
    reference: String = "group/project!7",
    sha: String? = "head-sha",
    diffRefs: GitLabMergeRequestDiffRefs? = nil,
    changesCount: String? = nil
) -> GitLabMergeRequest {
    GitLabMergeRequest(
        id: id,
        iid: iid,
        projectID: projectID,
        title: title,
        description: description,
        state: state,
        draft: draft,
        legacyWorkInProgress: legacyWorkInProgress,
        labels: labels,
        author: author,
        assignees: assignees,
        reviewers: reviewers,
        sourceBranch: sourceBranch,
        targetBranch: targetBranch,
        userNotesCount: userNotesCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
        closedAt: closedAt,
        mergedAt: mergedAt,
        webURL: webURL,
        references: GitLabMergeRequestReferences(
            short: "!\(iid)",
            relative: reference,
            full: reference
        ),
        sha: sha,
        diffRefs: diffRefs,
        changesCount: changesCount
    )
}

nonisolated func makeTestAPIUser(
    id: Int = 1,
    username: String = "octocat",
    name: String = "The Octocat"
) -> GitLabAPIUser {
    GitLabAPIUser(
        id: id,
        username: username,
        name: name,
        avatarURL: nil,
        webURL: URL(
            string: "https://gitlab.example.com/\(username)"
        )
    )
}
