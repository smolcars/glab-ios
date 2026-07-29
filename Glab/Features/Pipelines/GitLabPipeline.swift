import Foundation

nonisolated struct GitLabPipelineRoute:
    Equatable,
    Hashable,
    Sendable
{
    let projectID: Int
    let pipelineID: Int

    init?(
        projectID: Int,
        pipelineID: Int
    ) {
        guard
            projectID > 0,
            pipelineID > 0
        else {
            return nil
        }

        self.projectID = projectID
        self.pipelineID = pipelineID
    }
}

nonisolated struct GitLabJobRoute:
    Equatable,
    Hashable,
    Sendable
{
    let projectID: Int
    let pipelineID: Int
    let jobID: Int

    init?(
        projectID: Int,
        pipelineID: Int,
        jobID: Int
    ) {
        guard
            projectID > 0,
            pipelineID > 0,
            jobID > 0
        else {
            return nil
        }

        self.projectID = projectID
        self.pipelineID = pipelineID
        self.jobID = jobID
    }

    var pipelineRoute: GitLabPipelineRoute {
        GitLabPipelineRoute(
            projectID: projectID,
            pipelineID: pipelineID
        )!
    }
}

nonisolated struct GitLabCIStatus:
    Decodable,
    Equatable,
    Hashable,
    Sendable
{
    let rawValue: String

    init(rawValue: String) {
        self.rawValue =
            rawValue
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }

    init(from decoder: any Decoder) throws {
        let rawValue =
            try decoder
            .singleValueContainer()
            .decode(String.self)
        self.init(rawValue: rawValue)

        guard !self.rawValue.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "CI status cannot be empty."
                )
            )
        }
    }

    var title: String {
        switch rawValue {
        case "created":
            "Created"
        case "waiting_for_resource":
            "Waiting for resources"
        case "preparing":
            "Preparing"
        case "waiting_for_callback":
            "Waiting for callback"
        case "pending":
            "Pending"
        case "running":
            "Running"
        case "canceling":
            "Canceling"
        case "scheduled":
            "Scheduled"
        case "manual":
            "Manual"
        case "success":
            "Passed"
        case "failed":
            "Failed"
        case "canceled":
            "Canceled"
        case "skipped":
            "Skipped"
        default:
            "Unknown"
        }
    }

    var jobTitle: String {
        switch rawValue {
        case "created":
            "Waiting for prerequisites"
        case "waiting_for_resource":
            "Waiting for resource"
        case "pending":
            "Waiting for runner"
        default:
            title
        }
    }

    var showsActivityAnimation: Bool {
        switch rawValue {
        case "preparing",
             "running",
             "canceling":
            true
        default:
            false
        }
    }

    var showsWaitingIndicator: Bool {
        switch rawValue {
        case "created",
             "waiting_for_resource",
             "waiting_for_callback",
             "pending",
             "scheduled":
            true
        default:
            false
        }
    }

    var isActivelyChanging: Bool {
        switch rawValue {
        case "created",
             "waiting_for_resource",
             "preparing",
             "waiting_for_callback",
             "pending",
             "running",
             "canceling",
             "scheduled":
            true
        default:
            false
        }
    }

    var isTerminal: Bool {
        switch rawValue {
        case "success",
             "failed",
             "canceled",
             "skipped":
            true
        default:
            false
        }
    }
}

nonisolated struct GitLabPipelineDetailedStatus:
    Decodable,
    Equatable,
    Sendable
{
    let text: String?
    let label: String?
    let group: String?
    let tooltip: String?
    let hasDetails: Bool?
    let detailsPath: String?

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        text = container.decodeLossy(
            String.self,
            forKey: .text
        )
        label = container.decodeLossy(
            String.self,
            forKey: .label
        )
        group = container.decodeLossy(
            String.self,
            forKey: .group
        )
        tooltip = container.decodeLossy(
            String.self,
            forKey: .tooltip
        )
        hasDetails = container.decodeLossy(
            Bool.self,
            forKey: .hasDetails
        )
        detailsPath = container.decodeLossy(
            String.self,
            forKey: .detailsPath
        )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case text
        case label
        case group
        case tooltip
        case hasDetails = "has_details"
        case detailsPath = "details_path"
    }
}

