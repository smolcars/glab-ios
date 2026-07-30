import Foundation
import Testing
@testable import Glab

@Suite("GitLab Todo notification detection")
struct GitLabTodoNotificationDetectionTests {
    @Test("First scan establishes a silent baseline")
    func firstScanIsSilent() {
        let todos = [
            makeTestTodo(id: 1),
            makeTestTodo(id: 2),
        ]

        let result =
            GitLabTodoNotificationDetection
                .evaluate(
                    todos: todos,
                    checkpoint: nil
                )

        #expect(result.newTodos.isEmpty)
        #expect(
            result.checkpoint.observedTodoIDs
                == [1, 2]
        )
        #expect(
            result.checkpoint
                .newestObservedCreationDate
                == todos[0].createdAt
        )
    }

    @Test("Later scans report only unseen IDs")
    func reportsOnlyUnseenIDs() {
        let checkpoint =
            GitLabTodoNotificationCheckpoint(
                observedTodoIDs: [1, 2],
                newestObservedCreationDate:
                    makeTestTodo().createdAt
            )

        let result =
            GitLabTodoNotificationDetection
                .evaluate(
                    todos: [
                        makeTestTodo(id: 2),
                        makeTestTodo(id: 3),
                        makeTestTodo(id: 4),
                    ],
                    checkpoint: checkpoint
                )

        #expect(result.newTodos.map(\.id) == [3, 4])
        #expect(
            result.checkpoint.observedTodoIDs
                == [1, 2, 3, 4]
        )
    }

    @Test("Does not report older Todos that surface later")
    func ignoresLateOlderTodos() {
        let watermark =
            Date(timeIntervalSince1970: 200)
        let checkpoint =
            GitLabTodoNotificationCheckpoint(
                observedTodoIDs: [1],
                newestObservedCreationDate:
                    watermark
            )

        let result =
            GitLabTodoNotificationDetection
                .evaluate(
                    todos: [
                        makeTestTodo(
                            id: 2,
                            createdAt:
                                Date(
                                    timeIntervalSince1970:
                                        100
                                )
                        ),
                    ],
                    checkpoint: checkpoint
                )

        #expect(result.newTodos.isEmpty)
        #expect(
            result.checkpoint.observedTodoIDs
                == [1, 2]
        )
        #expect(
            result.checkpoint
                .newestObservedCreationDate
                == watermark
        )
    }

    @Test("Previously observed IDs remain deduplicated")
    func keepsObservedHistory() {
        let first =
            GitLabTodoNotificationDetection
                .evaluate(
                    todos: [makeTestTodo(id: 10)],
                    checkpoint: nil
                )
        let empty =
            GitLabTodoNotificationDetection
                .evaluate(
                    todos: [],
                    checkpoint: first.checkpoint
                )
        let returned =
            GitLabTodoNotificationDetection
                .evaluate(
                    todos: [makeTestTodo(id: 10)],
                    checkpoint: empty.checkpoint
                )

        #expect(returned.newTodos.isEmpty)
        #expect(
            returned.checkpoint.observedTodoIDs
                == [10]
        )
    }

    @Test("Foreground observation does not advance the watermark")
    func observationKeepsWatermark() {
        let watermark =
            Date(timeIntervalSince1970: 100)
        let checkpoint =
            GitLabTodoNotificationCheckpoint(
                observedTodoIDs: [1],
                newestObservedCreationDate:
                    watermark
            )

        let observed =
            checkpoint.observing(
                todoIDs: [2, 3]
            )

        #expect(
            observed.observedTodoIDs
                == [1, 2, 3]
        )
        #expect(
            observed.newestObservedCreationDate
                == watermark
        )
    }
}
