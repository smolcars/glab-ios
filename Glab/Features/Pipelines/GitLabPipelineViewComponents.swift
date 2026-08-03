import SwiftUI

struct GitLabPipelineHistoryRow: View {
    let pipeline: GitLabPipeline

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            GitLabCIStatusIcon(
                status: pipeline.status
            )
            .padding(.top, 2)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(
                    pipeline.name
                    ?? "Pipeline \(pipeline.displayID)"
                )
                .font(
                    .glabBody.weight(.semibold)
                )
                .lineLimit(3)

                metadata
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            [
                pipeline.name
                    ?? "Pipeline \(pipeline.displayID)",
                pipeline.status.title,
                pipeline.ref,
                pipeline.shortSHA,
            ]
            .joined(separator: ", ")
        )
    }

    private var metadata: Text {
        let status =
            Text(pipeline.status.title)
            .foregroundStyle(
                pipeline.status.tint
            )
        let sha =
            Text(pipeline.shortSHA)
            .fontDesign(.monospaced)
        let relativeTime =
            pipeline.relativeTime
                .map { "  \($0)" }
                ?? ""
        return Text(
            "\(status)  \(pipeline.ref)  \(sha)\(relativeTime)"
        )
    }
}

struct GitLabPipelineHeader: View {
    let pipeline: GitLabPipeline

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            if let name = pipeline.name {
                Text(name)
                    .font(
                        .glabHeadline
                    )
            }

            HStack(spacing: 8) {
                GitLabCIStatusIcon(
                    status: pipeline.status
                )

                Text(pipeline.status.title)
                    .font(
                        .glabBody.weight(.semibold)
                    )
                    .foregroundStyle(
                        pipeline.status.tint
                    )

                Text(pipeline.displayID)
                    .font(
                        .caption
                            .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
            }

            HStack(
                alignment: .firstTextBaseline,
                spacing: 6
            ) {
                Image(
                    systemName:
                        "arrow.triangle.branch"
                )
                .accessibilityHidden(true)

                reference
                    .lineLimit(3)
            }
            .font(.glabSubheadline)
            .foregroundStyle(.secondary)

            if !pipeline.metadataSummary.isEmpty {
                Text(
                    pipeline.metadataSummary
                )
                .font(.glabCaption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityIdentifier(
            "pipelines.detail.header"
        )
    }

    private var reference: Text {
        let sha =
            Text(pipeline.shortSHA)
            .fontDesign(.monospaced)
        return Text(
            "\(pipeline.ref)  \(sha)"
        )
    }
}

struct GitLabPipelineJobRow: View {
    let row: GitLabPipelineStageRow

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            GitLabCIStatusIcon(
                status: row.status
            )
            .padding(.top, 2)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(row.name)
                    .font(
                        .glabBody.weight(.medium)
                    )
                    .lineLimit(3)

                Text(row.metadataSummary)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)

                if
                    let downstreamSummary =
                        row.downstreamSummary
                {
                    Text(downstreamSummary)
                        .font(.glabCaption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            row.accessibilityLabel
        )
        .accessibilityIdentifier(
            row.accessibilityIdentifier
        )
    }
}

struct GitLabCIStatusIcon: View {
    let status: GitLabCIStatus

    var body: some View {
        Image(
            systemName:
                status.systemImage
        )
        .font(.glabBody)
        .foregroundStyle(status.tint)
        .frame(width: 22)
        .accessibilityHidden(true)
    }
}

extension GitLabPipeline {
    var displayID: String {
        "#\(iid ?? id)"
    }

    var shortSHA: String {
        String(sha.prefix(8))
    }

    var detailCacheLifetime:
        GitLabPipelineCacheLifetime
    {
        status.isTerminal
            ? .completed
            : .active
    }

