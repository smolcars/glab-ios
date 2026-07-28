import Foundation
import Testing
@testable import Glab

@Suite("GitLab resource edit validation")
struct GitLabResourceEditValidationTests {
    @Test("Builds exact issue and merge request snapshots")
    func buildsResourceSnapshots() {
        let issueUpdatedAt =
            Date(
                timeIntervalSince1970:
                    1_700_000_100
            )
        let issue = makeTestIssue(
            iid: 9,
            projectID: 72,
            title: "  Issue title  ",
            description: nil,
            updatedAt: issueUpdatedAt
        )
        let mergeRequestUpdatedAt =
            Date(
                timeIntervalSince1970:
                    1_700_000_200
            )
        let mergeRequest =
            makeTestMergeRequest(
                iid: 10,
                projectID: 73,
                title: "  MR title  ",
                description:
                    "\r\n# Exact 👩🏽‍💻\r\n",
                updatedAt:
                    mergeRequestUpdatedAt
            )

        let issueSnapshot =
            GitLabResourceEditSnapshot(
                issue: issue
            )
        let mergeRequestSnapshot =
            GitLabResourceEditSnapshot(
                mergeRequest: mergeRequest
            )

        #expect(
            issueSnapshot.target
                == GitLabResourceEditTarget
                .issue(issue.route)
        )
        #expect(issueSnapshot.resourceID == issue.id)
        #expect(
            issueSnapshot.title
                == "  Issue title  "
        )
        #expect(
            issueSnapshot.rawDescription
                == ""
        )
        #expect(
            issueSnapshot.updatedAt
                == issueUpdatedAt
        )
        #expect(
            mergeRequestSnapshot.target
                == GitLabResourceEditTarget
                .mergeRequest(
                    mergeRequest.route
                )
        )
        #expect(
            mergeRequestSnapshot.resourceID
                == mergeRequest.id
        )
        #expect(
            mergeRequestSnapshot.title
                == "  MR title  "
        )
        #expect(
            mergeRequestSnapshot
                .rawDescription
                == "\r\n# Exact 👩🏽‍💻\r\n"
        )
        #expect(
            mergeRequestSnapshot.updatedAt
                == mergeRequestUpdatedAt
        )
    }

    @Test("Preserves exact changed content")
    func preservesChangedContent() throws {
        let title = "  Preserve title spacing  "
        let description =
            "\r\n# Unicode 👩🏽‍💻\r\n\r\n- [ ] exact  \r\n"

        let changes = try GitLabResourceEditChanges(
            title: title,
            description: description
        )

        #expect(changes.title == title)
        #expect(changes.description == description)
    }

    @Test("Accepts the documented description boundary")
    func acceptsMaximumDescription() throws {
        let description = String(
            repeating: "a",
            count:
                GitLabResourceEditChanges
                    .maximumDescriptionLength
        )

        let changes = try GitLabResourceEditChanges(
            description: description
        )

        #expect(
            changes.description?.count
                == GitLabResourceEditChanges
                    .maximumDescriptionLength
        )
    }

    @Test("Counts Unicode characters rather than UTF-8 bytes")
    func countsUnicodeCharacters() throws {
        let description =
            String(
                repeating: "a",
                count:
                    GitLabResourceEditChanges
                        .maximumDescriptionLength
                    - 1
            )
            + "👩🏽‍💻"

        let changes = try GitLabResourceEditChanges(
            description: description
        )

        #expect(
            changes.description?.count
                == GitLabResourceEditChanges
                    .maximumDescriptionLength
        )
        #expect(
            changes.description?.utf8.count
                != changes.description?.count
        )
    }

    @Test("Rejects an over-limit description")
    func rejectsLongDescription() {
        let description = String(
            repeating: "a",
            count:
                GitLabResourceEditChanges
                    .maximumDescriptionLength
                    + 1
        )

        #expect(
            throws:
                GitLabResourceEditValidationError
                    .descriptionTooLong(
                        maximum:
                            GitLabResourceEditChanges
                                .maximumDescriptionLength
                    )
        ) {
            _ = try GitLabResourceEditChanges(
                description: description
            )
        }
    }

    @Test(
        "Rejects an empty changed title",
        arguments: [
            "",
            " ",
            "\n\t",
        ]
    )
    func rejectsEmptyTitle(_ title: String) {
        #expect(
            throws:
                GitLabResourceEditValidationError
                    .emptyTitle
        ) {
            _ = try GitLabResourceEditChanges(
                title: title
            )
        }
    }

    @Test("Rejects an update with no changed fields")
    func rejectsEmptyChanges() {
        #expect(
            throws:
                GitLabResourceEditValidationError
                    .noChanges
        ) {
            _ = try GitLabResourceEditChanges()
        }
    }

    @Test("Validation descriptions do not expose content")
    func redactsDescriptions() {
        for error in [
            GitLabResourceEditValidationError
                .emptyTitle,
            .descriptionTooLong(
                maximum:
                    GitLabResourceEditChanges
                        .maximumDescriptionLength
            ),
            .noChanges,
        ] {
            #expect(
                !error.description.contains(
                    "private-content"
                )
            )
            #expect(
                error.debugDescription
                    == error.description
            )
        }
    }
}
