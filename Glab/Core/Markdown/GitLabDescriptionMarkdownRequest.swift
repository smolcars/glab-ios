import Foundation

nonisolated enum
    GitLabDescriptionMarkdownRequest
{
    static func issue(
        accountID: GitLabAccountID,
        issue: GitLabIssue
    ) -> GitLabMarkdownRequest? {
        guard
            let source =
                nonemptySource(
                    issue.description
                )
        else {
            return nil
        }
        return GitLabMarkdownRequest(
            accountID: accountID,
            resource:
                .issue(
                    projectID: issue.projectID,
                    issueIID: issue.iid
                ),
            source: source,
            webURL: issue.safeWebURL
        )
    }

    static func mergeRequest(
        accountID: GitLabAccountID,
        mergeRequest:
            GitLabMergeRequest
    ) -> GitLabMarkdownRequest? {
        guard
            let source =
                nonemptySource(
                    mergeRequest
                        .description
                )
        else {
            return nil
        }
        return GitLabMarkdownRequest(
            accountID: accountID,
            resource:
                .mergeRequest(
                    projectID:
                        mergeRequest.projectID,
                    mergeRequestIID:
                        mergeRequest.iid
                ),
            source: source,
            webURL:
                mergeRequest.safeWebURL
        )
    }

    private static func nonemptySource(
        _ source: String?
    ) -> String? {
        guard
            let source,
            !source
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        else {
            return nil
        }
        return source
    }
}
