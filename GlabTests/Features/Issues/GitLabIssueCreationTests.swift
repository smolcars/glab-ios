import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue creation values")
struct GitLabIssueCreationTests {
    @Test(
        "Rejects a missing project",
        arguments: [
            nil,
            0,
            -1,
        ] as [Int?]
    )
    func rejectsMissingProject(
        _ projectID: Int?
    ) {
        #expect(
            throws:
                GitLabIssueCreationValidationError
                    .missingProject
        ) {
            _ = try GitLabIssueCreationInput(
                projectID: projectID,
                title: "Issue"
            )
        }
    }

    @Test(
        "Rejects a whitespace-only title",
        arguments: [
            "",
            " ",
            "\n\t",
        ]
    )
    func rejectsEmptyTitle(_ title: String) {
        #expect(
            throws:
                GitLabIssueCreationValidationError
                    .emptyTitle
        ) {
            _ = try GitLabIssueCreationInput(
                projectID: 42,
                title: title
            )
        }
    }

    @Test("Accepts the documented description boundary")
    func acceptsMaximumDescription() throws {
        let description = String(
            repeating: "a",
            count:
                GitLabIssueCreationInput
                    .maximumDescriptionLength
        )

        let input = try GitLabIssueCreationInput(
            projectID: 42,
            title: "Boundary",
            description: description
        )

        #expect(
            input.rawDescription.count
                == GitLabIssueCreationInput
                    .maximumDescriptionLength
        )
    }

    @Test("Counts Unicode characters instead of UTF-8 bytes")
    func countsUnicodeCharacters() throws {
        let description =
            String(
                repeating: "a",
                count:
                    GitLabIssueCreationInput
                    .maximumDescriptionLength
                    - 1
            )
            + "👩🏽‍💻"

        let input = try GitLabIssueCreationInput(
            projectID: 42,
            title: "Unicode",
            description: description
        )

        #expect(
            input.rawDescription.count
                == GitLabIssueCreationInput
                    .maximumDescriptionLength
        )
        #expect(
            input.rawDescription.utf8.count
                != input.rawDescription.count
        )
    }

    @Test("Rejects an over-limit description")
    func rejectsLongDescription() {
        let description = String(
            repeating: "a",
            count:
                GitLabIssueCreationInput
                    .maximumDescriptionLength
                    + 1
        )

        #expect(
            throws:
                GitLabIssueCreationValidationError
                    .descriptionTooLong(
                        maximum:
                            GitLabIssueCreationInput
                            .maximumDescriptionLength
                    )
        ) {
            _ = try GitLabIssueCreationInput(
                projectID: 42,
                title: "Too long",
                description: description
            )
        }
    }

    @Test("Rejects invalid assignee identities")
    func rejectsInvalidAssignee() {
        #expect(
            throws:
                GitLabIssueCreationValidationError
                    .invalidAssignee
        ) {
            _ = try GitLabIssueCreationInput(
                projectID: 42,
                title: "Issue",
                assigneeIDs: [7, 0]
            )
        }
    }

    @Test(
        "Formats valid due dates",
        arguments: [
            (
                GitLabIssueDueDate(
                    year: 2026,
                    month: 1,
                    day: 2
                ),
                "2026-01-02"
            ),
            (
                GitLabIssueDueDate(
                    year: 2024,
                    month: 2,
                    day: 29
                ),
                "2024-02-29"
            ),
        ]
    )
    func formatsDueDate(
        _ dueDate: GitLabIssueDueDate,
        expected: String
    ) {
        #expect(dueDate.apiValue == expected)
    }

    @Test(
        "Rejects impossible due dates",
        arguments: [
            GitLabIssueDueDate(
                year: 2025,
                month: 2,
                day: 29
            ),
            GitLabIssueDueDate(
                year: 2026,
                month: 13,
                day: 1
            ),
            GitLabIssueDueDate(
                year: 2026,
                month: 4,
                day: 31
            ),
        ]
    )
    func rejectsInvalidDueDate(
        _ dueDate: GitLabIssueDueDate
    ) {
        #expect(dueDate.apiValue == nil)
    }

    @Test("Redacts issue content from descriptions")
    func redactsDescriptions() throws {
        let secret = "private-issue-content"
        let input = try GitLabIssueCreationInput(
            projectID: 42,
            title: secret,
            description: secret,
            labelNames: [secret]
        )

        #expect(
            !String(describing: input)
                .contains(secret)
        )
        #expect(
            !String(reflecting: input)
                .contains(secret)
        )

        for error in [
            GitLabIssueCreationValidationError
                .missingProject,
            .emptyTitle,
            .descriptionTooLong(
                maximum:
                    GitLabIssueCreationInput
                    .maximumDescriptionLength
            ),
            .invalidAssignee,
            .invalidDueDate,
        ] {
            #expect(
                !error.description
                    .contains(secret)
            )
            #expect(
                error.debugDescription
                    == error.description
            )
        }
    }

    @Test(
        "Classifies create failures without automatic certainty",
        arguments: [
            (
                GitLabSessionClientError
                    .api(.validation(statusCode: 422)),
                GitLabMutationDeliveryCertainty
                    .rejected
            ),
            (
                GitLabSessionClientError
                    .api(.forbidden),
                GitLabMutationDeliveryCertainty
                    .rejected
            ),
            (
                GitLabSessionClientError
                    .api(.rateLimited(retryAfterSeconds: 30)),
                GitLabMutationDeliveryCertainty
                    .deliveryUnknown
            ),
            (
                GitLabSessionClientError
                    .api(.cancelled),
                GitLabMutationDeliveryCertainty
                    .deliveryUnknown
            ),
            (
                GitLabSessionClientError
                    .api(.server(statusCode: 500)),
                GitLabMutationDeliveryCertainty
                    .deliveryUnknown
            ),
        ]
    )
    func classifiesMutationFailure(
        _ error: GitLabSessionClientError,
        expected:
            GitLabMutationDeliveryCertainty
    ) {
        #expect(
            error.mutationDeliveryCertainty
                == expected
        )
    }
}

@Suite("GitLab issue creation metadata")
struct GitLabIssueCreationMetadataTests {
    @Test("Decodes old and new project label responses")
    func decodesLabels() throws {
        let labels = try decoder.decode(
            [GitLabProjectLabel].self,
            from: Data(
                """
                [
                  {
                    "id": 1,
                    "name": "bug",
                    "color": "#FF0000",
                    "text_color": "#FFFFFF",
                    "description": "A bug",
                    "archived": false
                  },
                  {
                    "id": 2,
                    "name": "legacy",
                    "color": "#123456",
                    "text_color": null,
                    "description": null
                  }
                ]
                """.utf8
            )
        )

        #expect(labels[0].archived == false)
        #expect(labels[1].archived == nil)
        #expect(labels[1].textColor == nil)
    }

    @Test("Decodes inherited project members")
    func decodesMembers() throws {
        let members = try decoder.decode(
            [GitLabProjectMember].self,
            from: Data(
                """
                [
                  {
                    "id": 7,
                    "username": "octocat",
                    "name": "The Octocat",
                    "state": "active",
                    "avatar_url": null,
                    "web_url": "https://gitlab.example.com/octocat",
                    "access_level": 30
                  }
                ]
                """.utf8
            )
        )

        #expect(members[0].id == 7)
        #expect(members[0].isActive)
        #expect(members[0].accessLevel == 30)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
