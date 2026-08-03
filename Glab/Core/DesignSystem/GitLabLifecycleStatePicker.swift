import SwiftUI

struct GitLabLifecycleStatePicker<State: Hashable>: View {
    let states: [State]
    @Binding var selection: State
    let title: (State) -> String
    let gitLabIcon: (State) -> GitLabIcon
    let accessibilityValue: (State) -> String
    let accessibilityIdentifier: String

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                picker
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(
                        "\(accessibilityIdentifier)Picker"
                    )
            } else {
                HStack(spacing: 4) {
                    ForEach(states, id: \.self) {
                        stateButton($0)
                    }
                }
                .padding(3)
                .background(
                    Color(
                        uiColor:
                            .tertiarySystemFill
                    ),
                    in: .capsule
                )
            }
        }
    }

    private func stateButton(
        _ state: State
    ) -> some View {
        let isSelected = selection == state

        return Button {
            selection = state
        } label: {
            Label {
                Text(title(state))
            } icon: {
                GitLabIconView(
                    gitLabIcon(state)
                )
            }
            .font(
                .glabSubheadline.weight(
                    .semibold
                )
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 30
            )
            .foregroundStyle(
                isSelected
                    ? Color.glabCanvas
                    : .secondary
            )
            .background(
                isSelected
                    ? Color.glabAccent
                    : .clear,
                in: .capsule
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            isSelected
                ? .isSelected
                : []
        )
        .accessibilityIdentifier(
            "\(accessibilityIdentifier).\(accessibilityValue(state))"
        )
    }

    private var picker: some View {
        Picker(
            "State",
            selection: $selection
        ) {
            ForEach(states, id: \.self) { state in
                Label {
                    Text(title(state))
                } icon: {
                    GitLabIconView(
                        gitLabIcon(state)
                    )
                }
                .labelStyle(
                    .titleAndIcon
                )
                .tag(state)
            }
        }
    }
}
