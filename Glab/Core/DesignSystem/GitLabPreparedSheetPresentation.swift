import Foundation

struct GitLabPreparedSheetPresentationState<
    Destination
>
where
    Destination: Identifiable,
    Destination.ID: Equatable
{
    // Keep content alive for one SwiftUI render pass before
    // presenting. Immediate presentation can produce an empty
    // sheet host on a cold launch.
    private(set) var destination: Destination?
    private(set) var isPresented = false

    var preparedID: Destination.ID? {
        destination?.id
    }

    mutating func prepare(
        _ destination: Destination
    ) {
        self.destination = destination
        isPresented = false
    }

    mutating func presentPrepared(
        id: Destination.ID?
    ) {
        guard
            let id,
            destination?.id == id
        else {
            return
        }
        isPresented = true
    }

    mutating func dismiss() {
        isPresented = false
    }

    mutating func didDismiss() {
        isPresented = false
        destination = nil
    }
}
