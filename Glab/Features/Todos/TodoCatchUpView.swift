import SafariServices
import SwiftUI

typealias TodoCatchUpAuthenticationFailureHandler =
    @MainActor @Sendable
    (GitLabSessionClientError) async -> Void

struct TodoCatchUpView: View {
    let model: TodoCatchUpModel
    let authenticationFailureHandler:
        TodoCatchUpAuthenticationFailureHandler

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.gitLabNativeNavigationAction)
    private var navigate
    @Environment(\.layoutDirection)
    private var layoutDirection
    @State private var dragOffset = CGSize.zero
    @State private var deckWidth: CGFloat = 320
    @State private var isThrowingCard = false
    @State private var thresholdDecision:
        TodoCatchUpDecision?
    @State private var thresholdFeedback = 0
    @State private var webDestination:
        TodoCatchUpWebDestination?

    init(
        model: TodoCatchUpModel,
        authenticationFailureHandler:
            @escaping TodoCatchUpAuthenticationFailureHandler =
                { _ in }
    ) {
        self.model = model
        self.authenticationFailureHandler =
            authenticationFailureHandler
    }

    var body: some View {
        ZStack {
            Color.glabCanvas
                .ignoresSafeArea()

            content
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if
                model.phase == .active,
                model.currentTodo != nil
            {
                actionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .task {
            await start()
        }
        .sheet(item: $webDestination) {
            destination in
            TodoCatchUpSafariView(
                url: destination.url
            )
            .ignoresSafeArea()
        }
        .sensoryFeedback(
            .selection,
            trigger: thresholdFeedback
        )
        .sensoryFeedback(
            .success,
            trigger: model.completedCount
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            loadingState
        case let .failed(error):
            GitLabRetryStateView(error: error) {
                Task {
                    await start()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .active:
            activeContent
        case .completed:
            completedState
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing your Todos…")
                .font(.glabHeadline)
            Text("Loading the current queue in order.")
                .font(.glabSubheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .gitLabAccessibilityAnnouncement(
            "Preparing Todo Catch Up"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("catchUp.loading")
    }

    private var activeContent: some View {
        VStack(spacing: 12) {
            guidance

            if let failure = model.completionFailure {
                completionFailure(failure)
            }

            GeometryReader { proxy in
                deck(in: proxy.size)
                    .onAppear {
                        deckWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) {
                        _, width in
                        deckWidth = width
                    }
            }
            .accessibilityIdentifier("catchUp.deck")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var guidance: some View {
        VStack(spacing: 5) {
            Text("Swipe or use the buttons")
                .font(.glabSubheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if !model.canCompleteTodos {
                Label(
                    "Done requires API write access",
                    systemImage: "lock.fill"
                )
                .font(.glabCaption)
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func completionFailure(
        _ error: GitLabSessionClientError
    ) -> some View {
        let presentation =
            GitLabRecoveryPresentation(error: error)
        return Label {
            Text(presentation.title)
                .lineLimit(2)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.glabFootnote.weight(.medium))
        .foregroundStyle(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color.red.opacity(0.1),
            in: .capsule
        )
        .gitLabAccessibilityAnnouncement(
            presentation.title
        )
        .accessibilityIdentifier(
            "catchUp.completionError"
        )
    }

    private func deck(
        in size: CGSize
    ) -> some View {
        ZStack {
            ForEach(
                Array(
                    model.visibleTodos
                        .enumerated()
                        .reversed()
                ),
                id: \.element.id
            ) { entry in
                if entry.offset == 0 {
                    interactiveCard(
                        entry.element,
                        in: size
                    )
                } else {
                    TodoCatchUpCard(
                        todo: entry.element,
                        decision: nil,
                        decisionProgress: 0
                    )
                    .scaleEffect(
                        1
                            - CGFloat(entry.offset)
                            * 0.025
                    )
                    .offset(
                        y:
                            CGFloat(entry.offset)
                            * 11
                    )
                    .opacity(
                        1
                            - Double(entry.offset)
                            * 0.12
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.bottom, 22)
        .animation(
            reduceMotion ? nil : .snappy,
            value: model.currentTodo?.id
        )
    }

    private func interactiveCard(
        _ todo: GitLabTodo,
        in size: CGSize
    ) -> some View {
        TodoCatchUpCard(
            todo: todo,
            decision: dragDecision,
            decisionProgress: dragProgress
        )
        .offset(dragOffset)
        .rotationEffect(
            reduceMotion
                ? .zero
                : .degrees(
                    Double(dragOffset.width / 32)
                )
        )
        .contentShape(.rect(cornerRadius: 24))
        .onTapGesture {
            open(todo)
        }
        .simultaneousGesture(
            dragGesture(in: size)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityLabel(for: todo)
        )
        .accessibilityHint(
            openHint(for: todo)
        )
        .accessibilityAddTraits(
            canOpen(todo) ? .isButton : []
        )
        .accessibilityAction {
            open(todo)
        }
        .accessibilityAction(
            named: "Keep for later"
        ) {
            commit(.keep)
        }
        .accessibilityAction(
            named: "Mark done"
        ) {
            guard model.canMarkDone else {
                return
            }
            commit(.done)
        }
        .accessibilityIdentifier(
            "catchUp.card.\(todo.id)"
        )
    }

    private func dragGesture(
        in size: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard
                    !isThrowingCard,
                    abs(value.translation.width)
                        > abs(value.translation.height)
                else {
                    return
                }

                dragOffset = CGSize(
                    width: value.translation.width,
                    height: value.translation.height * 0.08
                )
                updateThresholdFeedback()
            }
            .onEnded { value in
                guard !isThrowingCard else {
                    return
                }
                let isHorizontal =
                    abs(value.translation.width)
                    > abs(value.translation.height)
                let projectedWidth =
                    value.predictedEndTranslation.width
                guard
                    isHorizontal,
                    abs(value.translation.width) >= 96
                        || abs(projectedWidth) >= 180
                else {
                    resetDrag()
                    return
                }

                commit(
                    decision(
                        for: value.translation.width
                    )
                )
            }
    }

    private var actionBar: some View {
        Group {
            if
                #available(iOS 26.0, *),
                !reduceTransparency
            {
                actionButtons
                    .padding(6)
                    .glassEffect(
                        .regular.interactive(),
                        in: .capsule
                    )
            } else {
                actionButtons
                    .padding(6)
                    .background(
                        Color.glabRaisedSurface,
                        in: .capsule
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.glabSeparator,
                                lineWidth: 1
                            )
                    }
            }
        }
        .shadow(
            color: .black.opacity(0.12),
            radius: 12,
            y: 5
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button {
                commit(.keep)
            } label: {
                Label(
                    "Keep",
                    systemImage: "bookmark"
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(isThrowingCard || model.isCompleting)
            .accessibilityLabel("Keep for later")
            .accessibilityHint(
                "Leaves this Todo pending and shows the next one."
            )
            .accessibilityIdentifier("catchUp.keepButton")

            Divider()
                .frame(height: 28)

            Button {
                commit(.done)
            } label: {
                Group {
                    if model.isCompleting {
                        ProgressView()
                    } else {
                        Label(
                            "Done",
                            systemImage: "checkmark"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.glabAccent)
            .disabled(
                isThrowingCard
                    || !model.canMarkDone
            )
            .accessibilityHint(doneAccessibilityHint)
            .accessibilityIdentifier("catchUp.doneButton")
        }
        .font(.glabBody.weight(.semibold))
    }

    private var completedState: some View {
        ContentUnavailableView {
            Label {
                Text("You’re caught up")
            } icon: {
                GitLabIconView(
                    .todoDone,
                    pointSize: 34
                )
                .foregroundStyle(Color.glabAccent)
            }
        } description: {
            Text(completedSummary)
        }
        .gitLabAccessibilityAnnouncement(
            "Todo Catch Up complete. \(completedSummary)"
        )
        .accessibilityIdentifier("catchUp.completed")
    }

    private var navigationTitle: String {
        switch model.phase {
        case .active:
            "\(model.remainingCount) left"
        case .completed:
            "Caught up"
        case .idle, .loading, .failed:
            "Catch Up"
        }
    }

    private var completedSummary: String {
        switch (
            model.completedCount,
            model.keptCount
        ) {
        case let (done, kept) where done > 0 && kept > 0:
            "\(done) done · \(kept) kept for later"
        case let (done, _) where done > 0:
            "\(done) marked done"
        case let (_, kept) where kept > 0:
            "\(kept) kept for later"
        default:
            "No pending Todos remain."
        }
    }

    private var doneAccessibilityHint: String {
        if !model.canCompleteTodos {
            return "Requires API write access."
        }
        if model.isCompleting {
            return "The current Todo is being marked done."
        }
        return "Marks this Todo done on GitLab and shows the next one."
    }

    private var dragProgress: Double {
        min(1, abs(dragOffset.width) / 120)
    }

    private var dragDecision:
        TodoCatchUpDecision?
    {
        guard abs(dragOffset.width) > 18 else {
            return nil
        }
        return decision(for: dragOffset.width)
    }

    private func decision(
        for horizontalOffset: CGFloat
    ) -> TodoCatchUpDecision {
        let movesTowardTrailing =
            layoutDirection == .leftToRight
                ? horizontalOffset > 0
                : horizontalOffset < 0
        return movesTowardTrailing ? .done : .keep
    }

    private func throwDirection(
        for decision: TodoCatchUpDecision
    ) -> CGFloat {
        let trailing: CGFloat =
            layoutDirection == .leftToRight ? 1 : -1
        return decision == .done
            ? trailing
            : -trailing
    }

    private func updateThresholdFeedback() {
        let nextDecision:
            TodoCatchUpDecision? =
                abs(dragOffset.width) >= 96
                ? decision(for: dragOffset.width)
                : nil
        if
            thresholdDecision == nil,
            nextDecision != nil
        {
            thresholdFeedback += 1
        }
        thresholdDecision = nextDecision
    }

    private func resetDrag() {
        thresholdDecision = nil
        guard !reduceMotion else {
            dragOffset = .zero
            return
        }
        withAnimation(.snappy) {
            dragOffset = .zero
        }
    }

    private func commit(
        _ decision: TodoCatchUpDecision
    ) {
        guard
            !isThrowingCard,
            model.currentTodo != nil,
            decision != .done
                || model.canMarkDone
        else {
            return
        }

        isThrowingCard = true
        thresholdDecision = nil

        guard !reduceMotion else {
            Task {
                await complete(decision)
            }
            return
        }

        let distance = max(deckWidth + 80, 400)
        let destination = CGSize(
            width:
                throwDirection(for: decision)
                * distance,
            height: -18
        )

        withAnimation(
            .spring(
                duration: 0.34,
                bounce: 0.08
            ),
            completionCriteria: .logicallyComplete
        ) {
            dragOffset = destination
        } completion: {
            Task {
                await complete(decision)
            }
        }
    }

    private func complete(
        _ decision: TodoCatchUpDecision
    ) async {
        switch decision {
        case .keep:
            model.keepCurrent()
        case .done:
            await model.markCurrentDone()
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = .zero
            isThrowingCard = false
        }

        if
            let error = model.completionFailure,
            error.requiresReauthentication
        {
            await authenticationFailureHandler(error)
        }
    }

    private func start() async {
        await model.startIfNeeded()
        guard
            case let .failed(error) = model.phase,
            error.requiresReauthentication
        else {
            return
        }
        await authenticationFailureHandler(error)
    }

    private func canOpen(
        _ todo: GitLabTodo
    ) -> Bool {
        todo.nativeRoute != nil
            || todo.safeTargetURL != nil
    }

    private func open(
        _ todo: GitLabTodo
    ) {
        guard !isThrowingCard else {
            return
        }
        if let route = todo.nativeRoute {
            switch route {
            case let .issue(issueRoute):
                navigate(.issue(issueRoute))
            case let .mergeRequest(mergeRequestRoute):
                navigate(
                    .mergeRequest(
                        mergeRequestRoute
                    )
                )
            }
        } else if let url = todo.safeTargetURL {
            webDestination =
                TodoCatchUpWebDestination(
                    url: url
                )
        }
    }

    private func openHint(
        for todo: GitLabTodo
    ) -> String {
        canOpen(todo)
            ? "Opens this Todo. Back returns to Catch Up."
            : "No destination is available for this Todo."
    }

    private func accessibilityLabel(
        for todo: GitLabTodo
    ) -> String {
        var parts = [
            todo.targetType.title,
            todo.projectTitle,
            todo.title,
        ]
        if let body = todo.catchUpBody {
            parts.append(body)
        }
        parts.append(todo.action.title)
        parts.append("By \(todo.authorTitle)")
        return parts.joined(separator: ", ")
    }
}

private enum TodoCatchUpDecision:
    Equatable
{
    case keep
    case done

    var title: String {
        switch self {
        case .keep:
            "Keep"
        case .done:
            "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .keep:
            "bookmark.fill"
        case .done:
            "checkmark"
        }
    }

    var color: Color {
        switch self {
        case .keep:
            .secondary
        case .done:
            .glabAccent
        }
    }
}

private struct TodoCatchUpCard: View {
    let todo: GitLabTodo
    let decision: TodoCatchUpDecision?
    let decisionProgress: Double

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(18)

            Divider()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    Text(todo.title)
                        .font(.glabTitle2.bold())
                        .foregroundStyle(.primary)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                    if let body = todo.catchUpBody {
                        Text(body)
                            .font(.glabBody)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(18)
            }
            .scrollIndicators(.hidden)

            Divider()

            footer
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.glabRaisedSurface,
            in: .rect(cornerRadius: 24)
        )
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    Color.glabSeparator,
                    lineWidth: 1
                )
        }
        .overlay(alignment: .top) {
            decisionBadge
                .padding(.top, 68)
        }
        .shadow(
            color: .black.opacity(0.16),
            radius: 18,
            y: 10
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            typeIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.targetType.title)
                    .font(.glabSubheadline.weight(.semibold))
                    .foregroundStyle(Color.glabAccent)

                Text(todo.projectTitle)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(
                        dynamicTypeSize.isAccessibilitySize
                            ? 2
                            : 1
                    )
            }

            Spacer(minLength: 8)

            Text(
                GitLabRelativeTimeFormatter.string(
                    from: todo.updatedAt
                )
            )
            .font(.glabCaption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let author = todo.author {
                GitLabUserAvatar(
                    user: author.summary,
                    size: 26
                )
                .accessibilityHidden(true)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.authorTitle)
                    .font(.glabFootnote.weight(.medium))
                    .lineLimit(1)

                Text(todo.action.title)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if
                todo.nativeRoute != nil
                    || todo.safeTargetURL != nil
            {
                Image(systemName: "arrow.up.right")
                    .font(.glabCaption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var typeIcon: some View {
        Group {
            if let gitLabIcon = todo.targetType.gitLabIcon {
                GitLabIconView(gitLabIcon)
            } else {
                Image(
                    systemName:
                        todo.targetType.systemImage
                )
                .font(.glabCallout.weight(.semibold))
            }
        }
        .foregroundStyle(Color.glabAccent)
        .frame(width: 40, height: 40)
        .background(
            Color.glabAccent.opacity(0.12),
            in: .rect(cornerRadius: 11)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var decisionBadge: some View {
        if let decision {
            Label(
                decision.title,
                systemImage: decision.systemImage
            )
            .font(.glabTitle3.bold())
            .foregroundStyle(decision.color)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                .regularMaterial,
                in: .capsule
            )
            .opacity(decisionProgress)
            .scaleEffect(0.9 + decisionProgress * 0.1)
            .accessibilityHidden(true)
        }
    }
}

private struct TodoCatchUpWebDestination:
    Identifiable
{
    let url: URL

    var id: URL { url }
}

private struct TodoCatchUpSafariView:
    UIViewControllerRepresentable
{
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> SFSafariViewController {
        let controller = SFSafariViewController(
            url: url
        )
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(
        _ uiViewController:
            SFSafariViewController,
        context: Context
    ) {}
}

private extension GitLabTodo {
    var catchUpBody: String? {
        if let displayBody {
            return displayBody
        }
        guard
            let description = target?.description?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !description.isEmpty,
            description != title
        else {
            return nil
        }
        return description
    }
}
