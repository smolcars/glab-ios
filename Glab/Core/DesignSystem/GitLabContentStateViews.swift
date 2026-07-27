import SwiftUI

struct GitLabLoadingStateView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(maxWidth: index.isMultiple(of: 2) ? 210 : 170)
                            .frame(height: 13)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .frame(maxWidth: index.isMultiple(of: 2) ? 145 : 190)
                            .frame(height: 10)
                    }
                }
                .padding(.vertical, 14)

                if index < 3 {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}

struct GitLabEmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

struct GitLabRetryStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                "Couldn’t load GitLab",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise") {
                retry()
            }
            .buttonStyle(.glass)
            .tint(.orange)
        }
    }
}

struct GitLabContentStateScrollView<Content: View>: View {
    private let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity)
                .frame(minHeight: 430)
                .padding(.horizontal, 20)
        }
    }
}

#Preview("Loading") {
    GitLabLoadingStateView(message: "Loading GitLab")
        .padding()
}

#Preview("Empty") {
    GitLabEmptyStateView(
        title: "No Todos",
        message: "There is nothing requiring your attention.",
        systemImage: "checklist"
    )
}

#Preview("Retry") {
    GitLabRetryStateView(
        message: "Check your connection and try again.",
        retry: {}
    )
}
