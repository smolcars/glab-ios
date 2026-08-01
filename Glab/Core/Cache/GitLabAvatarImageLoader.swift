import Foundation

nonisolated protocol GitLabAvatarImageLoading:
    Sendable
{
    func image(
        at url: URL,
        targetPixelWidth: Int
    ) async throws -> GitLabMarkdownDecodedImage
}

actor UnavailableGitLabAvatarImageLoader:
    GitLabAvatarImageLoading
{
    func image(
        at url: URL,
        targetPixelWidth: Int
    ) async throws -> GitLabMarkdownDecodedImage {
        throw GitLabMarkdownImageError.unavailable
    }
}

nonisolated struct GitLabAvatarImageLoader:
    GitLabAvatarImageLoading
{
    let accountID: GitLabAccountID
    let imageLoader: any GitLabMarkdownImageLoading

    func image(
        at url: URL,
        targetPixelWidth: Int
    ) async throws -> GitLabMarkdownDecodedImage {
        try await imageLoader.image(
            GitLabMarkdownImageLoadRequest(
                accountID: accountID,
                url: url,
                targetPixelWidth: targetPixelWidth
            )
        )
    }
}
