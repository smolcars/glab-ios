import Foundation
import Testing
@testable import Glab

@Suite("GitLab repository endpoints")
struct GitLabRepositoryEndpointTests {
    @Test("Builds root and nested tree requests")
    func buildsTreeRequests() throws {
        let root = try requestURL(
            GitLabRepositoryEndpoints.tree(
                projectID: 42,
                ref: "main",
                path: ""
            )
        )
        let nested = try requestURL(
            GitLabRepositoryEndpoints.tree(
                projectID: 42,
                ref: "feature/source viewer",
                path: "Sources/App UI"
            )
        )

        #expect(
            root.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/repository/tree"
                + "?ref=main&per_page=100"
        )
        #expect(
            nested.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/repository/tree"
                + "?path=Sources/App%20UI"
                + "&ref=feature/source%20viewer"
                + "&per_page=100"
        )
    }

    @Test("Builds branch and repository search requests")
    func buildsBranchAndSearchRequests() throws {
        let branches = try requestURL(
            GitLabRepositoryEndpoints.branches(
                projectID: 42,
                search: "release"
            )
        )
        let search = try requestURL(
            GitLabRepositoryEndpoints.search(
                projectID: 42,
                ref: "main",
                query: "SourceView"
            )
        )

        #expect(
            branches.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/repository/branches"
                + "?search=release&per_page=100"
        )
        #expect(
            search.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/search"
                + "?scope=blobs&search=SourceView"
                + "&ref=main&per_page=20"
        )
    }

    @Test("Encodes a file path as one raw endpoint component")
    func buildsRawFileRequest() throws {
        let route = GitLabRepositoryFileRoute(
            projectID: 42,
            projectWebURL: nil,
            ref: "feature/source viewer",
            path: "Sources/App UI/File.swift",
            blobID: "blob-sha"
        )
        let request = try GitLabRequestBuilder(
            host: GitLabHost(
                "gitlab.example.com"
            ),
            authorization:
                .personalAccessToken(
                    "pat-secret"
                )
        )
        .build(
            GitLabRepositoryEndpoints
                .rawFile(at: route)
        )

        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/repository/files/"
                + "Sources%2FApp%20UI%2FFile.swift/raw"
                + "?ref=feature/source%20viewer"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Accept"
            )
                == "text/plain, application/octet-stream, */*"
        )
    }
}

private extension GitLabRepositoryEndpointTests {
    nonisolated func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URL {
        let request = try GitLabRequestBuilder(
            host: GitLabHost(
                "gitlab.example.com"
            ),
            authorization:
                .personalAccessToken(
                    "pat-secret"
                )
        )
        .build(endpoint)

        return try #require(request.url)
    }
}
