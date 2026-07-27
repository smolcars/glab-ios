import SwiftUI

struct HomeWorkShortcutRow: View {
    let section: HomeDashboardSection
    let presentation: HomeDashboardRowPresentation

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(
                    Color.orange.opacity(0.12),
                    in: .rect(cornerRadius: 10)
                )
                .accessibilityHidden(true)

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

            Spacer(minLength: 8)

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
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.title)
        .accessibilityValue(presentation.accessibilityValue)
    }
}

struct HomeDashboardListView: View {
    let section: HomeDashboardSection
    let model: HomeDashboardModel

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
                        await model.refresh()
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await model.refresh()
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
