import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue contract")
struct GitLabIssueTests {
    @Test("Decodes optional fields and confidential issues")
    func decodesIssue() throws {
        let data = Data(
            """
            {
              "id": 101,
              "iid": 7,
              "project_id": 42,
              "title": "Private incident",
              "description": null,
              "state": "opened",
              "confidential": true,
              "labels": [],
              "author": {
                "id": 1,
                "username": "octocat",
                "name": "The Octocat",
                "avatar_url": null,
                "web_url": "https://gitlab.example.com/octocat"
              },
              "assignees": [],
              "milestone": null,
              "due_date": null,
              "user_notes_count": 0,
              "created_at": "2026-07-20T12:00:00.000Z",
              "updated_at": "2026-07-27T12:30:00.123Z",
              "closed_at": null,
              "web_url": "https://gitlab.example.com/group/project/-/issues/7",
              "references": {
                "short": "#7",
                "relative": "group/project#7",
                "full": "group/project#7"
              }
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let issue = try decoder.decode(GitLabIssue.self, from: data)

        #expect(issue.route == GitLabIssueRoute(projectID: 42, issueIID: 7))
        #expect(issue.confidential)
        #expect(issue.description == nil)
        #expect(issue.assignees.isEmpty)
        #expect(issue.milestone == nil)
        #expect(issue.dueDate == nil)
        #expect(issue.closedAt == nil)
        #expect(issue.safeWebURL?.scheme == "https")
    }

    @Test("Uses project ID and IID for route identity")
    func identifiesIssueRoutes() {
        let first = makeTestIssue(
            id: 101,
            iid: 7,
            projectID: 42
        )
        let sameIIDInAnotherProject = makeTestIssue(
            id: 202,
            iid: 7,
            projectID: 84
        )
        let anotherIID = makeTestIssue(
            id: 203,
            iid: 8,
            projectID: 42
        )

        #expect(first.route != sameIIDInAnotherProject.route)
        #expect(first.route != anotherIID.route)
    }

    @Test("Reuses normalized GitLab user presentation")
    func normalizesIssueUsers() {
        let namedUser = makeTestIssueUser(
            username: "octocat",
            name: "  The Octocat  "
        )
        let usernameOnlyUser = makeTestIssueUser(
            username: "  monalisa  ",
            name: " \n "
        )

        #expect(namedUser.displayName == "The Octocat")
        #expect(namedUser.summary.avatarInitial == "T")
        #expect(usernameOnlyUser.displayName == "monalisa")
        #expect(usernameOnlyUser.summary.avatarInitial == "M")
    }

    @Test(
        "Maps issue states to stable presentation kinds",
        arguments: [
            ("opened", GitLabIssueStateKind.opened, "Opened"),
            (" CLOSED ", GitLabIssueStateKind.closed, "Closed"),
            ("blocked", GitLabIssueStateKind.unknown, "Blocked"),
            (" ", GitLabIssueStateKind.unknown, "Unknown"),
        ]
    )
    func mapsIssueStates(
        state: String,
        expectedKind: GitLabIssueStateKind,
        expectedTitle: String
    ) {
        let issue = makeTestIssue(state: state)

        #expect(issue.stateKind == expectedKind)
        #expect(issue.stateTitle == expectedTitle)
    }

    @Test(
        "Maps issue states to official GitLab icons",
        arguments: [
            (
                GitLabIssueStateKind.opened,
                GitLabIcon.workItemIssue
            ),
            (.closed, .issueClosed),
        ]
    )
    func mapsIssueIcons(
        state: GitLabIssueStateKind,
        expectedIcon: GitLabIcon
    ) {
        #expect(state.gitLabIcon == expectedIcon)
    }

    @Test("Rejects non-HTTPS issue web URLs")
    func validatesWebURL() {
        let insecure = makeTestIssue(
            webURL: URL(
                string: "http://gitlab.example.com/group/project/-/issues/7"
            )
        )
        let credentialBearing = makeTestIssue(
            webURL: URL(
                string:
                    "https://user@gitlab.example.com/group/project/-/issues/7"
            )
        )

        #expect(insecure.safeWebURL == nil)
        #expect(credentialBearing.safeWebURL == nil)
    }
}
