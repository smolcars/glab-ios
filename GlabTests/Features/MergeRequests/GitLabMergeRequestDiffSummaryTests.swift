import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request diff summary")
struct GitLabMergeRequestDiffSummaryTests {
    @Test("Builds a read-only GraphQL query under a self-managed relative root")
    func buildsGraphQLQuery() throws {
        let endpoint =
            try GitLabMergeRequestDiffSummaryEndpoint
                .query(mergeRequestID: 314)
        let request = try GitLabRequestBuilder(
            host: GitLabHost(
                "https://gitlab.example.com/company/gitlab"
            ),
            authorization:
                .personalAccessToken(
                    "pat-secret"
                )
        ).build(endpoint)
        let body = try #require(
            request.httpBody
        )
        let object = try #require(
            JSONSerialization.jsonObject(
                with: body
            ) as? [String: Any]
        )
        let variables = try #require(
            object["variables"]
                as? [String: String]
        )
        let query = try #require(
            object["query"] as? String
        )

        #expect(endpoint.target == .graphQL)
        #expect(endpoint.requiredAccess == .read)
        #expect(endpoint.method == .post)
        #expect(endpoint.pathComponents.isEmpty)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/company/gitlab/api/graphql"
        )
        #expect(
            variables["id"]
                == "gid://gitlab/MergeRequest/314"
        )
        #expect(
            query.contains(
                "diffStatsSummary"
            )
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "PRIVATE-TOKEN"
            ) == "pat-secret"
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "Content-Type"
            ) == "application/json"
        )
        #expect(
            !String(
                decoding: body,
                as: UTF8.self
            ).contains("pat-secret")
        )
    }

    @Test("Builds the GitLab.com GraphQL query with OAuth")
    func buildsHostedOAuthGraphQLQuery() throws {
        let endpoint =
            try GitLabMergeRequestDiffSummaryEndpoint
                .query(mergeRequestID: 7)
        let request = try GitLabRequestBuilder(
            host: GitLabHost("gitlab.com"),
            authorization:
                .oauth(
                    accessToken:
                        "oauth-secret"
                )
        ).build(endpoint)

        #expect(
            request.url?.absoluteString
                == "https://gitlab.com/api/graphql"
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "Authorization"
            ) == "Bearer oauth-secret"
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "PRIVATE-TOKEN"
            ) == nil
        )
        #expect(
            !(request.httpBody.map {
                String(
                    decoding: $0,
                    as: UTF8.self
                )
            } ?? "").contains(
                "oauth-secret"
            )
        )
    }

    @Test("Maps a complete GraphQL summary")
    func loadsSummary() async throws {
        let client = DiffSummaryClient(
            json:
                """
                {
                  "data": {
                    "mergeRequest": {
                      "diffStatsSummary": {
                        "additions": 727,
                        "deletions": 7,
                        "changes": 734,
                        "fileCount": 12,
                        "futureField": true
                      }
                    }
                  }
                }
                """
        )
        let loader = LiveGitLabMergeRequestLoader(
            client: client
        )

        let availability =
            try await loader
                .loadMergeRequestDiffSummary(
                    mergeRequestID: 314
                )

        #expect(
            availability
                == .available(
                    GitLabMergeRequestDiffSummary(
                        additions: 727,
                        deletions: 7,
                        changes: 734,
                        fileCount: 12
                    )
                )
        )
        #expect(await client.sendCount == 1)
        #expect(
            await client.lastRequiredAccess
                == .read
        )
    }

    @Test(
        "Treats incomplete or incompatible GraphQL data as unavailable",
        arguments: [
            """
            {"data":{"mergeRequest":null}}
            """,
            """
            {"data":{"mergeRequest":{"diffStatsSummary":null}}}
            """,
            """
            {"errors":[{"message":"Unknown field"}]}
            """,
            """
            {"data":{"mergeRequest":{"diffStatsSummary":{"additions":1,"deletions":2,"fileCount":3}}}}
            """,
            """
            {"data":{"mergeRequest":{"diffStatsSummary":{"additions":-1,"deletions":2,"changes":1,"fileCount":3}}}}
            """,
        ]
    )
    func mapsUnavailableSummary(
        json: String
    ) async throws {
        let loader = LiveGitLabMergeRequestLoader(
            client:
                DiffSummaryClient(
                    json: json
                )
        )

        let availability =
            try await loader
                .loadMergeRequestDiffSummary(
                    mergeRequestID: 314
                )

        #expect(availability == .unavailable)
    }

    @Test(
        "Preserves actionable request failures",
        arguments: [
            GitLabSessionClientError.api(
                .unauthenticated
            ),
            GitLabSessionClientError.api(
                .forbidden
            ),
            GitLabSessionClientError.api(
                .notFound
            ),
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            ),
            GitLabSessionClientError.api(
                .decoding
            ),
        ]
    )
    func preservesFailure(
        failure: GitLabSessionClientError
    ) async {
        let loader = LiveGitLabMergeRequestLoader(
            client:
                DiffSummaryClient(
                    failure: failure
                )
        )

        await #expect(throws: failure) {
            try await loader
                .loadMergeRequestDiffSummary(
                    mergeRequestID: 314
                )
        }
    }

    @Test("Loads a diff summary only once until explicitly retried")
    func loadsSummaryOnce() async {
        let client = DiffSummaryClient(
            json:
                """
                {
                  "data": {
                    "mergeRequest": {
                      "diffStatsSummary": {
                        "additions": 2,
                        "deletions": 1,
                        "changes": 3,
                        "fileCount": 1
                      }
                    }
                  }
                }
                """
        )
        let model = GitLabMergeRequestDiffSummaryModel(
            mergeRequestID: 7,
            loader:
                LiveGitLabMergeRequestLoader(
                    client: client
                )
        )

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(await client.sendCount == 1)
    }
}

