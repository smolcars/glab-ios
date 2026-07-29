import SwiftUI

struct GlabAppFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("v\(appVersion)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("Made with ❤️ by Nitesh")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link(destination: repositoryURL) {
                Image("GitHubMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .foregroundStyle(.primary)
            .accessibilityLabel("View Glab on GitHub")
            .accessibilityIdentifier("app.githubLink")
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/smolcars/glab-ios")!
    }
}
