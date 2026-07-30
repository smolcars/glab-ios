import SwiftUI

private struct GitLabMentionSearchRequest:
    Equatable,
    Hashable
{
    let projectID: Int
    let query: String
}

struct GitLabMentionTextEditor<Editor: View>:
    View
{
    @Binding private var text: String
    @State private var selection:
        TextSelection?
    @State private var members:
        [GitLabProjectMember] = []
    @State private var loadedRequest:
        GitLabMentionSearchRequest?
    @State private var loadingRequest:
        GitLabMentionSearchRequest?

    private let projectID: Int?
    private let editor:
        (
            Binding<String>,
            Binding<TextSelection?>
        ) -> Editor

    @Environment(\.gitLabMentionService)
    private var mentionService
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    init(
        text: Binding<String>,
        projectID: Int?,
        @ViewBuilder editor:
            @escaping (
                Binding<String>,
                Binding<TextSelection?>
            ) -> Editor
    ) {
        _text = text
        self.projectID = projectID
        self.editor = editor
    }

    var body: some View {
        let context = activeQuery
        let request = context.flatMap {
            searchRequest(for: $0)
        }
        let presentation =
            panelPresentation(
                for: request
            )

        ZStack(alignment: .bottom) {
            editor($text, $selection)

            if presentation != .hidden {
                Group {
                    switch presentation {
                    case .hidden:
                        EmptyView()
                    case .loading:
                        GitLabMentionLoadingView()
                    case .suggestions:
                        GitLabMentionSuggestionsView(
                            members: members,
                            select: insert
                        )
                    }
                }
                .glassEffect(
                    .regular,
                    in: .rect(
                        cornerRadius: 18
                    )
                )
                .glassEffectTransition(
                    .materialize
                )
                .padding(10)
                .shadow(
                    color:
                        .black.opacity(0.16),
                    radius: 18,
                    y: 8
                )
                .transition(
                    .opacity.combined(
                        with: .scale(
                            scale: 0.96,
                            anchor: .bottom
                        )
                    )
                )
                .zIndex(1)
            }
        }
        .animation(
            reduceMotion
                ? nil
                : .snappy(duration: 0.22),
            value: presentation
        )
        .onChange(of: request) {
            _, newRequest in
            members = []
            loadedRequest = nil
            if
                loadingRequest
                    != newRequest
            {
                loadingRequest = nil
            }
        }
        .task(id: request) {
            await search(request)
        }
    }

    private var activeQuery:
        GitLabMentionQuery?
    {
        GitLabMentionQuery.active(
            in: text,
            selection: selectedRange
        )
    }

    private var selectedRange:
        Range<String.Index>?
    {
        guard
            let selection,
            case let .selection(range) =
                selection.indices
        else {
            return nil
        }
        return range
    }

    private func panelPresentation(
        for request:
            GitLabMentionSearchRequest?
    ) -> GitLabMentionPanelPresentation {
        if
            loadingRequest == request,
            request != nil
        {
            return .loading
        }
        if
            loadedRequest == request,
            !members.isEmpty
        {
            return .suggestions
        }
        return .hidden
    }

    private func searchRequest(
        for query: GitLabMentionQuery
    ) -> GitLabMentionSearchRequest? {
        guard let projectID else {
            return nil
        }
        return GitLabMentionSearchRequest(
            projectID: projectID,
            query: query.query
        )
    }

    private func search(
        _ request:
            GitLabMentionSearchRequest?
    ) async {
        guard let request else {
            return
        }

        do {
            try await Task.sleep(
                for: .milliseconds(250)
            )
            try Task.checkCancellation()
            loadingRequest = request
            let response =
                try await mentionService
                    .searchProjectMembers(
                        projectID:
                            request.projectID,
                        query: request.query
                    )
            try Task.checkCancellation()
            members = response
                .filter(\.isActive)
                .filter {
                    !$0.username.isEmpty
                }
                .prefix(10)
                .map { $0 }
            loadedRequest = request
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            members = []
            loadedRequest = request
        }

        if loadingRequest == request {
            loadingRequest = nil
        }
    }

    private func insert(
        _ member: GitLabProjectMember
    ) {
        guard
            let insertion =
                activeQuery?.inserting(
                    username: member.username,
                    into: text
                )
        else {
            return
        }

        text = insertion.text
        selection = TextSelection(
            insertionPoint:
                insertion.cursor
        )
        members = []
        loadedRequest = nil
        loadingRequest = nil
    }
}

private enum GitLabMentionPanelPresentation:
    Equatable
{
    case hidden
    case loading
    case suggestions
}

private struct GitLabMentionLoadingView:
    View
{
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Finding people…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityIdentifier(
            "mentionAutocomplete.loading"
        )
    }
}

private struct GitLabMentionSuggestionsView:
    View
{
    let members: [GitLabProjectMember]
    let select:
        (GitLabProjectMember) -> Void

    var body: some View {
        let displayedMembers =
            Array(members.prefix(3))

        VStack(spacing: 0) {
            ForEach(displayedMembers) {
                member in
                let summary = member.summary

                Button {
                    select(member)
                } label: {
                    HStack(spacing: 10) {
                        GitLabUserAvatar(
                            user: summary,
                            size: 30
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 1
                        ) {
                            Text(
                                summary.displayName
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .medium
                                    )
                            )
                            .foregroundStyle(
                                .primary
                            )
                            .lineLimit(1)

                            Text(
                                "@\(member.username)"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                            .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(summary.displayName), @\(member.username)"
                )
                .accessibilityHint(
                    "Inserts this mention"
                )
                .accessibilityIdentifier(
                    "mentionAutocomplete"
                        + ".\(member.username)"
                )

                if
                    member.id
                        != displayedMembers.last?
                        .id
                {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(
            children: .contain
        )
        .accessibilityIdentifier(
            "mentionAutocomplete.suggestions"
        )
    }
}
