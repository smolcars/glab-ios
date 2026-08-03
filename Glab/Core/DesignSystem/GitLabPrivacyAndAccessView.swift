import SwiftUI

struct GitLabPrivacyAndAccessView: View {
    let presentation:
        GitLabPrivacyAndAccessPresentation

    var body: some View {
        GlabList {
            Section("GitLab permission") {
                LabeledContent(
                    "API scope",
                    value: presentation.scopeName
                )

                Text(presentation.scopeSummary)
            }

            Section("Authentication") {
                Label {
                    Text(
                        presentation
                            .authenticationSummary
                    )
                } icon: {
                    Image(
                        systemName:
                            "person.badge.shield.checkmark"
                    )
                    .foregroundStyle(Color.glabAccent)
                }

                Label {
                    Text(presentation.storageSummary)
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color.glabAccent)
                }
            }

            Section("Data use") {
                Label {
                    Text(presentation.dataUseSummary)
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(Color.glabAccent)
                }

                if let privacyPolicyURL =
                    presentation.privacyPolicyURL
                {
                    Link(
                        destination: privacyPolicyURL
                    ) {
                        Label(
                            "Privacy Policy",
                            systemImage:
                                "arrow.up.right.square"
                        )
                    }
                    .accessibilityIdentifier(
                        "privacyAndAccess"
                            + ".privacyPolicyLink"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy & API access")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(
            "privacyAndAccess.view"
        )
    }
}

struct GitLabPrivacyAndAccessSheet: View {
    let presentation:
        GitLabPrivacyAndAccessPresentation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GitLabPrivacyAndAccessView(
                presentation: presentation
            )
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier(
                        "privacyAndAccess.doneButton"
                    )
                }
            }
        }
    }
}
