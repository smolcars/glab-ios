import SwiftUI

private struct
    GitLabPipelineActionServiceEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabPipelineActionServing =
            UnavailableGitLabPipelineActionService()
}

extension EnvironmentValues {
    var gitLabPipelineActionService:
        any GitLabPipelineActionServing
    {
        get {
            self[
                GitLabPipelineActionServiceEnvironmentKey
                    .self
            ]
        }
        set {
            self[
                GitLabPipelineActionServiceEnvironmentKey
                    .self
            ] = newValue
        }
    }
}

nonisolated struct
    UnavailableGitLabPipelineActionService:
    GitLabPipelineActionServing
{
    func retryPipeline(
        at route: GitLabPipelineRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        throw unavailable
    }

    func cancelPipeline(
        at route: GitLabPipelineRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        throw unavailable
    }

    func retryJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        throw unavailable
    }

    func cancelJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        throw unavailable
    }

    func playJob(
        at route: GitLabJobRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        throw unavailable
    }

    func createMergeRequestPipeline(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        throw unavailable
    }

    private var unavailable:
        GitLabSessionClientError
    {
        .insufficientAccess(
            required: .write
        )
    }
}