@Suite("GitLab merge request diff summary presentation")
struct GitLabMergeRequestDiffSummaryPresentationTests {
    @Test("Presents exact GraphQL statistics")
    func presentsExactStatistics() {
        let presentation =
            GitLabMergeRequestDiffSummaryPresentation(
                state:
                    .loaded(
                        .available(
                            GitLabMergeRequestDiffSummary(
                                additions: 727,
                                deletions: 7,
                                changes: 734,
                                fileCount: 12
                            )
                        )
                    ),
                restChangesCount: "11"
            )

        #expect(
            presentation.fileText
                == "12 files"
        )
        #expect(
            presentation.additionsText
                == "+727"
        )
        #expect(
            presentation.deletionsText
                == "−7"
        )
        #expect(!presentation.isLoading)
        #expect(
            presentation.accessibilityLabel
                == "12 changed files, 727 additions, 7 deletions"
        )
    }

    @Test("Presents exact singular GraphQL statistics")
    func presentsExactSingularStatistics() {
        let presentation =
            GitLabMergeRequestDiffSummaryPresentation(
                state:
                    .loaded(
                        .available(
                            GitLabMergeRequestDiffSummary(
                                additions: 1,
                                deletions: 1,
                                changes: 2,
                                fileCount: 1
                            )
                        )
                    ),
                restChangesCount: nil
            )

        #expect(presentation.fileText == "1 file")
        #expect(
            presentation.accessibilityLabel
                == "1 changed file, 1 additions, 1 deletions"
        )
    }

    @Test(
        "Falls back to a normalized REST count",
        arguments: [
            (
                "1",
                "1 file"
            ),
            (
                "1000+",
                "1000+ files"
            ),
            (
                " 27 ",
                "27 files"
            ),
            (
                "",
                "Changed files"
            ),
        ]
    )
    func fallsBackToRESTCount(
        restCount: String,
        expected: String
    ) {
        let presentation =
            GitLabMergeRequestDiffSummaryPresentation(
                state: .failed(
                    .api(
                        .server(
                            statusCode: 503
                        )
                    )
                ),
                restChangesCount: restCount
            )

        #expect(
            presentation.fileText
                == expected
        )
        #expect(
            presentation.additionsText == nil
        )
        #expect(
            presentation.deletionsText == nil
        )
        #expect(!presentation.isLoading)
    }

    @Test("Keeps a compact loading state with the REST fallback")
    func presentsLoadingFallback() {
        let presentation =
            GitLabMergeRequestDiffSummaryPresentation(
                state: .loading,
                restChangesCount: "8"
            )

        #expect(
            presentation.fileText
                == "8 files"
        )
        #expect(presentation.isLoading)
    }

    @Test(
        "Uses a generic fallback for unavailable or invalid REST counts",
        arguments: [
            (
                GitLabResourceDetailState<
                    GitLabMergeRequestDiffSummaryAvailability
                >.idle,
                "files"
            ),
            (
                .loaded(.unavailable),
                "12 files"
            ),
            (
                .failed(.api(.notFound)),
                "+"
            ),
        ]
    )
    func presentsGenericFallback(
        state:
            GitLabResourceDetailState<
                GitLabMergeRequestDiffSummaryAvailability
            >,
        restCount: String
    ) {
        let presentation =
            GitLabMergeRequestDiffSummaryPresentation(
                state: state,
                restChangesCount: restCount
            )

        #expect(
            presentation.fileText
                == "Changed files"
        )
        #expect(presentation.additionsText == nil)
        #expect(presentation.deletionsText == nil)
    }
}

private actor DiffSummaryClient:
    GitLabPaginatedSessionRequestSending
{
    private let result:
        Result<Data, GitLabSessionClientError>
    private(set) var sendCount = 0
    private(set) var lastRequiredAccess:
        GitLabAPIRequestAccess?

    init(json: String) {
        result = .success(
            Data(json.utf8)
        )
    }

    init(failure: GitLabSessionClientError) {
        result = .failure(failure)
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sendCount += 1
        lastRequiredAccess =
            endpoint.requiredAccess
        let data = try result.get()
        do {
            return try JSONDecoder().decode(
                Response.self,
                from: data
            )
        } catch {
            throw .api(.decoding)
        }
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        throw .api(.invalidResponse)
    }
}