    var metadataSummary: String {
        var values: [String] = []
        if let source {
            values.append(
                source.replacingOccurrences(
                    of: "_",
                    with: " "
                )
            )
        }
        if let user {
            values.append(user.displayName)
        }
        if
            let duration,
            let formatted =
                GitLabDurationFormatter
                .string(seconds: duration)
        {
            values.append(formatted)
        }
        if
            let date =
                finishedAt
                ?? updatedAt
                ?? startedAt
                ?? createdAt
        {
            values.append(
                GitLabRelativeTimeFormatter
                    .string(from: date)
            )
        }
        return values.joined(
            separator: " · "
        )
    }

    var relativeTime: String? {
        guard
            let date = updatedAt ?? createdAt
        else {
            return nil
        }
        return GitLabRelativeTimeFormatter
            .string(from: date)
    }
}

extension GitLabPipelineStageRow {
    var allowsFailure: Bool {
        switch content {
        case let .job(job):
            job.allowFailure
        case let .triggerJob(job):
            job.allowFailure
        }
    }

    var durationText: String? {
        let duration:
            TimeInterval? =
            switch content {
            case let .job(job):
                job.duration
            case let .triggerJob(job):
                job.duration
            }
        guard let duration else {
            return nil
        }
        return GitLabDurationFormatter
            .string(seconds: duration)
    }

    var downstreamSummary: String? {
        guard
            case let .triggerJob(job) =
                content,
            let pipeline =
                job.downstreamPipeline
        else {
            return nil
        }
        return [
            pipeline.status.title,
            pipeline.ref,
            pipeline.shortSHA,
        ]
        .joined(separator: " · ")
    }

    var metadataSummary: String {
        var values: [String] = []
        if case .triggerJob = content {
            values.append("Child")
        }
        values.append(status.jobTitle)
        if attempt != .only {
            values.append(attempt.title)
        }
        if let durationText {
            values.append(durationText)
        }
        if allowsFailure {
            values.append("Allowed")
        }
        return values.joined(
            separator: " · "
        )
    }

    var accessibilityLabel: String {
        var values = [
            name,
            status.jobTitle,
        ]
        if case .triggerJob = content {
            values.append("Child pipeline")
        }
        if attempt != .only {
            values.append(attempt.title)
        }
        if allowsFailure {
            values.append("Failure allowed")
        }
        if let durationText {
            values.append(durationText)
        }
        if let downstreamSummary {
            values.append(downstreamSummary)
        }
        return values.joined(
            separator: ", "
        )
    }

    var accessibilityIdentifier: String {
        switch id {
        case let .job(id):
            "pipelines.detail.job.\(id)"
        case let .triggerJob(id):
            "pipelines.detail.triggerJob.\(id)"
        }
    }
}

extension GitLabPipelineJobAttempt {
    var title: String {
        switch self {
        case .only:
            ""
        case .latest:
            "Latest run"
        case .earlier:
            "Earlier run"
        }
    }
}

extension GitLabCIStatus {
    var systemImage: String {
        switch rawValue {
        case "created":
            "hourglass"
        case "waiting_for_resource",
             "waiting_for_callback":
            "hourglass"
        case "preparing":
            "wrench.and.screwdriver.fill"
        case "pending":
            "clock.fill"
        case "running":
            "play.circle.fill"
        case "canceling":
            "xmark.circle"
        case "scheduled":
            "calendar.badge.clock"
        case "manual":
            "hand.tap.fill"
        case "success":
            "checkmark.circle.fill"
        case "failed":
            "xmark.circle.fill"
        case "canceled":
            "slash.circle.fill"
        case "skipped":
            "forward.end.circle.fill"
        default:
            "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch rawValue {
        case "success":
            .green
        case "failed":
            .red
        case "canceled",
             "skipped":
            .secondary
        case "manual":
            .orange
        case "created",
             "waiting_for_resource",
             "preparing",
             "waiting_for_callback",
             "pending",
             "running",
             "canceling",
             "scheduled":
            .blue
        default:
            .secondary
        }
    }
}
