import Foundation

nonisolated struct GitLabTodoNotificationCheckpoint:
    Codable,
    Equatable,
    Sendable
{
    let observedTodoIDs: Set<Int>
    let newestObservedCreationDate: Date?

    func observing(
        todoIDs: some Sequence<Int>
    ) -> Self {
        Self(
            observedTodoIDs:
                observedTodoIDs.union(todoIDs),
            newestObservedCreationDate:
                newestObservedCreationDate
        )
    }
}

nonisolated struct GitLabTodoNotificationDetection:
    Equatable,
    Sendable
{
    let newTodos: [GitLabTodo]
    let checkpoint: GitLabTodoNotificationCheckpoint

    static func evaluate(
        todos: [GitLabTodo],
        checkpoint:
            GitLabTodoNotificationCheckpoint?
    ) -> Self {
        let observedTodoIDs =
            checkpoint?.observedTodoIDs ?? []
        let newestObservedCreationDate =
            (
                todos.map(\.createdAt)
                    + [
                        checkpoint?
                            .newestObservedCreationDate,
                    ]
                    .compactMap { $0 }
            )
            .max()
        let newTodos: [GitLabTodo]

        if let checkpoint {
            newTodos = todos.filter {
                guard
                    !observedTodoIDs
                        .contains($0.id)
                else {
                    return false
                }
                guard
                    let watermark =
                        checkpoint
                            .newestObservedCreationDate
                else {
                    return true
                }
                return $0.createdAt >= watermark
            }
        } else {
            newTodos = []
        }

        return Self(
            newTodos: newTodos,
            checkpoint:
                GitLabTodoNotificationCheckpoint(
                    observedTodoIDs:
                        observedTodoIDs.union(
                            todos.map(\.id)
                        ),
                    newestObservedCreationDate:
                        newestObservedCreationDate
                )
        )
    }
}
