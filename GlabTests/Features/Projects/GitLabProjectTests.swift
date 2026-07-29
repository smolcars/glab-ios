import Foundation
import Testing
@testable import Glab

@Suite("GitLab project contract")
struct GitLabProjectTests {
    @Test("Decodes project list presentation fields")
    func decodesProject() throws {
        let project = try decodeProject()

        #expect(project.id == 42)
        #expect(project.name == "Glab iOS")
        #expect(project.nameWithNamespace == "Mobile / Glab iOS")
        #expect(project.pathWithNamespace == "mobile/glab-ios")
        #expect(project.namespace?.fullPath == "mobile")
        #expect(project.visibility == .privateAccess)
        #expect(
            project.issuesAccessLevel == .enabled
        )
        #expect(
            project.mergeRequestsAccessLevel
                == .enabled
        )
        #expect(project.visibility.title == "Private")
        #expect(project.starCount == 17)
        #expect(
            project.lastActivityAt
                == Date(timeIntervalSince1970: 1_784_980_800)
        )
        #expect(project.safeAvatarURL?.scheme == "https")
        #expect(project.safeWebURL?.scheme == "https")
        #expect(project.avatarMark == "GI")
    }

    @Test(
        "Maps project merge request access without rejecting future values",
        arguments: [
            (
                "disabled",
                GitLabProjectFeatureAccessLevel
                    .disabled,
                true
            ),
            (
                "private",
                GitLabProjectFeatureAccessLevel
                    .privateAccess,
                false
            ),
            (
                "enabled",
                GitLabProjectFeatureAccessLevel
                    .enabled,
                false
            ),
            (
                "restricted",
                GitLabProjectFeatureAccessLevel
                    .unknown("restricted"),
                false
            ),
        ]
    )
    func mapsMergeRequestAccess(
        value: String,
        expected:
            GitLabProjectFeatureAccessLevel,
        isDisabled: Bool
    ) throws {
        let project = try decodeProject(
            mergeRequestsAccessLevel: value
        )

        #expect(
            project.mergeRequestsAccessLevel
                == expected
        )
        #expect(
            project.mergeRequestsAccessLevel?
                .isDisabled == isDisabled
        )
    }

    @Test(
        "Maps project issues access without rejecting future values",
        arguments: [
            (
                "disabled",
                GitLabProjectFeatureAccessLevel
                    .disabled,
                true
            ),
            (
                "private",
                GitLabProjectFeatureAccessLevel
                    .privateAccess,
                false
            ),
            (
                "enabled",
                GitLabProjectFeatureAccessLevel
                    .enabled,
                false
            ),
            (
                "restricted",
                GitLabProjectFeatureAccessLevel
                    .unknown("restricted"),
                false
            ),
        ]
    )
    func mapsIssuesAccess(
        value: String,
        expected:
            GitLabProjectFeatureAccessLevel,
        isDisabled: Bool
    ) throws {
        let project = try decodeProject(
            issuesAccessLevel: value
        )

        #expect(
            project.issuesAccessLevel
                == expected
        )
        #expect(
            project.issuesAccessLevel?
                .isDisabled == isDisabled
        )
    }

    @Test("Decodes missing optional project presentation data")
    func decodesMissingOptionalData() throws {
        let project = try decodeProject(
            namespace: "null",
            avatarURL: "null"
        )

        #expect(project.namespace == nil)
        #expect(project.safeAvatarURL == nil)
        #expect(project.namespaceTitle == "mobile")
    }

    @Test(
        "Maps project visibility without rejecting future values",
        arguments: [
            (
                "private",
                GitLabProjectVisibility.privateAccess,
                "Private"
            ),
            (
                "internal",
                GitLabProjectVisibility.internalAccess,
                "Internal"
            ),
            (
                "public",
                GitLabProjectVisibility.publicAccess,
                "Public"
            ),
            (
                "partner",
                GitLabProjectVisibility.unknown("partner"),
                "Partner"
            ),
            (
                " ",
                GitLabProjectVisibility.unknown(""),
                "Unknown"
            ),
        ]
    )
    func mapsVisibility(
        value: String,
        expected: GitLabProjectVisibility,
        title: String
    ) throws {
        let project = try decodeProject(
            visibility: value
        )

        #expect(project.visibility == expected)
        #expect(project.visibility.title == title)
    }

    @Test("Rejects unsafe project and avatar URLs")
    func validatesURLs() {
        let project = makeTestProject(
            webURL: URL(
                string:
                    "http://gitlab.example.com/mobile/glab-ios"
            ),
            avatarURL: URL(
                string:
                    "https://user@gitlab.example.com/uploads/avatar.png"
            )
        )

        #expect(project.safeWebURL == nil)
        #expect(project.safeAvatarURL == nil)
    }

    @Test(
        "Builds stable project fallback marks",
        arguments: [
            ("GitLab Core", "GC"),
            ("glab-ios", "GI"),
            ("Runner", "RU"),
            ("42", "42"),
            ("💎", "GL"),
        ]
    )
    func buildsAvatarMark(
        name: String,
        expected: String
    ) {
        #expect(
            makeTestProject(name: name).avatarMark
                == expected
        )
    }
}

private extension GitLabProjectTests {
    func decodeProject(
        visibility: String = "private",
        issuesAccessLevel: String =
            "enabled",
        mergeRequestsAccessLevel: String =
            "enabled",
        namespace: String = """
            {
              "id": 7,
              "name": "Mobile",
              "path": "mobile",
              "kind": "group",
              "full_path": "mobile"
            }
            """,
        avatarURL: String =
            #""https://gitlab.example.com/uploads/avatar.png""#
    ) throws -> GitLabProject {
        let data = Data(
            """
            {
              "id": 42,
              "name": "Glab iOS",
              "name_with_namespace": "Mobile / Glab iOS",
              "path_with_namespace": "mobile/glab-ios",
              "web_url": "https://gitlab.example.com/mobile/glab-ios",
              "avatar_url": \(avatarURL),
              "star_count": 17,
              "last_activity_at": "2026-07-25T12:00:00Z",
              "visibility": "\(visibility)",
              "issues_access_level": "\(issuesAccessLevel)",
              "merge_requests_access_level": "\(mergeRequestsAccessLevel)",
              "namespace": \(namespace)
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            GitLabProject.self,
            from: data
        )
    }
}
