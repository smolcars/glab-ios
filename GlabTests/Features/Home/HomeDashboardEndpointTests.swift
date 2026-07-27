import Foundation
import Testing
@testable import Glab

@Suite("Home dashboard endpoints")
struct HomeDashboardEndpointTests {
    @Test("Builds the current-user request")
    func buildsCurrentUserRequest() throws {
        let url = try requestURL(HomeDashboardEndpoints.currentUser)

        #expect(url.path == "/company/api/v4/user")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query == nil)
    }

    @Test("Builds assigned issue preview sorting")
    func buildsAssignedIssueRequest() throws {
        let url = try requestURL(HomeDashboardEndpoints.assignedIssues)

        #expect(url.path == "/company/api/v4/issues")
        #expect(
            query(from: url)
                == [
                    "scope": "assigned_to_me",
                    "state": "opened",
                    "order_by": "updated_at",
                    "sort": "desc",
                    "per_page": "3",
                ]
        )
    }

    @Test("Builds assigned and review-requested merge request previews")
    func buildsMergeRequestRequests() throws {
        let assignedURL = try requestURL(
            HomeDashboardEndpoints.assignedMergeRequests
        )
        let reviewURL = try requestURL(
            HomeDashboardEndpoints.reviewRequests
        )

        #expect(assignedURL.path == "/company/api/v4/merge_requests")
        #expect(reviewURL.path == "/company/api/v4/merge_requests")
        #expect(
            query(from: assignedURL)
                == [
                    "scope": "assigned_to_me",
                    "state": "opened",
                    "order_by": "updated_at",
                    "sort": "desc",
                    "per_page": "3",
                ]
        )
        #expect(
            query(from: reviewURL)
                == [
                    "scope": "reviews_for_me",
                    "state": "opened",
                    "order_by": "updated_at",
                    "sort": "desc",
                    "per_page": "3",
                ]
        )
    }

    @Test("Builds recent-member and starred project previews")
    func buildsProjectRequests() throws {
        let recentURL = try requestURL(
            HomeDashboardEndpoints.recentProjects
        )
        let starredURL = try requestURL(
            HomeDashboardEndpoints.starredProjects
        )

        #expect(recentURL.path == "/company/api/v4/projects")
        #expect(starredURL.path == "/company/api/v4/projects")
        #expect(
            query(from: recentURL)
                == [
                    "membership": "true",
                    "order_by": "last_activity_at",
                    "sort": "desc",
                    "simple": "true",
                    "per_page": "3",
                ]
        )
        #expect(
            query(from: starredURL)
                == [
                    "starred": "true",
                    "order_by": "last_activity_at",
                    "sort": "desc",
                    "simple": "true",
                    "per_page": "3",
                ]
        )
    }
}

private extension HomeDashboardEndpointTests {
    func requestURL<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URL {
        let request = try GitLabRequestBuilder(
            host: GitLabHost("https://gitlab.example.com/company"),
            authorization: .personalAccessToken("secret")
        )
        .build(endpoint)

        return try #require(request.url)
    }

    func query(from url: URL) -> [String: String] {
        let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?
        .queryItems ?? []

        return Dictionary(
            uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }
        )
    }
}
