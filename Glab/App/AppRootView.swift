import SwiftUI

struct AppRootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Glab",
                systemImage: "chevron.left.forwardslash.chevron.right",
                description: Text("Your GitLab work, wherever you are.")
            )
            .navigationTitle("Glab")
        }
    }
}

#Preview {
    AppRootView()
}
