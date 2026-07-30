import SwiftUI

struct GitLabSearchField: View {
    @Binding private var text: String

    @FocusState private var isFocused: Bool

    private let prompt: String
    private let accessibilityIdentifier: String
    private let focusesOnAppear: Bool

    init(
        text: Binding<String>,
        prompt: String,
        accessibilityIdentifier: String,
        focusesOnAppear: Bool = false
    ) {
        _text = text
        self.prompt = prompt
        self.accessibilityIdentifier =
            accessibilityIdentifier
        self.focusesOnAppear = focusesOnAppear
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .accessibilityIdentifier(
                    accessibilityIdentifier
                )

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .glassEffect(
            .regular.interactive(),
            in: .capsule
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color(uiColor: .systemGroupedBackground)
        )
        .task {
            if focusesOnAppear {
                isFocused = true
            }
        }
    }
}
