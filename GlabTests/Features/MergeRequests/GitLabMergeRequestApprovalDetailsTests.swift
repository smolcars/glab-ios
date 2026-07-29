import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request approval details")
struct GitLabMergeRequestApprovalDetailsTests {
    @Test("Decodes approving users and approval timestamps")
    func decodesGlobalApprovals() throws {
        let summary: GitLabMergeRequestApprovalSummary =
            try decode(
                """
                {
                  "approved": false,
                  "approvals_required": 2,
                  "approvals_left": 1,
                  "approved_by": [
                    {
                      "user": {
                        "id": 7,
                        "username": "ada",
                        "name": "Ada Lovelace",
                        "avatar_url": "https://gitlab.example.com/uploads/ada.png",
                        "web_url": "https://gitlab.example.com/ada"
                      },
                      "approved_at": "2026-07-29T12:34:56Z"
                    }
                  ]
                }
                """
            )

        let approval = try #require(
            summary.approvedBy.first
        )
        #expect(approval.user?.id == 7)
        #expect(
            approval.approvedAt
                == Date(
                    timeIntervalSince1970:
                        1_785_328_496
                )
        )
    }

    @Test("Decodes zero and multiple detailed rules")
    func decodesDetailedRules() throws {
        let empty: GitLabMergeRequestApprovalDetails =
            try decode(
                """
                {
                  "approval_rules_overwritten": false,
                  "rules": []
                }
                """
            )
        let details: GitLabMergeRequestApprovalDetails =
            try decode(detailedFixture)

        #expect(empty.rules.isEmpty)
        #expect(
            empty.approvalRulesOverwritten
                == false
        )
        #expect(details.rules.count == 2)

        let security = try #require(
            details.rules.first
        )
        #expect(security.id == 41)
        #expect(security.name == "Security")
        #expect(security.ruleType == "regular")
        #expect(
            security.eligibleApprovers?
                .map(\.id) == [7, 8, 8]
        )
        #expect(
            security.approvedBy?
                .map(\.id) == [7, 7]
        )
        #expect(
            security.users?.map(\.id) == [7]
        )
        #expect(
            security.groups?.map(\.id) == [19]
        )
        #expect(
            security.containsHiddenGroups
                == false
        )
        #expect(security.approved == false)
        #expect(security.overridden == true)

        let codeOwners = try #require(
            details.rules.last
        )
        #expect(
            codeOwners.ruleType == "code_owner"
        )
        #expect(
            codeOwners.containsHiddenGroups
                == true
        )
    }

    @Test("Keeps omitted mutation fields distinct from empty arrays")
    func decodesPartialRule() throws {
        let details:
            GitLabMergeRequestApprovalDetails =
            try decode(
                """
                {
                  "rules": [
                    {
                      "id": 99,
                      "name": "Partial"
                    }
                  ]
                }
                """
            )
        let rule = try #require(
            details.rules.first
        )

        #expect(rule.eligibleApprovers == nil)
        #expect(rule.approvedBy == nil)
        #expect(rule.users == nil)
        #expect(rule.groups == nil)
        #expect(
            rule.containsHiddenGroups == nil
        )
        #expect(rule.approvalsRequired == nil)
        #expect(rule.approved == nil)
    }

    @Test("Presents approved and eligible people without duplicates")
    func presentsRulePeople() throws {
        let details:
            GitLabMergeRequestApprovalDetails =
            try decode(detailedFixture)
        let security = try #require(
            details.rules.first
        )
        let presentation =
            GitLabMergeRequestApprovalRulePresentation(
                rule: security
            )

        #expect(
            presentation.state
                == .pending(remaining: 1)
        )
        #expect(
            presentation.people.map(\.user.id)
                == [7, 8]
        )
        #expect(
            presentation.people.map(\.state)
                == [.approved, .eligible]
        )
        #expect(
            presentation.editability == .editable
        )
    }

    @Test("Presents global approvals once and preserves response order")
    func presentsGlobalApprovals() {
        let summary =
            GitLabMergeRequestApprovalSummary(
                approved: false,
                approvalsRequired: 2,
                approvalsLeft: 1,
                approvedBy: [
                    GitLabMergeRequestApproval(
                        user: makeUser(7)
                    ),
                    GitLabMergeRequestApproval(
                        user: nil
                    ),
                    GitLabMergeRequestApproval(
                        user: makeUser(7)
                    ),
                    GitLabMergeRequestApproval(
                        user: makeUser(8)
                    ),
                ]
            )

        let presentation =
            GitLabMergeRequestApprovalSummaryPresentation(
                summary: summary,
                currentUserID: 7
            )

        #expect(
            presentation.approvals
                .compactMap(\.user?.id)
                == [7, 8]
        )
        #expect(
            presentation.currentUserHasApproved
        )
        #expect(
            presentation.status
                == .remaining(1)
        )
    }

    @Test(
        "Keeps concise global approval status semantic",
        arguments: [
            (
                true as Bool?,
                Optional(0),
                Optional(0),
                0,
                GitLabMergeRequestApprovalSummaryStatus
                    .notRequired
            ),
            (
                true as Bool?,
                Optional(2),
                Optional(0),
                2,
                .complete
            ),
            (
                false as Bool?,
                Optional(2),
                nil as Int?,
                1,
                .recorded(1)
            ),
            (
                nil as Bool?,
                nil as Int?,
                nil as Int?,
                0,
                .none
            ),
        ]
    )
    func presentsGlobalStatus(
        approved: Bool?,
        required: Int?,
        left: Int?,
        approvalCount: Int,
        expected:
            GitLabMergeRequestApprovalSummaryStatus
    ) {
        let summary =
            GitLabMergeRequestApprovalSummary(
                approved: approved,
                approvalsRequired: required,
                approvalsLeft: left,
                approvedBy:
                    (0..<approvalCount)
                    .map {
                        GitLabMergeRequestApproval(
                            user:
                                makeUser(
                                    $0 + 1
                                )
                        )
                    }
            )

        #expect(
            GitLabMergeRequestApprovalSummaryPresentation(
                summary: summary,
                currentUserID: 99
            ).status == expected
        )
    }

    @Test(
        "Uses authoritative rule state before inconsistent counts",
        arguments: [
            (
                Optional(true),
                3,
                [7],
                GitLabMergeRequestApprovalRuleState
                    .approved
            ),
            (
                Optional(false),
                1,
                [7],
                .pending(remaining: 0)
            ),
            (
                nil as Bool?,
                2,
                [7],
                .pending(remaining: 1)
            ),
            (
                nil as Bool?,
                0,
                [],
                .notRequired
            ),
        ]
    )
    func presentsRuleState(
        approved: Bool?,
        required: Int,
        approvedUserIDs: [Int],
        expected:
            GitLabMergeRequestApprovalRuleState
    ) {
        let rule = makeRule(
            approvalsRequired: required,
            approvedBy:
                approvedUserIDs.map(makeUser),
            approved: approved
        )

        #expect(
            GitLabMergeRequestApprovalRulePresentation(
                rule: rule
            ).state == expected
        )
    }

    @Test("Locks hidden, system, and incomplete rules")
    func locksUnsafeRules() {
        let hidden =
            GitLabMergeRequestApprovalRulePresentation(
                rule:
                    makeRule(
                        containsHiddenGroups: true
                    )
            )
        let system =
            GitLabMergeRequestApprovalRulePresentation(
                rule:
                    makeRule(
                        ruleType:
                            "report_approver"
                    )
            )
        let unknown =
            GitLabMergeRequestApprovalRulePresentation(
                rule:
                    makeRule(
                        ruleType:
                            "future_rule"
                    )
            )
        let incomplete =
            GitLabMergeRequestApprovalRulePresentation(
                rule:
                    GitLabMergeRequestApprovalRule(
                        id: 41,
                        name: "Incomplete",
                        ruleType: "regular",
                        eligibleApprovers: [],
                        approvalsRequired: 1,
                        users: nil,
                        groups: [],
                        containsHiddenGroups: false,
                        approvedBy: [],
                        approved: false,
                        overridden: false
                    )
            )

        #expect(
            hidden.editability
                == .locked(.hiddenGroups)
        )
        #expect(
            system.editability
                == .locked(.systemRule)
        )
        #expect(
            unknown.editability
                == .locked(.unknownRuleType)
        )
        #expect(
            incomplete.editability
                == .locked(.incomplete)
        )
    }

    @Test("Keeps overlapping eligible users scoped to each rule")
    func preservesOverlappingUsers() {
        let first =
            GitLabMergeRequestApprovalRulePresentation(
                rule:
                    makeRule(
                        id: 1,
                        eligibleApprovers: [
                            makeUser(7),
                            makeUser(8),
                        ],
                        approvedBy: [
                            makeUser(7)
                        ]
                    )
            )
        let second =
            GitLabMergeRequestApprovalRulePresentation(
                rule:
                    makeRule(
                        id: 2,
                        eligibleApprovers: [
                            makeUser(7),
                            makeUser(9),
                        ],
                        approvedBy: []
                    )
            )

        #expect(
            first.people.map(\.user.id)
                == [7, 8]
        )
        #expect(
            second.people.map(\.user.id)
                == [7, 9]
        )
        #expect(
            second.people.map(\.state)
                == [.eligible, .eligible]
        )
    }

    private var detailedFixture: String {
        """
        {
          "approval_rules_overwritten": true,
          "rules": [
            {
              "id": 41,
              "name": "Security",
              "rule_type": "regular",
              "eligible_approvers": [
                {
                  "id": 7,
                  "username": "ada",
                  "name": "Ada",
                  "avatar_url": null,
                  "web_url": null
                },
                {
                  "id": 8,
                  "username": "grace",
                  "name": "Grace",
                  "avatar_url": null,
                  "web_url": null
                },
                {
                  "id": 8,
                  "username": "grace",
                  "name": "Grace",
                  "avatar_url": null,
                  "web_url": null
                }
              ],
              "approvals_required": 2,
              "users": [
                {
                  "id": 7,
                  "username": "ada",
                  "name": "Ada",
                  "avatar_url": null,
                  "web_url": null
                }
              ],
              "groups": [
                {
                  "id": 19,
                  "name": "Security",
                  "path": "security",
                  "avatar_url": null,
                  "web_url": "https://gitlab.example.com/groups/security"
                }
              ],
              "contains_hidden_groups": false,
              "approved_by": [
                {
                  "id": 7,
                  "username": "ada",
                  "name": "Ada",
                  "avatar_url": null,
                  "web_url": null
                },
                {
                  "id": 7,
                  "username": "ada",
                  "name": "Ada",
                  "avatar_url": null,
                  "web_url": null
                }
              ],
              "approved": false,
              "overridden": true
            },
            {
              "id": 42,
              "name": "Code Owners",
              "rule_type": "code_owner",
              "eligible_approvers": [],
              "approvals_required": 1,
              "users": [],
              "groups": [],
              "contains_hidden_groups": true,
              "approved_by": [],
              "approved": false,
              "overridden": false
            }
          ]
        }
        """
    }

    private func makeRule(
        id: Int = 41,
        ruleType: String = "regular",
        eligibleApprovers:
            [GitLabAPIUser] = [],
        approvalsRequired: Int = 2,
        users: [GitLabAPIUser]? = [],
        groups:
            [GitLabMergeRequestApprovalRuleGroup]? =
                [],
        containsHiddenGroups: Bool? = false,
        approvedBy:
            [GitLabAPIUser]? = [],
        approved: Bool? = false
    ) -> GitLabMergeRequestApprovalRule {
        GitLabMergeRequestApprovalRule(
            id: id,
            name: "Security",
            ruleType: ruleType,
            eligibleApprovers:
                eligibleApprovers,
            approvalsRequired:
                approvalsRequired,
            users: users,
            groups: groups,
            containsHiddenGroups:
                containsHiddenGroups,
            approvedBy: approvedBy,
            approved: approved,
            overridden: false
        )
    }

    private func makeUser(
        _ id: Int
    ) -> GitLabAPIUser {
        GitLabAPIUser(
            id: id,
            username: "user\(id)",
            name: "User \(id)",
            avatarURL: nil,
            webURL: nil
        )
    }

    private func decode<Value>(
        _ json: String
    ) throws -> Value
    where Value: Decodable {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Value.self,
            from: Data(json.utf8)
        )
    }
}
