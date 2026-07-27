import SwiftUI

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
        Image(systemName: section.systemImage)
            .font(.headline)
            .foregroundStyle(.orange)
            .frame(width: 38, height: 38)
            .background(
                Color.orange.opacity(0.12),
                in: .rect(cornerRadius: 10)
            )
            .accessibilityHidden(true)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(section.title)
                .font(.body.weight(.medium))

            Text(presentation.subtitle)
                .font(.subheadline)
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
            }
        }
    }
}

struct HomeDashboardListView: View {
    let section: HomeDashboardSection
    let model: HomeDashboardModel
    let refresh: () async -> Void

    var body: some View {
        Group {
            switch model.state(for: section) {
            case .idle, .loading:
                loadingView
            case let .loaded(items) where items.isEmpty:
                GitLabEmptyStateView(
                    title: section.emptyMessage,
                    message: "Pull to refresh your GitLab work.",
                    systemImage: section.systemImage
                )
            case let .loaded(items):
                List(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body.weight(.medium))

                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.insetGrouped)
            case let .failed(error):
                GitLabRetryStateView(
                    message: error.description
                ) {
                    Task {
                        await refresh()
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await refresh()
        }
        .accessibilityIdentifier(
            "home.list.\(section.rawValue)"
        )
    }

    private var loadingView: some View {
        ScrollView {
            GitLabLoadingStateView(
                message: "Loading \(section.title)"
            )
            .padding(20)
        }
    }
}
