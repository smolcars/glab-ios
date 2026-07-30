import SwiftUI

nonisolated protocol GitLabMentionSearching:
    Sendable
{
    func searchProjectMembers(
        projectID: Int,
        query: String
    ) async throws(GitLabSessionClientError)
        -> [GitLabProjectMember]
}

nonisolated struct LiveGitLabMentionService:
    GitLabMentionSearching,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending

    init(
        client: any GitLabSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func searchProjectMembers(
        projectID: Int,
        query: String
    ) async throws(GitLabSessionClientError)
        -> [GitLabProjectMember]
    {
        try await client.send(
            GitLabProjectMemberEndpoints
                .members(
                    projectID: projectID,
                    search: query,
                    perPage: 10
                )
        )
    }
}

private struct
    GitLabMentionServiceEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabMentionSearching =
            UnavailableGitLabMentionService()
}

extension EnvironmentValues {
    var gitLabMentionService:
        any GitLabMentionSearching
    {
        get {
            self[
                GitLabMentionServiceEnvironmentKey
                    .self
            ]
        }
        set {
            self[
                GitLabMentionServiceEnvironmentKey
                    .self
            ] = newValue
        }
    }
}

nonisolated struct
    UnavailableGitLabMentionService:
    GitLabMentionSearching
{
    func searchProjectMembers(
        projectID _: Int,
        query _: String
    ) async throws(GitLabSessionClientError)
        -> [GitLabProjectMember]
    {
        []
    }
}
