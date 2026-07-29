import Foundation

nonisolated struct GitLabMergeRequestApprovalDetails:
    Decodable,
    Equatable,
    Sendable
{
    let approvalRulesOverwritten: Bool?
    let rules:
        [GitLabMergeRequestApprovalRule]

    init(
        approvalRulesOverwritten: Bool?,
        rules:
            [GitLabMergeRequestApprovalRule]
    ) {
        self.approvalRulesOverwritten =
            approvalRulesOverwritten
        self.rules = rules
    }

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        approvalRulesOverwritten =
            try container.decodeIfPresent(
                Bool.self,
                forKey:
                    .approvalRulesOverwritten
            )
        rules =
            try container.decodeIfPresent(
                [GitLabMergeRequestApprovalRule]
                    .self,
                forKey: .rules
            )
            ?? []
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case approvalRulesOverwritten =
            "approval_rules_overwritten"
        case rules
    }
}

nonisolated struct
    GitLabMergeRequestApprovalRuleGroup:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String?
    let path: String?
    let avatarURL: URL?
    let webURL: URL?

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case name
        case path
        case avatarURL = "avatar_url"
        case webURL = "web_url"
    }
}

nonisolated struct
    GitLabMergeRequestApprovalSourceRule:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int?
}

nonisolated struct GitLabMergeRequestApprovalRule:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int?
    let name: String?
    let ruleType: String?
    let eligibleApprovers:
        [GitLabAPIUser]?
    let approvalsRequired: Int?
    let users: [GitLabAPIUser]?
    let groups:
        [GitLabMergeRequestApprovalRuleGroup]?
    let containsHiddenGroups: Bool?
    let approvedBy: [GitLabAPIUser]?
    let sourceRule:
        GitLabMergeRequestApprovalSourceRule?
    let approved: Bool?
    let overridden: Bool?

    init(
        id: Int?,
        name: String?,
        ruleType: String?,
        eligibleApprovers:
            [GitLabAPIUser]?,
        approvalsRequired: Int?,
        users: [GitLabAPIUser]?,
        groups:
            [GitLabMergeRequestApprovalRuleGroup]?,
        containsHiddenGroups: Bool?,
        approvedBy: [GitLabAPIUser]?,
        sourceRule:
            GitLabMergeRequestApprovalSourceRule? =
                nil,
        approved: Bool?,
        overridden: Bool?
    ) {
        self.id = id
        self.name = name
        self.ruleType = ruleType
        self.eligibleApprovers =
            eligibleApprovers
        self.approvalsRequired =
            approvalsRequired
        self.users = users
        self.groups = groups
        self.containsHiddenGroups =
            containsHiddenGroups
        self.approvedBy = approvedBy
        self.sourceRule = sourceRule
        self.approved = approved
        self.overridden = overridden
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case name
        case ruleType = "rule_type"
        case eligibleApprovers =
            "eligible_approvers"
        case approvalsRequired =
            "approvals_required"
        case users
        case groups
        case containsHiddenGroups =
            "contains_hidden_groups"
        case approvedBy = "approved_by"
        case sourceRule = "source_rule"
        case approved
        case overridden
    }
}

nonisolated enum
    GitLabMergeRequestApprovalDetailsAvailability:
    Equatable,
    Sendable
{
    case available(
        GitLabMergeRequestApprovalDetails
    )
    case unavailable
}

nonisolated enum
    GitLabMergeRequestApprovalRuleState:
    Equatable,
    Sendable
{
    case approved
    case pending(remaining: Int?)
    case notRequired
    case unknown
}

nonisolated enum
    GitLabMergeRequestApprovalPersonState:
    Equatable,
    Sendable
{
    case approved
    case eligible
}

nonisolated struct
    GitLabMergeRequestApprovalPersonPresentation:
    Equatable,
    Sendable
{
    let user: GitLabAPIUser
    let state:
        GitLabMergeRequestApprovalPersonState
}

nonisolated enum
    GitLabMergeRequestApprovalRuleLockReason:
    Equatable,
    Sendable
{
    case hiddenGroups
    case systemRule
    case unknownRuleType
    case incomplete
}