nonisolated struct GitLabPipelineUser:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let username: String?
    let name: String?
    let avatarURL: URL?
    let webURL: URL?

    var displayName: String {
        if let name = Self.nonempty(name) {
            return name
        }
        if let username = Self.nonempty(username) {
            return username
        }
        return "GitLab user"
    }

    var safeAvatarURL: URL? {
        GitLabWebURL.validated(avatarURL)
    }

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    var summary: GitLabUserSummary {
        GitLabUserSummary(
            id: id,
            username: username ?? "",
            name: name ?? "",
            avatarURL: safeAvatarURL
        )
    }

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        id = try container.decodePositiveInt(
            forKey: .id
        )
        username = container.decodeLossy(
            String.self,
            forKey: .username
        )
        name = container.decodeLossy(
            String.self,
            forKey: .name
        )
        avatarURL = container.decodeLossy(
            URL.self,
            forKey: .avatarURL
        )
        webURL = container.decodeLossy(
            URL.self,
            forKey: .webURL
        )
    }

    private static func nonempty(
        _ value: String?
    ) -> String? {
        let normalized =
            value?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        return normalized?.isEmpty == false
            ? normalized
            : nil
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case username
        case name
        case avatarURL = "avatar_url"
        case webURL = "web_url"
    }
}

nonisolated struct GitLabPipeline:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let iid: Int?
    let projectID: Int?
    let name: String?
    let sha: String
    let ref: String
    let status: GitLabCIStatus
    let source: String?
    let createdAt: Date?
    let updatedAt: Date?
    let startedAt: Date?
    let finishedAt: Date?
    let duration: TimeInterval?
    let queuedDuration: TimeInterval?
    let coverage: String?
    let archived: Bool?
    let webURL: URL?
    let user: GitLabPipelineUser?
    let detailedStatus:
        GitLabPipelineDetailedStatus?

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    var route: GitLabPipelineRoute? {
        guard let projectID else {
            return nil
        }
        return GitLabPipelineRoute(
            projectID: projectID,
            pipelineID: id
        )
    }

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        id = try container.decodePositiveInt(
            forKey: .id
        )
        iid = container.decodePositiveIntIfPresent(
            forKey: .iid
        )
        projectID =
            container.decodePositiveIntIfPresent(
                forKey: .projectID
            )
        name = container.decodeNonemptyStringIfPresent(
            forKey: .name
        )
        sha = try container.decodeNonemptyString(
            forKey: .sha
        )
        ref = try container.decodeNonemptyString(
            forKey: .ref
        )
        status = try container.decode(
            GitLabCIStatus.self,
            forKey: .status
        )
        source = container.decodeNonemptyStringIfPresent(
            forKey: .source
        )
        createdAt = container.decodeLossy(
            Date.self,
            forKey: .createdAt
        )
        updatedAt = container.decodeLossy(
            Date.self,
            forKey: .updatedAt
        )
        startedAt = container.decodeLossy(
            Date.self,
            forKey: .startedAt
        )
        finishedAt = container.decodeLossy(
            Date.self,
            forKey: .finishedAt
        )
        duration =
            container.decodeNonnegativeDoubleIfPresent(
                forKey: .duration
            )
        queuedDuration =
            container.decodeNonnegativeDoubleIfPresent(
                forKey: .queuedDuration
            )
        coverage = container.decodeNonemptyStringIfPresent(
            forKey: .coverage
        )
        archived = container.decodeLossy(
            Bool.self,
            forKey: .archived
        )
        webURL = container.decodeLossy(
            URL.self,
            forKey: .webURL
        )
        user = container.decodeLossy(
            GitLabPipelineUser.self,
            forKey: .user
        )
        detailedStatus = container.decodeLossy(
            GitLabPipelineDetailedStatus.self,
            forKey: .detailedStatus
        )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case iid
        case projectID = "project_id"
        case name
        case sha
        case ref
        case status
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case duration
        case queuedDuration = "queued_duration"
        case coverage
        case archived
        case webURL = "web_url"
        case user
        case detailedStatus = "detailed_status"
    }
}

nonisolated struct GitLabPipelineReference:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let projectID: Int?
    let ref: String?
    let sha: String?
    let status: GitLabCIStatus?

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        id = try container.decodePositiveInt(
            forKey: .id
        )
        projectID =
            container.decodePositiveIntIfPresent(
                forKey: .projectID
            )
        ref = container.decodeNonemptyStringIfPresent(
            forKey: .ref
        )
        sha = container.decodeNonemptyStringIfPresent(
            forKey: .sha
        )
        status = container.decodeLossy(
            GitLabCIStatus.self,
            forKey: .status
        )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case projectID = "project_id"
        case ref
        case sha
        case status
    }
}

