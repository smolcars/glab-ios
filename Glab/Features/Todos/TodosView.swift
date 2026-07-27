import SwiftUI

struct TodosView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                GitLabEmptyStateView(
                    title: "Todos will appear here",
                    message:
                        "GitLab Todos that need your attention will be "
                        + "collected in this inbox.",
                    systemImage: "checklist"
                )
                .frame(minHeight: 430)
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Todos")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