nonisolated enum
    GitLabMergeRequestApprovalRuleEditability:
    Equatable,
    Sendable
{
    case editable
    case locked(
        GitLabMergeRequestApprovalRuleLockReason
    )
}

nonisolated struct
    GitLabMergeRequestApprovalRulePresentation:
    Equatable,
    Sendable
{
    let title: String
    let state:
        GitLabMergeRequestApprovalRuleState
    let people:
        [GitLabMergeRequestApprovalPersonPresentation]
    let editability:
        GitLabMergeRequestApprovalRuleEditability

    init(
        rule: GitLabMergeRequestApprovalRule
    ) {
        title =
            rule.name?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .nonempty
            ?? "Approval rule"
        state = Self.state(for: rule)
        people = Self.people(for: rule)
        editability =
            Self.editability(for: rule)
    }

    private static func state(
        for rule:
            GitLabMergeRequestApprovalRule
    ) -> GitLabMergeRequestApprovalRuleState {
        guard
            let required =
                rule.approvalsRequired,
            required >= 0
        else {
            return .unknown
        }
        guard required > 0 else {
            return .notRequired
        }

        let uniqueApprovedCount =
            Set(
                (rule.approvedBy ?? [])
                    .map(\.id)
            )
            .count
        let remaining = max(
            required - uniqueApprovedCount,
            0
        )

        if let approved = rule.approved {
            return approved
                ? .approved
                : .pending(
                    remaining: remaining
                )
        }
        guard rule.approvedBy != nil else {
            return .unknown
        }
        return remaining == 0
            ? .approved
            : .pending(
                remaining: remaining
            )
    }

    private static func people(
        for rule:
            GitLabMergeRequestApprovalRule
    ) -> [
        GitLabMergeRequestApprovalPersonPresentation
    ] {
        var seen: Set<Int> = []
        var result: [
            GitLabMergeRequestApprovalPersonPresentation
        ] = []

        for user in rule.approvedBy ?? [] {
            guard seen.insert(user.id).inserted else {
                continue
            }
            result.append(
                GitLabMergeRequestApprovalPersonPresentation(
                    user: user,
                    state: .approved
                )
            )
        }
        for user in rule.eligibleApprovers ?? [] {
            guard seen.insert(user.id).inserted else {
                continue
            }
            result.append(
                GitLabMergeRequestApprovalPersonPresentation(
                    user: user,
                    state: .eligible
                )
            )
        }
        return result
    }

    private static func editability(
        for rule:
            GitLabMergeRequestApprovalRule
    ) -> GitLabMergeRequestApprovalRuleEditability {
        let type =
            rule.ruleType?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        switch type {
        case "regular":
            break
        case "code_owner",
             "report_approver",
             "any_approver":
            return .locked(.systemRule)
        case .some:
            return .locked(
                .unknownRuleType
            )
        case .none:
            return .locked(.incomplete)
        }

        if rule.containsHiddenGroups == true {
            return .locked(.hiddenGroups)
        }
        guard
            let id = rule.id,
            id > 0,
            rule.name?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty == false,
            let required =
                rule.approvalsRequired,
            required >= 0,
            let users = rule.users,
            users.allSatisfy({ $0.id > 0 }),
            let groups = rule.groups,
            groups.allSatisfy({
                $0.id > 0
            }),
            rule.containsHiddenGroups
                == false
        else {
            return .locked(.incomplete)
        }
        return .editable
    }
}

private nonisolated extension String {
    var nonempty: String? {
        isEmpty ? nil : self
    }
}

nonisolated struct
    GitLabMergeRequestApprovalRuleReplacement:
    Encodable,
    Equatable,
    Sendable
{
    let name: String
    let approvalsRequired: Int
    let userIDs: [Int]
    let groupIDs: [Int]
    let removeHiddenGroups = false

    init(
        name: String,
        approvalsRequired: Int,
        userIDs: [Int],
        groupIDs: [Int]
    ) {
        self.name = name
        self.approvalsRequired =
            approvalsRequired
        self.userIDs = userIDs
        self.groupIDs = groupIDs
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case name
        case approvalsRequired =
            "approvals_required"
        case userIDs = "user_ids"
        case groupIDs = "group_ids"
        case removeHiddenGroups =
            "remove_hidden_groups"
    }
}
