import Foundation

nonisolated enum GitLabSearchScope:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case projects
    case issues
    case mergeRequests

    var apiValue: String {
        switch self {
        case .projects:
            "projects"
        case .issues:
            "issues"
        case .mergeRequests:
            "merge_requests"
        }
    }
}

nonisolated struct GitLabProjectSearchResult:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String
    let nameWithNamespace: String?
    let pathWithNamespace: String
    let description: String?
    let webURL: URL?
    let avatarURL: URL?
    let visibility: GitLabProjectVisibility?
    let starCount: Int?
    let lastActivityAt: Date?

    init(
        id: Int,
        name: String,
        nameWithNamespace: String?,
        pathWithNamespace: String,
        description: String?,
        webURL: URL?,
        avatarURL: URL?,
        visibility: GitLabProjectVisibility?,
        starCount: Int?,
        lastActivityAt: Date?
    ) {
        self.id = id
        self.name = name
        self.nameWithNamespace = nameWithNamespace
        self.pathWithNamespace = pathWithNamespace
        self.description = description
        self.webURL = webURL
        self.avatarURL = avatarURL
        self.visibility = visibility
        self.starCount = starCount
        self.lastActivityAt = lastActivityAt
    }

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameWithNamespace = "name_with_namespace"
        case pathWithNamespace = "path_with_namespace"
        case description
        case webURL = "web_url"
        case avatarURL = "avatar_url"
        case visibility
        case starCount = "star_count"
        case lastActivityAt = "last_activity_at"
    }
}

nonisolated struct GitLabIssueSearchResult:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let iid: Int
    let projectID: Int
    let title: String
    let description: String?
    let state: String
    let confidential: Bool
    let labels: [String]
    let author: GitLabAPIUser?
    let updatedAt: Date?
    let webURL: URL?

    init(
        id: Int,
        iid: Int,
        projectID: Int,
        title: String,
        description: String?,
        state: String,
        confidential: Bool,
        labels: [String],
        author: GitLabAPIUser?,
        updatedAt: Date?,
        webURL: URL?
    ) {
        self.id = id
        self.iid = iid
        self.projectID = projectID
        self.title = title
        self.description = description
        self.state = state
        self.confidential = confidential
        self.labels = labels
        self.author = author
        self.updatedAt = updatedAt
        self.webURL = webURL
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        id = try container.decode(Int.self, forKey: .id)
        iid = try container.decode(Int.self, forKey: .iid)
        projectID = try container.decode(
            Int.self,
            forKey: .projectID
        )
        title = try container.decode(
            String.self,
            forKey: .title
        )
        description = try container.decodeIfPresent(
            String.self,
            forKey: .description
        )
        state = try container.decodeIfPresent(
            String.self,
            forKey: .state
        ) ?? "unknown"
        confidential = try container.decodeIfPresent(
            Bool.self,
            forKey: .confidential
        ) ?? false
        labels = try container.decodeIfPresent(
            [String].self,
            forKey: .labels
        ) ?? []
        author = try container.decodeIfPresent(
            GitLabAPIUser.self,
            forKey: .author
        )
        updatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        )
        webURL = try container.decodeIfPresent(
            URL.self,
            forKey: .webURL
        )
    }

    var route: GitLabIssueRoute {
        GitLabIssueRoute(
            projectID: projectID,
            issueIID: iid
        )
    }

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case description
        case state
        case confidential
        case labels
        case author
        case updatedAt = "updated_at"
        case webURL = "web_url"
    }
}

