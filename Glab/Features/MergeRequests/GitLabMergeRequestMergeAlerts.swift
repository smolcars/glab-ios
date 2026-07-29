import SwiftUI

extension View {
    func gitLabMergeRequestMergeAlerts(
        model:
            GitLabMergeRequestMergeModel
    ) -> some View {
        modifier(
            GitLabMergeRequestMergeAlertModifier(
                model: model
            )
        )
    }
}

private struct
    GitLabMergeRequestMergeAlertModifier:
    ViewModifier
{
    let model:
        GitLabMergeRequestMergeModel

    func body(
        content: Content
    ) -> some View {
        content
            .alert(
                confirmationTitle,
                isPresented:
                    confirmationIsPresented
            ) {
                if let confirmation =
                    model.confirmation
                {
                    Button(
                        confirmation
                            .action.title
                    ) {
                        Task {
                            await model
                                .confirm()
                        }
                    }
                    .accessibilityIdentifier(
                        "mergeRequests.merge.confirm"
                    )
                }
                Button(
                    "Cancel",
                    role: .cancel
                ) {
                    model
                        .dismissConfirmation()
                }
            } message: {
                Text(confirmationMessage)
            }
            .alert(
                "Couldn’t merge request",
                isPresented:
                    failureIsPresented
            ) {
                Button("OK", role: .cancel) {
                    model.dismissFailure()
                }
            } message: {
                Text(
                    model.failure?
                        .message
                    ?? ""
                )
            }
    }

    private var confirmationIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                model.confirmation != nil
            },
            set: {
                if !$0 {
                    model
                        .dismissConfirmation()
                }
            }
        )
    }

    private var confirmationTitle:
        String
    {
        model.confirmation?
            .action == .autoMerge
            ? "Set auto-merge?"
            : "Merge request?"
    }

    private var confirmationMessage:
        String
    {
        guard
            let confirmation =
                model.confirmation
        else {
            return ""
        }
        let route =
            "\(confirmation.sourceBranch) → \(confirmation.targetBranch)"
        switch confirmation.action {
        case .mergeNow:
            return "Merge “\(confirmation.title)” from \(route)?"
        case .autoMerge:
            return "GitLab will merge “\(confirmation.title)” from \(route) after all checks pass and may use a merge train."
        }
    }

    private var failureIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                model.failure != nil
            },
            set: {
                if !$0 {
                    model.dismissFailure()
                }
            }
        )
    }
}