nonisolated struct GitLabPipelineRunner:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let description: String?
    let name: String?
    let runnerType: String?
    let systemID: String?
    let platform: String?
    let architecture: String?
    let status: String?
    let online: Bool?
    let paused: Bool?
    let isShared: Bool?

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        id = try container.decodePositiveInt(
            forKey: .id
        )
        description =
            container.decodeNonemptyStringIfPresent(
                forKey: .description
            )
        name = container.decodeNonemptyStringIfPresent(
            forKey: .name
        )
        runnerType =
            container.decodeNonemptyStringIfPresent(
                forKey: .runnerType
            )
        systemID =
            container.decodeNonemptyStringIfPresent(
                forKey: .systemID
            )
        platform =
            container.decodeNonemptyStringIfPresent(
                forKey: .platform
            )
        architecture =
            container.decodeNonemptyStringIfPresent(
                forKey: .architecture
            )
        status =
            container.decodeNonemptyStringIfPresent(
                forKey: .status
            )
        online = container.decodeLossy(
            Bool.self,
            forKey: .online
        )
        paused = container.decodeLossy(
            Bool.self,
            forKey: .paused
        )
        isShared = container.decodeLossy(
            Bool.self,
            forKey: .isShared
        )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case description
        case name
        case runnerType = "runner_type"
        case systemID = "system_id"
        case platform
        case architecture
        case status
        case online
        case paused
        case isShared = "is_shared"
    }
}

nonisolated struct GitLabPipelineArtifact:
    Decodable,
    Equatable,
    Sendable
{
    let fileType: String?
    let size: Int?
    let filename: String?
    let fileFormat: String?

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        fileType =
            container.decodeNonemptyStringIfPresent(
                forKey: .fileType
            )
        size =
            container.decodeNonnegativeIntIfPresent(
                forKey: .size
            )
        filename =
            container.decodeNonemptyStringIfPresent(
                forKey: .filename
            )
        fileFormat =
            container.decodeNonemptyStringIfPresent(
                forKey: .fileFormat
            )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case fileType = "file_type"
        case size
        case filename
        case fileFormat = "file_format"
    }
}

nonisolated struct GitLabPipelineArtifactSummary:
    Equatable,
    Sendable
{
    let artifacts: [GitLabPipelineArtifact]

    var totalSize: Int {
        artifacts.reduce(into: 0) {
            $0 += $1.size ?? 0
        }
    }

    var hasArchive: Bool {
        artifacts.contains {
            $0.fileType?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased() == "archive"
        }
    }
}

nonisolated struct GitLabPipelineJob:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String
    let stage: String
    let status: GitLabCIStatus
    let allowFailure: Bool
    let failureReason: String?
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?
    let erasedAt: Date?
    let archived: Bool?
    let duration: TimeInterval?
    let queuedDuration: TimeInterval?
    let ref: String?
    let webURL: URL?
    let pipeline: GitLabPipelineReference?
    let user: GitLabPipelineUser?
    let runner: GitLabPipelineRunner?
    let runnerManager: GitLabPipelineRunner?
    let artifactSummary:
        GitLabPipelineArtifactSummary

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        id = try container.decodePositiveInt(
            forKey: .id
        )
        name = try container.decodeNonemptyString(
            forKey: .name
        )
        stage = try container.decodeNonemptyString(
            forKey: .stage
        )
        status = try container.decode(
            GitLabCIStatus.self,
            forKey: .status
        )
        allowFailure =
            container.decodeLossy(
                Bool.self,
                forKey: .allowFailure
            )
            ?? false
        failureReason =
            container.decodeNonemptyStringIfPresent(
                forKey: .failureReason
            )
        createdAt = container.decodeLossy(
            Date.self,
            forKey: .createdAt
        )
        startedAt = container.decodeLossy(
            Date.self,
            forKey: .startedAt
        )
        finishedAt = container.decodeLossy(
            Date.self,
            forKey: .finishedAt
        )
        erasedAt = container.decodeLossy(
            Date.self,
            forKey: .erasedAt
        )
        archived = container.decodeLossy(
            Bool.self,
            forKey: .archived
        )
        duration =
            container.decodeNonnegativeDoubleIfPresent(
                forKey: .duration
            )
        queuedDuration =
            container.decodeNonnegativeDoubleIfPresent(
                forKey: .queuedDuration
            )
        ref = container.decodeNonemptyStringIfPresent(
            forKey: .ref
        )
        webURL = container.decodeLossy(
            URL.self,
            forKey: .webURL
        )
        pipeline = container.decodeLossy(
            GitLabPipelineReference.self,
            forKey: .pipeline
        )
        user = container.decodeLossy(
            GitLabPipelineUser.self,
            forKey: .user
        )
        runner = container.decodeLossy(
            GitLabPipelineRunner.self,
            forKey: .runner
        )
        runnerManager = container.decodeLossy(
            GitLabPipelineRunner.self,
            forKey: .runnerManager
        )
        artifactSummary =
            GitLabPipelineArtifactSummary(
                artifacts:
                    container.decodeLossy(
                        [GitLabPipelineArtifact].self,
                        forKey: .artifacts
                    )
                    ?? []
            )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case name
        case stage
        case status
        case allowFailure = "allow_failure"
        case failureReason = "failure_reason"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case erasedAt = "erased_at"
        case archived
        case duration
        case queuedDuration = "queued_duration"
        case ref
        case webURL = "web_url"
        case pipeline
        case user
        case runner
        case runnerManager = "runner_manager"
        case artifacts
    }
}

