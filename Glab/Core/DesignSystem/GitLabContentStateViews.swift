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
        .gitLabAccessibilityAnnouncement(message)
        .accessibilityIdentifier("gitlab.loadingState")
    }
}

private struct GitLabAccessibilityAnnouncementModifier:
    ViewModifier
{
    let message: String

    @State private var announcedMessage: String?

    func body(content: Content) -> some View {
        content.task(id: message) {
            guard announcedMessage != message else {
                return
            }
            announcedMessage = message
            AccessibilityNotification
                .Announcement(message)
                .post()
        }
    }
}

extension View {
    func gitLabAccessibilityAnnouncement(
        _ message: String
    ) -> some View {
        modifier(
            GitLabAccessibilityAnnouncementModifier(
                message: message
            )
        )
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
    let presentation: GitLabRecoveryPresentation
    let retry: () -> Void

    init(
        error: GitLabSessionClientError,
        retry: @escaping () -> Void
    ) {
        presentation = GitLabRecoveryPresentation(
            error: error
        )
        self.retry = retry
    }

    init(
        message: String,
        retry: @escaping () -> Void
    ) {
        presentation = .generic(message: message)
        self.retry = retry
    }

    var body: some View {
        ContentUnavailableView {
            Label(
                presentation.title,
                systemImage: presentation.systemImage
            )
        } description: {
            Text(presentation.message)
        } actions: {
            if
                presentation.retryAvailability
                    != .unavailable
            {
                GitLabRetryControl(
                    availability:
                        presentation.retryAvailability,
                    action: retry
                ) {
                    Label(
                        "Try Again",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.glass)
                .tint(.orange)
                .accessibilityIdentifier(
                    "gitlab.retryButton"
                )
            }
        }
    }
}

struct GitLabRetryControl<Label: View>: View {
    let availability:
        GitLabRecoveryPresentation.RetryAvailability
    let action: () -> Void
    let label: Label

    @State private var isWaiting: Bool

    init(
        availability:
            GitLabRecoveryPresentation.RetryAvailability,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.availability = availability
        self.action = action
        self.label = label()
        _isWaiting = State(
            initialValue:
                availability.waitSeconds.map { $0 > 0 }
                    ?? false
        )
    }

    @ViewBuilder
    var body: some View {
        if availability == .unavailable {
            label
        } else {
            Button(action: action) {
                label
            }
            .disabled(isWaiting)
            .task(id: availability) {
                await waitIfNeeded()
            }
        }
    }

    private func waitIfNeeded() async {
        guard
            let seconds = availability.waitSeconds,
            seconds > 0
        else {
            isWaiting = false
            return
        }

        isWaiting = true

        do {
            try await Task.sleep(
                for: .seconds(seconds)
            )
        } catch {
            return
        }

        guard !Task.isCancelled else {
            return
        }
        isWaiting = false
    }
}

private extension GitLabRecoveryPresentation.RetryAvailability {
    var waitSeconds: Int? {
        guard case let .after(seconds) = self else {
            return nil
        }
        return seconds
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
