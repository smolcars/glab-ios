import SwiftUI

struct GitLabKeyboardDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                "Dismiss keyboard",
                systemImage:
                    "keyboard.chevron.compact.down"
            )
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Dismiss keyboard")
    }
}