nonisolated struct GitLabMergeRequestSearchResult:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let iid: Int
    let projectID: Int
    let title: String
    let description: String?
    let state: String
    let draft: Bool?
    let legacyWorkInProgress: Bool?
    let labels: [String]
    let author: GitLabAPIUser?
    let updatedAt: Date?
    let webURL: URL?

    init(
        id: Int,
        iid: Int,
        projectID: Int,
        title: String,
        description: String?,
        state: String,
        draft: Bool?,
        legacyWorkInProgress: Bool?,
        labels: [String],
        author: GitLabAPIUser?,
        updatedAt: Date?,
        webURL: URL?
    ) {
        self.id = id
        self.iid = iid
        self.projectID = projectID
        self.title = title
        self.description = description
        self.state = state
        self.draft = draft
        self.legacyWorkInProgress =
            legacyWorkInProgress
        self.labels = labels
        self.author = author
        self.updatedAt = updatedAt
        self.webURL = webURL
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        id = try container.decode(Int.self, forKey: .id)
        iid = try container.decode(Int.self, forKey: .iid)
        projectID = try container.decode(
            Int.self,
            forKey: .projectID
        )
        title = try container.decode(
            String.self,
            forKey: .title
        )
        description = try container.decodeIfPresent(
            String.self,
            forKey: .description
        )
        state = try container.decodeIfPresent(
            String.self,
            forKey: .state
        ) ?? "unknown"
        draft = try container.decodeIfPresent(
            Bool.self,
            forKey: .draft
        )
        legacyWorkInProgress =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .legacyWorkInProgress
            )
        labels = try container.decodeIfPresent(
            [String].self,
            forKey: .labels
        ) ?? []
        author = try container.decodeIfPresent(
            GitLabAPIUser.self,
            forKey: .author
        )
        updatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        )
        webURL = try container.decodeIfPresent(
            URL.self,
            forKey: .webURL
        )
    }

    var route: GitLabMergeRequestRoute {
        GitLabMergeRequestRoute(
            projectID: projectID,
            mergeRequestIID: iid
        )
    }

    var isDraft: Bool {
        draft ?? legacyWorkInProgress ?? false
    }

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case title
        case description
        case state
        case draft
        case legacyWorkInProgress = "work_in_progress"
        case labels
        case author
        case updatedAt = "updated_at"
        case webURL = "web_url"
    }
}

nonisolated enum GitLabSearchResult:
    Decodable,
    Equatable,
    Sendable
{
    case project(GitLabProjectSearchResult)
    case issue(GitLabIssueSearchResult)
    case mergeRequest(
        GitLabMergeRequestSearchResult
    )

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: DiscriminatorKeys.self
        )

        if container.contains(.pathWithNamespace) {
            self = .project(
                try GitLabProjectSearchResult(
                    from: decoder
                )
            )
        } else if
            container.contains(.sourceBranch)
                || container.contains(.targetBranch)
                || container.contains(.draft)
                || container.contains(
                    .legacyWorkInProgress
                )
        {
            self = .mergeRequest(
                try GitLabMergeRequestSearchResult(
                    from: decoder
                )
            )
        } else {
            self = .issue(
                try GitLabIssueSearchResult(
                    from: decoder
                )
            )
        }
    }

    var resourceID: GitLabSearchResourceID {
        switch self {
        case let .project(project):
            .project(project.id)
        case let .issue(issue):
            .issue(issue.route)
        case let .mergeRequest(mergeRequest):
            .mergeRequest(mergeRequest.route)
        }
    }

    var scope: GitLabSearchScope {
        switch self {
        case .project:
            .projects
        case .issue:
            .issues
        case .mergeRequest:
            .mergeRequests
        }
    }

    private enum DiscriminatorKeys:
        String,
        CodingKey
    {
        case pathWithNamespace =
            "path_with_namespace"
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case draft
        case legacyWorkInProgress =
            "work_in_progress"
    }
}

nonisolated enum GitLabSearchResourceID:
    Equatable,
    Hashable,
    Sendable
{
    case project(Int)
    case issue(GitLabIssueRoute)
    case mergeRequest(GitLabMergeRequestRoute)
}

nonisolated struct GitLabSearchResultID:
    Equatable,
    Hashable,
    Sendable
{
    let accountID: GitLabAccountID
    let resource: GitLabSearchResourceID
}

nonisolated struct GitLabSearchPage:
    Equatable,
    Sendable
{
    let results: [GitLabSearchResult]
    let nextPageURL: URL?
    let totalCount: Int?

    init(
        results: [GitLabSearchResult],
        nextPageURL: URL?,
        totalCount: Int? = nil
    ) {
        self.results = results
        self.nextPageURL = nextPageURL
        self.totalCount = totalCount
    }
}
