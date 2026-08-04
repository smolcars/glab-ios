import Foundation
import Testing
@testable import Glab

@Suite("GitLab user endpoints")
struct GitLabUserEndpointTests {
    @Test("Builds public profile requests")
    func buildsProfileRequests() throws {
        let endpoints = [
            (
                GitLabUserEndpoints.profile(userID: 42),
                "users/42"
            ),
        ]

        for (endpoint, path) in endpoints {
            let request = try request(endpoint)

            #expect(endpoint.method == .get)
            #expect(endpoint.requiredAccess == .read)
            #expect(
                request.url?.absoluteString
                    == "https://gitlab.example.com/api/v4/\(path)"
            )
        }
    }

    @Test("Builds user status and GPG key requests")
    func buildsAuxiliaryRequests() throws {
        let status = GitLabUserEndpoints.status(
            userID: 42
        )
        let gpgKeys = GitLabUserEndpoints.gpgKeys(
            userID: 42
        )

        #expect(status.method == .get)
        #expect(status.requiredAccess == .read)
        #expect(
            try request(status).url?.absoluteString
                == "https://gitlab.example.com/api/v4/users/42/status"
        )
        #expect(gpgKeys.method == .get)
        #expect(gpgKeys.requiredAccess == .read)
        #expect(
            try request(gpgKeys).url?.absoluteString
                == "https://gitlab.example.com/api/v4/users/42/gpg_keys"
        )
    }

    @Test(
        "Builds follow mutations",
        arguments: [true, false]
    )
    func buildsFollowMutations(
        isFollowed: Bool
    ) throws {
        let endpoint = isFollowed
            ? GitLabUserEndpoints.follow(userID: 42)
            : GitLabUserEndpoints.unfollow(userID: 42)
        let request = try request(endpoint)

        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/users/42/"
                + (isFollowed ? "follow" : "unfollow")
        )
    }
}

private extension GitLabUserEndpointTests {
    nonisolated func request<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URLRequest {
        try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization: .personalAccessToken("pat-secret")
        ).build(endpoint)
    }
}
