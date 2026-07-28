import QuartzCore
import SwiftUI
import Testing
import UIKit
@testable import Glab

@Suite(
    "GitLab Markdown view performance",
    .serialized
)
@MainActor
struct GitLabMarkdownViewPerformanceTests {
    @Test("Keeps scroll geometry stable across mixed Markdown blocks")
    func stableScrollGeometry() async throws {
        let request = try makeRequest(
            source: GitLabMarkdownFixtures.medium
        )
        let document =
            try await GitLabMarkdownParser.parse(
                request
            )
        let host = try MarkdownScrollHost(
            document: document
        )
        defer {
            host.tearDown()
        }

        let scrollView =
            try await host.prepare()
        let initialHeight =
            scrollView.contentSize.height
        let initialMaximumOffset = max(
            0,
            initialHeight
                - scrollView.bounds.height
        )
        #expect(initialMaximumOffset > 0)

        var measuredHeights = [
            initialHeight
        ]
        for step in 1...12 {
            let targetOffset =
                initialMaximumOffset
                * CGFloat(step)
                / 12
            scrollView.setContentOffset(
                CGPoint(
                    x: 0,
                    y: targetOffset
                ),
                animated: false
            )
            scrollView.layoutIfNeeded()
            host.controller.view
                .layoutIfNeeded()
            CATransaction.flush()
            await Task.yield()
            measuredHeights.append(
                scrollView.contentSize.height
            )
        }

        let heightSpread =
            try #require(
                measuredHeights.max()
            )
            - (try #require(
                measuredHeights.min()
            ))
        #expect(
            heightSpread <= 1,
            "Content height changed by \(heightSpread) points while scrolling."
        )
        #expect(
            abs(
                scrollView.contentOffset.y
                    - initialMaximumOffset
            ) <= 1,
            "The scroll offset did not remain at the requested end position."
        )
    }

    private func makeRequest(
        source: String
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 1
            ),
            resource: .issue(
                projectID: 10,
                issueIID: 42
            ),
            source: source,
            webURL: URL(
                string:
                    "https://gitlab.example.com/group/project"
                    + "/-/issues/42"
            )
        )
    }
}

@MainActor
private final class MarkdownScrollHost {
    let window: UIWindow
    let controller:
        UIHostingController<
            MarkdownScrollTestView
        >

    init(
        document: GitLabMarkdownDocument
    ) throws {
        controller = UIHostingController(
            rootView:
                MarkdownScrollTestView(
                    document: document
                )
        )
        guard
            let windowScene =
                UIApplication.shared
                    .connectedScenes
                    .compactMap({
                        $0 as? UIWindowScene
                    })
                    .first
        else {
            throw MarkdownViewPerformanceError
                .missingWindowScene
        }
        window = UIWindow(
            windowScene: windowScene
        )
        window.frame = CGRect(
            x: 0,
            y: 0,
            width: 402,
            height: 874
        )
        window.rootViewController =
            controller
        controller.loadViewIfNeeded()
        controller.view.frame =
            window.bounds
        window.makeKeyAndVisible()
    }

    func prepare() async throws -> UIScrollView {
        await Task.yield()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        CATransaction.flush()
        await Task.yield()
        controller.view.layoutIfNeeded()
        CATransaction.flush()

        guard
            let scrollView =
                Self.verticalScrollView(
                    in: controller.view
                )
        else {
            throw MarkdownViewPerformanceError
                .missingScrollView
        }
        return scrollView
    }

    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private static func verticalScrollView(
        in view: UIView
    ) -> UIScrollView? {
        if
            let scrollView =
                view as? UIScrollView,
            scrollView.contentSize.height
                > scrollView.bounds.height
        {
            return scrollView
        }
        for subview in view.subviews {
            if
                let scrollView =
                    verticalScrollView(
                        in: subview
                    )
            {
                return scrollView
            }
        }
        return nil
    }
}

private struct MarkdownScrollTestView:
    View
{
    let document: GitLabMarkdownDocument

    var body: some View {
        ScrollView {
            GitLabMarkdownDocumentView(
                document: document,
                taskInteraction: nil
            )
            .padding(20)
        }
    }
}

private enum MarkdownViewPerformanceError:
    Error
{
    case missingWindowScene
    case missingScrollView
}