nonisolated struct GitLabPipelineTriggerJob:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String
    let stage: String
    let status: GitLabCIStatus
    let allowFailure: Bool
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?
    let duration: TimeInterval?
    let queuedDuration: TimeInterval?
    let webURL: URL?
    let user: GitLabPipelineUser?
    let pipeline: GitLabPipelineReference?
    let downstreamPipeline: GitLabPipeline?

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    var downstreamRoute: GitLabPipelineRoute? {
        downstreamPipeline?.route
    }

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        id = try container.decodePositiveInt(
            forKey: .id
        )
        name = try container.decodeNonemptyString(
            forKey: .name
        )
        stage = try container.decodeNonemptyString(
            forKey: .stage
        )
        status = try container.decode(
            GitLabCIStatus.self,
            forKey: .status
        )
        allowFailure =
            container.decodeLossy(
                Bool.self,
                forKey: .allowFailure
            )
            ?? false
        createdAt = container.decodeLossy(
            Date.self,
            forKey: .createdAt
        )
        startedAt = container.decodeLossy(
            Date.self,
            forKey: .startedAt
        )
        finishedAt = container.decodeLossy(
            Date.self,
            forKey: .finishedAt
        )
        duration =
            container.decodeNonnegativeDoubleIfPresent(
                forKey: .duration
            )
        queuedDuration =
            container.decodeNonnegativeDoubleIfPresent(
                forKey: .queuedDuration
            )
        webURL = container.decodeLossy(
            URL.self,
            forKey: .webURL
        )
        user = container.decodeLossy(
            GitLabPipelineUser.self,
            forKey: .user
        )
        pipeline = container.decodeLossy(
            GitLabPipelineReference.self,
            forKey: .pipeline
        )
        downstreamPipeline = container.decodeLossy(
            GitLabPipeline.self,
            forKey: .downstreamPipeline
        )
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case name
        case stage
        case status
        case allowFailure = "allow_failure"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case duration
        case queuedDuration = "queued_duration"
        case webURL = "web_url"
        case user
        case pipeline
        case downstreamPipeline =
            "downstream_pipeline"
    }
}

private nonisolated extension KeyedDecodingContainer {
    func decodeLossy<Value>(
        _ type: Value.Type,
        forKey key: Key
    ) -> Value?
    where Value: Decodable {
        do {
            return try decodeIfPresent(
                type,
                forKey: key
            )
        } catch {
            return nil
        }
    }

    func decodePositiveInt(
        forKey key: Key
    ) throws -> Int {
        let value = try decode(
            Int.self,
            forKey: key
        )
        guard value > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription:
                    "Identifier must be positive."
            )
        }
        return value
    }

    func decodePositiveIntIfPresent(
        forKey key: Key
    ) -> Int? {
        guard
            let value = decodeLossy(
                Int.self,
                forKey: key
            ),
            value > 0
        else {
            return nil
        }
        return value
    }

    func decodeNonnegativeIntIfPresent(
        forKey key: Key
    ) -> Int? {
        guard
            let value = decodeLossy(
                Int.self,
                forKey: key
            ),
            value >= 0
        else {
            return nil
        }
        return value
    }

    func decodeNonnegativeDoubleIfPresent(
        forKey key: Key
    ) -> Double? {
        guard
            let value = decodeLossy(
                Double.self,
                forKey: key
            ),
            value >= 0
        else {
            return nil
        }
        return value
    }

    func decodeNonemptyString(
        forKey key: Key
    ) throws -> String {
        let value = try decode(
            String.self,
            forKey: key
        )
        let normalized =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !normalized.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription:
                    "Value cannot be empty."
            )
        }
        return normalized
    }

    func decodeNonemptyStringIfPresent(
        forKey key: Key
    ) -> String? {
        guard
            let value = decodeLossy(
                String.self,
                forKey: key
            )
        else {
            return nil
        }
        let normalized =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        return normalized.isEmpty
            ? nil
            : normalized
    }
}
