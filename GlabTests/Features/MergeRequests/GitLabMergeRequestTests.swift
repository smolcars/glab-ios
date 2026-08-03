import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request contract")
struct GitLabMergeRequestTests {
    @Test("Decodes merge request list and detail fields")
    func decodesMergeRequest() throws {
        let mergeRequest = try decodeMergeRequest(
            draftFields: #""draft": true,"#,
            revisionFields:
                """
                "sha": "fallback-head",
                "diff_refs": {
                  "base_sha": "base-sha",
                  "start_sha": "start-sha",
                  "head_sha": "head-sha"
                },
                "changes_count": "1000+",
                """
        )

        #expect(
            mergeRequest.route
                == GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                )
        )
        #expect(mergeRequest.isDraft)
        #expect(mergeRequest.description == nil)
        #expect(mergeRequest.labels.isEmpty)
        #expect(mergeRequest.assignees.isEmpty)
        #expect(mergeRequest.reviewers.isEmpty)
        #expect(mergeRequest.closedAt == nil)
        #expect(mergeRequest.mergedAt == nil)
        #expect(mergeRequest.safeWebURL?.scheme == "https")
        #expect(
            mergeRequest.safeChangesURL?
                .absoluteString
                == "https://gitlab.example.com/group/project/"
                    + "-/merge_requests/7/diffs"
        )
        #expect(
            mergeRequest.diffRefs
                == GitLabMergeRequestDiffRefs(
                    baseSHA: "base-sha",
                    startSHA: "start-sha",
                    headSHA: "head-sha"
                )
        )
        #expect(mergeRequest.diffHeadSHA == "head-sha")
        #expect(mergeRequest.changesCount == "1000+")
    }

    @Test("Uses legacy work-in-progress only when draft is absent")
    func decodesDraftCompatibility() throws {
        let current = try decodeMergeRequest(
            draftFields:
                #""draft": false, "work_in_progress": true,"#
        )
        let legacy = try decodeMergeRequest(
            draftFields: #""work_in_progress": true,"#
        )
        let missing = try decodeMergeRequest(draftFields: "")

        #expect(!current.isDraft)
        #expect(legacy.isDraft)
        #expect(!missing.isDraft)
    }

    @Test("Normalizes and falls back across diff head fields")
    func normalizesDiffHead() throws {
        let preferred = try decodeMergeRequest(
            draftFields: "",
            revisionFields:
                """
                "sha": " fallback-head ",
                "diff_refs": {
                  "base_sha": "base",
                  "start_sha": "start",
                  "head_sha": " preferred-head "
                },
                """
        )
        let fallback = try decodeMergeRequest(
            draftFields: "",
            revisionFields:
                """
                "sha": " fallback-head ",
                "diff_refs": {
                  "base_sha": "base",
                  "start_sha": "start",
                  "head_sha": "   "
                },
                """
        )
        let preparing = try decodeMergeRequest(
            draftFields: "",
            revisionFields:
                """
                "sha": " ",
                "diff_refs": null,
                "changes_count": null,
                """
        )

        #expect(
            preferred.diffHeadSHA
                == "preferred-head"
        )
        #expect(
            fallback.diffHeadSHA
                == "fallback-head"
        )
        #expect(preparing.diffHeadSHA == nil)
        #expect(preparing.changesCount == nil)
    }

    @Test("Decodes defensive merge readiness fields")
    func decodesReadinessFields() throws {
        let mergeRequest = try decodeMergeRequest(
            draftFields: #""draft": false,"#,
            revisionFields:
                """
                "detailed_merge_status": "ci_still_running",
                "has_conflicts": false,
                "blocking_discussions_resolved": true,
                "head_pipeline": {
                  "id": 501,
                  "status": "running",
                  "web_url": "https://gitlab.example.com/group/project/-/pipelines/501"
                },
                """
        )

        #expect(
            mergeRequest.detailedMergeStatus
                == "ci_still_running"
        )
        #expect(mergeRequest.hasConflicts == false)
        #expect(
            mergeRequest
                .blockingDiscussionsResolved
                == true
        )
        #expect(
            mergeRequest.headPipeline
                == GitLabMergeRequestHeadPipeline(
                    id: 501,
                    status: "running",
                    webURL: URL(
                        string:
                            "https://gitlab.example.com/group/project/-/pipelines/501"
                    )
                )
        )
        #expect(
            mergeRequest.headPipeline?
                .safeWebURL != nil
        )
    }

    @Test("Decodes merge permission and auto-merge state")
    func decodesMergeActionFields() throws {
        let mergeRequest = try decodeMergeRequest(
            draftFields: #""draft": false,"#,
            revisionFields:
                """
                "merge_when_pipeline_succeeds": true,
                "user": {
                  "can_merge": true
                },
                """
        )

        #expect(
            mergeRequest
                .mergeWhenPipelineSucceeds == true
        )
        #expect(
            mergeRequest
                .userPermissions?
                .canMerge == true
        )
    }

    @Test("Keeps older merge action fields optional")
    func decodesMissingMergeActionFields() throws {
        let mergeRequest = try decodeMergeRequest(
            draftFields: #""draft": false,"#
        )

        #expect(
            mergeRequest
                .mergeWhenPipelineSucceeds == nil
        )
        #expect(
            mergeRequest.userPermissions == nil
        )
    }

    @Test("Keeps missing and future readiness fields decodable")
    func decodesMissingReadinessFields() throws {
        let missing = try decodeMergeRequest(
            draftFields: ""
        )
        let future = try decodeMergeRequest(
            draftFields: #""draft": false,"#,
            revisionFields:
                """
                "detailed_merge_status": "future_status",
                "has_conflicts": null,
                "blocking_discussions_resolved": null,
                "head_pipeline": {
                  "id": 502,
                  "status": "future_pipeline",
                  "web_url": "http://gitlab.example.com/unsafe"
                },
                """
        )

        #expect(missing.detailedMergeStatus == nil)
        #expect(missing.hasConflicts == nil)
        #expect(
            missing.blockingDiscussionsResolved
                == nil
        )
        #expect(missing.headPipeline == nil)
        #expect(
            future.detailedMergeStatus
                == "future_status"
        )
        #expect(
            future.headPipeline?.status
                == "future_pipeline"
        )
        #expect(
            future.headPipeline?
                .safeWebURL == nil
        )
    }

    @Test("Uses project ID and IID for route identity")
    func identifiesRoutes() {
        let first = makeTestMergeRequest(
            id: 101,
            iid: 7,
            projectID: 42
        )
        let sameIIDInAnotherProject = makeTestMergeRequest(
            id: 202,
            iid: 7,
            projectID: 84
        )
        let anotherIID = makeTestMergeRequest(
            id: 203,
            iid: 8,
            projectID: 42
        )

        #expect(first.route != sameIIDInAnotherProject.route)
        #expect(first.route != anotherIID.route)
    }

    @Test(
        "Maps merge request states to stable presentation kinds",
        arguments: [
            ("opened", GitLabMergeRequestStateKind.opened, "Opened"),
            (" CLOSED ", GitLabMergeRequestStateKind.closed, "Closed"),
            ("merged", GitLabMergeRequestStateKind.merged, "Merged"),
            ("locked", GitLabMergeRequestStateKind.locked, "Locked"),
            ("checking", GitLabMergeRequestStateKind.unknown, "Checking"),
            (" ", GitLabMergeRequestStateKind.unknown, "Unknown"),
        ]
    )
    func mapsStates(
        state: String,
        expectedKind: GitLabMergeRequestStateKind,
        expectedTitle: String
    ) {
        let mergeRequest = makeTestMergeRequest(state: state)

        #expect(mergeRequest.stateKind == expectedKind)
        #expect(mergeRequest.stateTitle == expectedTitle)
    }

    @Test(
        "Maps merge request states to official GitLab icons",
        arguments: [
            (
                GitLabMergeRequestStateKind.opened,
                GitLabIcon.mergeRequestOpen
            ),
            (.closed, .mergeRequestClosed),
            (.merged, .merged),
        ]
    )
    func mapsStateIcons(
        state: GitLabMergeRequestStateKind,
        expectedIcon: GitLabIcon
    ) {
        #expect(state.gitLabIcon == expectedIcon)
    }

    @Test("Rejects unsafe merge request web URLs")
    func validatesWebURL() {
        let insecure = makeTestMergeRequest(
            webURL: URL(
                string:
                    "http://gitlab.example.com/group/project/-/merge_requests/7"
            )
        )
        let credentialBearing = makeTestMergeRequest(
            webURL: URL(
                string:
                    "https://user@gitlab.example.com/group/project/"
                    + "-/merge_requests/7"
            )
        )

        #expect(insecure.safeWebURL == nil)
        #expect(credentialBearing.safeWebURL == nil)
        #expect(insecure.safeChangesURL == nil)
        #expect(credentialBearing.safeChangesURL == nil)
    }
}

private extension GitLabMergeRequestTests {
    func decodeMergeRequest(
        draftFields: String,
        revisionFields: String = ""
    ) throws -> GitLabMergeRequest {
        let data = Data(
            """
            {
              "id": 101,
              "iid": 7,
              "project_id": 42,
              "title": "Review pagination",
              "description": null,
              "state": "opened",
              \(draftFields)
              \(revisionFields)
              "labels": [],
              "author": {
                "id": 1,
                "username": "octocat",
                "name": "The Octocat",
                "avatar_url": null,
                "web_url": "https://gitlab.example.com/octocat"
              },
              "assignees": [],
              "reviewers": [],
              "source_branch": "feature/pagination",
              "target_branch": "main",
              "user_notes_count": 0,
              "created_at": "2026-07-20T12:00:00.000Z",
              "updated_at": "2026-07-27T12:30:00.123Z",
              "closed_at": null,
              "merged_at": null,
              "web_url": "https://gitlab.example.com/group/project/-/merge_requests/7",
              "references": {
                "short": "!7",
                "relative": "group/project!7",
                "full": "group/project!7"
              }
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            GitLabMergeRequest.self,
            from: data
        )
    }
}
