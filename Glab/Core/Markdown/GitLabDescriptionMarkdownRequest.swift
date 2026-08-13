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

    static func todo(
        accountID: GitLabAccountID,
        todo: GitLabTodo,
        source: String
    ) -> GitLabMarkdownRequest? {
        guard
            let source = nonemptySource(source),
            let projectID =
                todo.target?.projectID
                ?? todo.project?.id,
            let iid = todo.target?.iid
        else {
            return nil
        }

        let resource: GitLabMarkdownResourceID
        switch todo.targetType {
        case .issue:
            resource = .issue(
                projectID: projectID,
                issueIID: iid
            )
        case .mergeRequest:
            resource = .mergeRequest(
                projectID: projectID,
                mergeRequestIID: iid
            )
        case
            .commit,
            .epic,
            .design,
            .alert,
            .project,
            .namespace,
            .vulnerability,
            .wikiPage,
            .unknown:
            return nil
        }

        return GitLabMarkdownRequest(
            accountID: accountID,
            resource: resource,
            source: source,
            webURL: todo.safeTargetURL
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
