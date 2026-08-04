import Foundation
import Testing
import UIKit
@testable import Glab

@Suite("GitLab user profiles")
struct GitLabUserProfileTests {
    @Test("Decodes public profile, status, and GPG key fields")
    func decodesPublicFields() throws {
        let profile = try makeTestUserProfile()
        let status = try JSONDecoder().decode(
            GitLabUserStatus.self,
            from: Data(
                #"{"emoji":"coffee","availability":"busy","message":"Heads down"}"#.utf8
            )
        )
        let key = try JSONDecoder().decode(
            GitLabUserGPGKey.self,
            from: Data(
                #"{"id":9,"key":"PUBLIC KEY","created_at":"2026-08-04T15:04:03.123Z"}"#.utf8
            )
        )

        #expect(profile.id == 42)
        #expect(profile.displayName == "Alex Example")
        #expect(profile.createdAt != nil)
        #expect(profile.bio == "Builds GitLab tools")
        #expect(profile.followers == 660)
        #expect(profile.following == 49)
        #expect(profile.isFollowed == false)
        #expect(profile.contacts.count == 6)
        #expect(status.emoji == "coffee")
        #expect(status.availability == "busy")
        #expect(status.message == "Heads down")
        #expect(key.id == 9)
        #expect(key.createdAt != nil)
    }

    @Test("Builds safe destinations for published contacts")
    func buildsContactDestinations() throws {
        let contacts = try makeTestUserProfile().contacts

        #expect(
            contacts.first(where: { $0.id == .email })?
                .destination?.absoluteString
                == "mailto:alex@example.com"
        )
        #expect(
            contacts.first(where: { $0.id == .website })?
                .destination?.absoluteString
                == "https://example.com"
        )
        #expect(
            contacts.first(where: { $0.id == .github })?
                .destination?.absoluteString
                == "https://github.com/alexexample"
        )
        #expect(
            contacts.first(where: { $0.id == .linkedIn })?
                .destination?.absoluteString
                == "https://www.linkedin.com/in/alex-example"
        )
        #expect(
            contacts.first(where: { $0.id == .twitter })?
                .destination?.absoluteString
                == "https://x.com/alexexample"
        )
        #expect(
            contacts.first(where: { $0.id == .discord })?
                .destination == nil
        )
    }

    @Test("Drops empty and unsafe public fields")
    func dropsEmptyAndUnsafeFields() throws {
        let profile = try makeTestUserProfile(
            overrides:
                #""followers":-2,"website_url":"javascript:alert(1)","public_email":"   ","github":"https://user:secret@github.com/alex","linkedin":" ","twitter":" ","discord":" ""#
        )

        #expect(profile.followers == nil)
        #expect(profile.contacts.map(\.id) == [.website, .github])
        #expect(profile.contacts.allSatisfy { $0.destination == nil })
    }

    @MainActor
    @Test("Bundles official social brand marks")
    func bundlesSocialBrandMarks() {
        for name in [
            "GitHubMark",
            "LinkedInMark",
            "XMark",
            "DiscordMark",
        ] {
            #expect(
                UIImage(named: name) != nil,
                "Missing asset for \(name)"
            )
        }
    }
}

nonisolated func makeTestUserProfile(
    isFollowed: Bool = false,
    followers: Int = 660,
    overrides: String? = nil
) throws -> GitLabUserProfile {
    var fields = [
        #""id":42"#,
        #""username":"alexexample""#,
        #""name":"Alex Example""#,
        #""state":"active""#,
        #""locked":false"#,
        #""avatar_url":"https://gitlab.example.com/avatar.png""#,
        #""web_url":"https://gitlab.example.com/alexexample""#,
        #""created_at":"2024-01-28T12:30:45.456Z""#,
        #""bio":"Builds GitLab tools""#,
        #""bot":false"#,
        #""location":"New York""#,
        #""public_email":"alex@example.com""#,
        #""linkedin":"alex-example""#,
        #""twitter":"@alexexample""#,
        #""discord":"alex#1234""#,
        #""github":"alexexample""#,
        #""website_url":"example.com""#,
        #""organization":"Example, Inc.""#,
        #""job_title":"Engineer""#,
        #""pronouns":"they/them""#,
        #""work_information":"Mobile""#,
        #""followers":\#(followers)"#,
        #""following":49"#,
        #""local_time":"11:04 AM""#,
        #""is_followed":\#(isFollowed)"#,
    ]
    if let overrides {
        for replacement in overrides.split(separator: ",") {
            let key = replacement.split(separator: ":", maxSplits: 1)[0]
            fields.removeAll { $0.hasPrefix("\(key):") }
            fields.append(String(replacement))
        }
    }
    let data = Data("{\(fields.joined(separator: ","))}".utf8)
    return try JSONDecoder().decode(
        GitLabUserProfile.self,
        from: data
    )
}
