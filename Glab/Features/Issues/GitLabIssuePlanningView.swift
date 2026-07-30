import SwiftUI

struct GitLabIssueMilestonePicker: View {
    let model: GitLabIssuePlanningModel

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        List {
            Section {
                choice(
                    title: "No milestone",
                    subtitle: nil,
                    isSelected:
                        model
                        .selectedMilestoneID
                        == nil
                ) {
                    await model
                        .selectMilestone(nil)
                }

                ForEach(model.milestones) {
                    milestone in
                    choice(
                        title: milestone.title,
                        subtitle:
                            GitLabIssueFieldDatePresentation
                            .range(
                                start:
                                    milestone
                                    .startDate,
                                due:
                                    milestone
                                    .dueDate
                            ),
                        isSelected:
                            model
                            .selectedMilestoneID
                            == milestone.id
                    ) {
                        await model
                            .selectMilestone(
                                milestone
                            )
                    }
                }
            }
        }
        .navigationTitle("Milestone")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if
                model.milestones.isEmpty,
                !model.isBusy
            {
                ContentUnavailableView(
                    "No active milestones",
                    systemImage:
                        "signpost.right"
                )
            }
        }
    }

    private func choice(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action:
            @escaping @MainActor () async
                -> Void
    ) -> some View {
        Button {
            Task {
                await action()
                if
                    model.failure == nil,
                    !model
                        .requiresDeliveryCheck
                {
                    dismiss()
                }
            }
        } label: {
            GitLabIssuePlanningChoiceRow(
                title: title,
                subtitle: subtitle,
                isSelected: isSelected,
                systemImage:
                    "signpost.right"
            )
        }
        .disabled(model.isBusy)
    }
}

struct GitLabIssueIterationPicker: View {
    let model: GitLabIssuePlanningModel

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        List {
            Section {
                choice(
                    title: "No iteration",
                    subtitle: nil,
                    isSelected:
                        model
                        .selectedIterationID
                        == nil
                ) {
                    await model
                        .selectIteration(nil)
                }

                ForEach(model.iterations) {
                    iteration in
                    choice(
                        title:
                            iteration
                            .displayTitle,
                        subtitle:
                            GitLabIssueFieldDatePresentation
                            .range(
                                start:
                                    iteration
                                    .startDate,
                                due:
                                    iteration
                                    .dueDate
                            ),
                        isSelected:
                            model
                            .selectedIterationID
                            == iteration.id
                    ) {
                        await model
                            .selectIteration(
                                iteration
                            )
                    }
                }
            }
        }
        .navigationTitle("Iteration")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if
                model.iterations.isEmpty,
                !model.isBusy
            {
                ContentUnavailableView(
                    "No open iterations",
                    systemImage: "repeat"
                )
            }
        }
    }

    private func choice(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action:
            @escaping @MainActor () async
                -> Void
    ) -> some View {
        Button {
            Task {
                await action()
                if
                    model.failure == nil,
                    !model
                        .requiresDeliveryCheck
                {
                    dismiss()
                }
            }
        } label: {
            GitLabIssuePlanningChoiceRow(
                title: title,
                subtitle: subtitle,
                isSelected: isSelected,
                systemImage: "repeat"
            )
        }
        .disabled(model.isBusy)
    }
}

private struct GitLabIssuePlanningChoiceRow:
    View
{
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }
            }
            Spacer(minLength: 12)
            if isSelected {
                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(.orange)
            }
        }
        .contentShape(.rect)
    }
}
