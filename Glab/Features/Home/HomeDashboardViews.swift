import SwiftUI

struct HomeCatchUpShortcutRow: View {
    let count: Int?

    var body: some View {
        HStack(spacing: 14) {
            GitLabIconView(.todoDone)
                .foregroundStyle(Color.glabAccent)
                .frame(width: 38, height: 38)
                .background(
                    Color.glabAccent.opacity(0.12),
                    in: .rect(cornerRadius: 10)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Catch Up")
                    .font(.glabBody.weight(.semibold))

                Text("Swipe through pending Todos")
                    .font(.glabSubheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.glabSubheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.glabAccent)
                    .accessibilityLabel(
                        "\(count) Todos"
                    )
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Catch Up")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            "Opens a swipeable Todo queue."
        )
    }

    private var accessibilityValue: String {
        guard let count, count > 0 else {
            return "Pending Todos available"
        }
        return "\(count) pending Todos"
    }
}

struct HomeWorkShortcutRow: View {
    let section: HomeDashboardSection
    let presentation: HomeDashboardRowPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        icon
                        Spacer()
                        statusAccessory
                    }

                    textContent
                }
            } else {
                HStack(spacing: 14) {
                    icon
                    textContent
                    Spacer(minLength: 8)
                    statusAccessory
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.title)
        .accessibilityValue(presentation.accessibilityValue)
    }

    private var icon: some View {
        Group {
            if let gitLabIcon = section.gitLabIcon {
                GitLabIconView(gitLabIcon)
            } else {
                Image(systemName: section.systemImage)
                    .font(.glabHeadline)
            }
        }
            .foregroundStyle(Color.glabAccent)
            .frame(width: 38, height: 38)
            .background(
                Color.glabAccent.opacity(0.12),
                in: .rect(cornerRadius: 10)
            )
            .accessibilityHidden(true)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(section.title)
                .font(.glabBody.weight(.medium))

            Text(presentation.subtitle)
                .font(.glabSubheadline)
                .foregroundStyle(
                    presentation.status == .failed
                        ? AnyShapeStyle(.red)
                        : AnyShapeStyle(.secondary)
                )
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var statusAccessory: some View {
        Group {
            if presentation.status == .loading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else if presentation.status == .failed {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            } else if presentation.status == .stale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
        }
    }
}
