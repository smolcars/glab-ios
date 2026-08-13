import Foundation
import Observation

nonisolated enum TodoCatchUpPhase:
    Equatable,
    Sendable
{
    case idle
    case loading
    case active
    case completed
    case failed(GitLabSessionClientError)
}

@MainActor
@Observable
final class TodoCatchUpModel {
    private(set) var phase =
        TodoCatchUpPhase.idle
    private(set) var keptCount = 0
    private(set) var completedCount = 0
    private(set) var completingTodoID: Int?
    private(set) var completionFailure:
        GitLabSessionClientError?

    @ObservationIgnored
    private let todosModel: TodosModel
    private var remainingTodoIDs: [Int] = []
    private var handledTodoIDs: Set<Int> = []
    private var snapshotTodosByID:
        [Int: GitLabTodo] = [:]

    init(todosModel: TodosModel) {
        self.todosModel = todosModel
    }

    var visibleTodos: [GitLabTodo] {
        remainingTodoIDs.prefix(3).compactMap {
            todo(id: $0)
        }
    }

    var currentTodo: GitLabTodo? {
        remainingTodoIDs.first.flatMap(todo(id:))
    }

    var remainingCount: Int {
        remainingTodoIDs.count
    }

    var isCompleting: Bool {
        completingTodoID != nil
    }

    var canCompleteTodos: Bool {
        todosModel.canComplete
    }

    var canMarkDone: Bool {
        canCompleteTodos
            && currentTodo != nil
            && !isCompleting
    }

    var shouldShowHomeShortcut: Bool {
        switch phase {
        case .idle, .loading:
            return todosModel.hasPendingTodos
        case .active:
            return currentTodo != nil
                || isCompleting
        case .completed:
            return !unhandledPendingTodos.isEmpty
        case .failed:
            return true
        }
    }

    var homeShortcutCount: Int? {
        switch phase {
        case .active:
            return remainingCount
        case .completed:
            return unhandledPendingTodos.count
        case .idle, .loading, .failed:
            return todosModel.pendingBadgeCount
        }
    }

    func startIfNeeded() async {
        switch phase {
        case .loading, .active:
            return
        case .completed:
            guard !unhandledPendingTodos.isEmpty else {
                return
            }
        case .idle, .failed:
            break
        }

        phase = .loading
        completionFailure = nil
        completingTodoID = nil

        await todosModel.loadAllPendingTodos()
        guard !Task.isCancelled else {
            phase = .idle
            return
        }
        if let error = todosModel.pendingTodosLoadError {
            phase = .failed(error)
            return
        }

        let todos = unhandledPendingTodos
        snapshotTodosByID.merge(
            todos.reduce(into: [:]) {
                $0[$1.id] = $1
            },
            uniquingKeysWith: { _, latest in latest }
        )
        remainingTodoIDs = todos.map(\.id)
        keptCount = 0
        completedCount = 0
        phase = remainingTodoIDs.isEmpty
            ? .completed
            : .active
    }

    func keepCurrent() {
        guard
            phase == .active,
            !isCompleting,
            let todoID = remainingTodoIDs.first
        else {
            return
        }

        remainingTodoIDs.removeFirst()
        handledTodoIDs.insert(todoID)
        keptCount += 1
        completionFailure = nil
        finishIfNeeded()
    }

    func markCurrentDone() async {
        guard
            phase == .active,
            canMarkDone,
            let todo = currentTodo
        else {
            return
        }

        remainingTodoIDs.removeFirst()
        completingTodoID = todo.id
        completionFailure = nil

        await todosModel.markDone(todo)
        guard !Task.isCancelled else {
            restore(todoID: todo.id)
            return
        }

        if
            case let .markDone(id, error) =
                todosModel.mutationFailure,
            id == todo.id
        {
            completionFailure = error
            restore(todoID: todo.id)
            return
        }

        if todosModel.pendingTodos.contains(
            where: { $0.id == todo.id }
        ) {
            restore(todoID: todo.id)
            return
        }

        handledTodoIDs.insert(todo.id)
        completedCount += 1
        completingTodoID = nil
        finishIfNeeded()
    }

    private var unhandledPendingTodos:
        [GitLabTodo]
    {
        todosModel.pendingTodos.filter {
            !handledTodoIDs.contains($0.id)
        }
    }

    private func todo(
        id: Int
    ) -> GitLabTodo? {
        todosModel.pendingTodo(id: id)
            ?? snapshotTodosByID[id]
    }

    private func restore(todoID: Int) {
        if !remainingTodoIDs.contains(todoID) {
            remainingTodoIDs.insert(todoID, at: 0)
        }
        completingTodoID = nil
        phase = .active
    }

    private func finishIfNeeded() {
        guard remainingTodoIDs.isEmpty else {
            return
        }
        phase = .completed
    }
}
