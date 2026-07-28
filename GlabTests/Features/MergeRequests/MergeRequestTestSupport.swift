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
    changesCount: String? = nil,
    detailedMergeStatus: String? = nil,
    hasConflicts: Bool? = nil,
    blockingDiscussionsResolved: Bool? = nil,
    headPipeline:
        GitLabMergeRequestHeadPipeline? = nil
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
        changesCount: changesCount,
        detailedMergeStatus:
            detailedMergeStatus,
        hasConflicts: hasConflicts,
        blockingDiscussionsResolved:
            blockingDiscussionsResolved,
        headPipeline: headPipeline
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

nonisolated func makeTestDiffFile(
    oldPath: String = "Sources/File.swift",
    newPath: String = "Sources/File.swift",
    diff: String = "@@ -1 +1 @@\n-old\n+new",
    isNewFile: Bool = false,
    isRenamedFile: Bool = false,
    isDeletedFile: Bool = false,
    isGeneratedFile: Bool = false,
    isCollapsed: Bool = false,
    isTooLarge: Bool = false
) -> GitLabMergeRequestDiffFile {
    GitLabMergeRequestDiffFile(
        oldPath: oldPath,
        newPath: newPath,
        oldMode: "100644",
        newMode: "100644",
        diff: diff,
        isNewFile: isNewFile,
        isRenamedFile: isRenamedFile,
        isDeletedFile: isDeletedFile,
        isGeneratedFile: isGeneratedFile,
        isCollapsed: isCollapsed,
        isTooLarge: isTooLarge
    )
}
