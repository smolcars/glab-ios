import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab project starring service")
struct LiveGitLabProjectStarringServiceTests {
    @Test("Finds a starred project on a later page")
    func findsStarredProjectAcrossPages() async throws {
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "users/17/starred_projects?page=2"
            )
        )
        let client = ProjectStarringClient(
            pages: [
                .init(
                    ids: [1, 2],
                    nextPageURL: nextPageURL
                ),
                .init(
                    ids: [42],
                    nextPageURL: nil
                ),
            ]
        )
        let service =
            LiveGitLabProjectStarringService(
                client: client
            )

        let isStarred = try await service.isStarred(
            makeTestProject(),
            byUserID: 17
        )

        #expect(isStarred)
        #expect(
            await client.pageRequests
                == [
                    "users/17/starred_projects"
                        + "?simple=true&per_page=100",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
    }

    @Test("Returns false after exhausting starred projects")
    func reportsUnstarredProject() async throws {
        let client = ProjectStarringClient(
            pages: [
                .init(
                    ids: [1, 2],
                    nextPageURL: nil
                )
            ]
        )
        let service =
            LiveGitLabProjectStarringService(
                client: client
            )

        let isStarred = try await service.isStarred(
            makeTestProject(),
            byUserID: 17
        )

        #expect(!isStarred)
    }

    @Test(
        "Sends the requested mutation and invalidates project reads",
        arguments: [true, false]
    )
    func mutatesAndInvalidatesReads(
        isStarred: Bool
    ) async throws {
        let updatedProject = makeTestProject(
            starCount: isStarred ? 18 : 16
        )
        let client = ProjectStarringClient(
            mutationResult:
                .success(updatedProject)
        )
        let service =
            LiveGitLabProjectStarringService(
                client: client
            )

        let result = try await service.setStarred(
            isStarred,
            for: makeTestProject(),
            byUserID: 17
        )

        #expect(result == updatedProject)
        #expect(
            await client.mutationPaths
                == [
                    "projects/42/"
                        + (isStarred
                            ? "star"
                            : "unstar")
                ]
        )
        #expect(
            await client.invalidatedReads
                == [
                    "projects/mobile/glab-ios",
                    "projects?membership",
                    "projects?starred",
                ]
        )
    }

    @Test("Rejects a mutation response for another project")
    func rejectsMismatchedMutationResponse() async {
        let client = ProjectStarringClient(
            mutationResult:
                .success(
                    makeTestProject(id: 99)
                )
        )
        let service =
            LiveGitLabProjectStarringService(
                client: client
            )

        await #expect {
            try await service.setStarred(
                true,
                for: makeTestProject(),
                byUserID: 17
            )
        } throws: { error in
            error as? GitLabSessionClientError
                == .api(.invalidResponse)
        }
    }

    @Test("Invalidates reads when mutation delivery is unknown")
    func invalidatesAfterUncertainDelivery() async {
        let client = ProjectStarringClient(
            mutationResult:
                .failure(
                    .api(
                        .connectivity(.timedOut)
                    )
                )
        )
        let service =
            LiveGitLabProjectStarringService(
                client: client
            )

        await #expect {
            try await service.setStarred(
                true,
                for: makeTestProject(),
                byUserID: 17
            )
        } throws: { error in
            error as? GitLabSessionClientError
                == .api(
                    .connectivity(.timedOut)
                )
        }
        #expect(
            await client.invalidatedReads.count
                == 3
        )
    }

    @Test(
        "Accepts an already-applied star state",
        arguments: [true, false]
    )
    func acceptsAlreadyAppliedState(
        isStarred: Bool
    ) async throws {
        let updatedProject = makeTestProject(
            starCount: isStarred ? 18 : 16
        )
        let client = ProjectStarringClient(
            pages: [
                .init(
                    ids: isStarred ? [42] : [1],
                    nextPageURL: nil
                )
            ],
            mutationResult:
                .failure(.api(.invalidResponse)),
            projectResult: .success(updatedProject)
        )
        let service =
            LiveGitLabProjectStarringService(
                client: client
            )

        let result = try await service.setStarred(
            isStarred,
            for: makeTestProject(),
            byUserID: 17
        )

        #expect(result == updatedProject)
        #expect(
            await client.mutationPaths
                == [
                    "projects/42/"
                        + (isStarred
                            ? "star"
                            : "unstar"),
                    "projects/mobile/glab-ios",
                ]
        )
        #expect(
            await client.invalidatedReads.count
                == 3
        )
    }
}

private actor ProjectStarringClient:
    GitLabPaginatedSessionRequestSending
{
    struct Page: Sendable {
        let ids: [Int]
        let nextPageURL: URL?
    }

    private var pages: [Page]
    private var projectResults:
        [
        Result<
            GitLabProject,
            GitLabSessionClientError
        >
        ]
    private(set) var pageRequests: [String] = []
    private(set) var mutationPaths: [String] = []
    private(set) var invalidatedReads: [String] = []

    init(
        pages: [Page] = [],
        mutationResult:
            Result<
                GitLabProject,
                GitLabSessionClientError
            > = .success(makeTestProject()),
        projectResult:
            Result<
                GitLabProject,
                GitLabSessionClientError
            >? = nil
    ) {
        self.pages = pages
        projectResults = [mutationResult]
        if let projectResult {
            projectResults.append(projectResult)
        }
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        mutationPaths.append(
            endpoint.pathComponents
                .joined(separator: "/")
        )
        guard !projectResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try projectResults.removeFirst().get()
            as! Response
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        switch page {
        case let .initial(endpoint):
            let query = endpoint.queryItems
                .map {
                    "\($0.name)=\($0.value ?? "")"
                }
                .joined(separator: "&")
            pageRequests.append(
                endpoint.pathComponents
                    .joined(separator: "/")
                    + "?\(query)"
            )
        case let .next(url):
            pageRequests.append(
                "next:\(url.absoluteString)"
            )
        }

        guard !pages.isEmpty else {
            throw .api(.invalidResponse)
        }
        let responsePage = pages.removeFirst()
        let references = responsePage.ids.map {
            GitLabStarredProjectReference(id: $0)
        }
        return GitLabAPIResponse(
            value: references as! Response,
            metadata: GitLabResponseMetadata(
                nextPageURL:
                    responsePage.nextPageURL
            )
        )
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async {
        var identifier = endpoint.pathComponents
            .joined(separator: "/")
        if
            let filter = endpoint.queryItems
                .first?.name
        {
            identifier += "?\(filter)"
        }
        invalidatedReads.append(identifier)
    }
}
