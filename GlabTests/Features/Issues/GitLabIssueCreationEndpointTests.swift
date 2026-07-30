import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue creation endpoints")
struct GitLabIssueCreationEndpointTests {
    @Test("Builds the initial membership project query")
    func buildsInitialProjectQuery() throws {
        let endpoint =
            GitLabProjectEndpoints.issueCreationProjects(
                search: nil
            )
        let request = try buildRequest(endpoint)

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/projects"
                + "?membership=true&archived=false"
                + "&order_by=last_activity_at&sort=desc"
                + "&simple=true&per_page=20"
        )
    }

    @Test("Builds a normalized server project search")
    func buildsProjectSearch() throws {
        let endpoint =
            GitLabProjectEndpoints.issueCreationProjects(
                search: "  wallet service  "
            )
        let request = try buildRequest(endpoint)

        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/projects"
                + "?membership=true&archived=false"
                + "&order_by=last_activity_at&sort=desc"
                + "&simple=true&per_page=20"
                + "&search=wallet%20service"
        )
    }

    @Test("Builds project label and inherited member queries")
    func buildsProjectMetadataQueries() throws {
        let labels =
            GitLabIssueCreationEndpoints.labels(
                projectID: 42
            )
        let members =
            GitLabProjectMemberEndpoints.members(
                projectID: 42
            )

        #expect(labels.requiredAccess == .read)
        #expect(members.requiredAccess == .read)
        #expect(
            try buildRequest(labels).url?
                .absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/labels"
                + "?with_counts=false"
                + "&include_ancestor_groups=true"
                + "&per_page=20"
        )
        #expect(
            try buildRequest(members).url?
                .absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/members/all"
                + "?per_page=20"
        )
    }

    @Test("Builds milestone, iteration, and status option queries")
    func buildsIssueFieldOptionQueries() throws {
        let milestones =
            GitLabIssueCreationEndpoints
                .milestones(projectID: 42)
        let iterations =
            GitLabIssueCreationEndpoints
                .iterations(projectID: 42)
        let statuses =
            try GitLabIssueCreationEndpoints
                .statuses(
                    projectPath:
                        "group/project"
                )

        #expect(
            try buildRequest(milestones)
                .url?.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/milestones"
                + "?state=active"
                + "&include_ancestors=true"
                + "&per_page=100"
        )
        #expect(
            try buildRequest(iterations)
                .url?.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/iterations"
                + "?state=opened"
                + "&include_ancestors=true"
                + "&per_page=100"
        )
        let statusJSON =
            try jsonObject(
                buildRequest(statuses)
            )
        let variables = try #require(
            statusJSON["variables"]
                as? [String: String]
        )
        #expect(
            variables["projectPath"]
                == "group/project"
        )
        #expect(
            (statusJSON["query"] as? String)?
                .contains(
                    "allowedStatuses"
                ) == true
        )
    }

    @Test("Builds normalized server metadata searches")
    func buildsProjectMetadataSearches() throws {
        let labels =
            GitLabIssueCreationEndpoints.labels(
                projectID: 42,
                search: "  needs QA 👩🏽‍💻  "
            )
        let members =
            GitLabProjectMemberEndpoints.members(
                projectID: 42,
                search: "  helper bot  "
            )

        #expect(
            try buildRequest(labels).url?
                .absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/labels"
                + "?with_counts=false"
                + "&include_ancestor_groups=true"
                + "&per_page=20"
                + "&search=needs%20QA%20%F0%9F%91%A9%F0%9F%8F%BD%E2%80%8D%F0%9F%92%BB"
        )
        #expect(
            try buildRequest(members).url?
                .absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/members/all"
                + "?per_page=20"
                + "&query=helper%20bot"
        )
    }

    @Test("Omits blank metadata searches")
    func omitsBlankMetadataSearches() throws {
        let labels =
            GitLabIssueCreationEndpoints.labels(
                projectID: 42,
                search: " \n "
            )
        let members =
            GitLabProjectMemberEndpoints.members(
                projectID: 42,
                search: "\t"
            )

        #expect(
            labels.queryItems
                .contains(where: {
                    $0.name == "search"
                }) == false
        )
        #expect(
            members.queryItems
                .contains(where: {
                    $0.name == "query"
                }) == false
        )
    }

    @Test("Builds a minimal title-only issue")
    func buildsMinimalIssue() throws {
        let input = try GitLabIssueCreationInput(
            projectID: 42,
            title: "Fix pagination"
        )
        let endpoint =
            try GitLabIssueEndpoints.create(
                input
            )
        let request = try buildRequest(endpoint)
        let json = try jsonObject(request)

        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            request.url?.absoluteString
                == "https://gitlab.example.com/api/v4/"
                + "projects/42/issues"
        )
        #expect(json["title"] as? String == "Fix pagination")
        #expect(json["confidential"] as? Bool == false)
        #expect(json["description"] == nil)
        #expect(json["labels"] == nil)
        #expect(json["assignee_id"] == nil)
        #expect(json["assignee_ids"] == nil)
        #expect(json["due_date"] == nil)
    }

    @Test("Builds a complete Unicode issue with one assignee")
    func buildsCompleteSingleAssigneeIssue() throws {
        let input = try GitLabIssueCreationInput(
            projectID: 42,
            title: "  Preserve 👩🏽‍💻 title  ",
            description:
                "\r\n# Unicode 👩🏽‍💻\r\n\r\n- [ ] exact  \r\n",
            labelNames: [
                "team::mobile",
                "bug",
                "team::mobile",
            ],
            assigneeIDs: [7, 7],
            confidential: true,
            dueDate: GitLabIssueDueDate(
                year: 2026,
                month: 8,
                day: 3
            )
        )
        let request = try buildRequest(
            try GitLabIssueEndpoints.create(input)
        )
        let json = try jsonObject(request)

        #expect(
            json["title"] as? String
                == "  Preserve 👩🏽‍💻 title  "
        )
        #expect(
            json["description"] as? String
                == "\r\n# Unicode 👩🏽‍💻\r\n\r\n- [ ] exact  \r\n"
        )
        #expect(
            json["labels"] as? String
                == "team::mobile,bug"
        )
        #expect(json["assignee_id"] as? Int == 7)
        #expect(json["assignee_ids"] == nil)
        #expect(json["confidential"] as? Bool == true)
        #expect(json["due_date"] as? String == "2026-08-03")
    }

    @Test("Includes a selected milestone in REST creation")
    func buildsIssueWithMilestone() throws {
        let input =
            try GitLabIssueCreationInput(
                projectID: 42,
                title: "Ship it",
                milestone:
                    GitLabIssueMilestone(
                        id: 19,
                        iid: 3,
                        title: "1.0",
                        state: "active",
                        startDate:
                            "2026-07-01",
                        dueDate:
                            "2026-08-01"
                    )
            )
        let json = try jsonObject(
            buildRequest(
                try GitLabIssueEndpoints
                    .create(input)
            )
        )

        #expect(
            json["milestone_id"]
                as? Int == 19
        )
    }

    @Test("Builds GraphQL creation fields with global IDs")
    func buildsGraphQLIssueFields() throws {
        let status =
            GitLabIssueWorkItemStatus(
                id:
                    "gid://gitlab/WorkItems::Statuses::SystemDefined::Status/7",
                name: "In progress",
                description: nil,
                iconName: nil,
                color: nil,
                position: 2,
                category: .inProgress
            )
        let input =
            try GitLabIssueCreationInput(
                projectID: 42,
                projectPath:
                    "group/project",
                title: "Plan the release",
                assigneeIDs: [9],
                status: status,
                milestone:
                    GitLabIssueMilestone(
                        id: 19,
                        iid: 3,
                        title: "1.0",
                        state: "active",
                        startDate: nil,
                        dueDate: nil
                    ),
                iteration:
                    GitLabIssueIteration(
                        id: 23,
                        iid: 5,
                        title: "Sprint 5",
                        state: 1,
                        startDate: nil,
                        dueDate: nil
                    )
            )
        let endpoint =
            try GitLabIssueEndpoints
                .createWithWorkItemFields(
                    input
                )
        let json = try jsonObject(
            buildRequest(endpoint)
        )
        let variables = try #require(
            json["variables"]
                as? [String: Any]
        )

        #expect(
            endpoint.requiredAccess == .write
        )
        #expect(
            variables["projectPath"]
                as? String
                == "group/project"
        )
        #expect(
            variables["milestoneID"]
                as? String
                == "gid://gitlab/Milestone/19"
        )
        #expect(
            variables["iterationID"]
                as? String
                == "gid://gitlab/Iteration/23"
        )
        #expect(
            variables["statusID"]
                as? String == status.id
        )
        #expect(
            variables["assigneeIDs"]
                as? [String]
                == ["gid://gitlab/User/9"]
        )
        #expect(
            (json["query"] as? String)?
                .contains("createIssue")
                == true
        )
    }

    @Test("Uses only the paid multi-assignee body shape")
    func buildsMultipleAssignees() throws {
        let input = try GitLabIssueCreationInput(
            projectID: 42,
            title: "Shared ownership",
            assigneeIDs: [7, 9, 7, 11]
        )
        let json = try jsonObject(
            buildRequest(
                try GitLabIssueEndpoints.create(input)
            )
        )

        #expect(json["assignee_id"] == nil)
        #expect(
            json["assignee_ids"] as? [Int]
                == [7, 9, 11]
        )
    }
}

private extension GitLabIssueCreationEndpointTests {
    nonisolated func buildRequest<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws -> URLRequest {
        try GitLabRequestBuilder(
            host: GitLabHost("gitlab.example.com"),
            authorization:
                .personalAccessToken("pat-secret")
        ).build(endpoint)
    }

    nonisolated func jsonObject(
        _ request: URLRequest
    ) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(
            JSONSerialization.jsonObject(
                with: body
            ) as? [String: Any]
        )
    }
}
