import SwiftUI
import UIKit

enum GlabTheme {
    static func configureUIKitAppearance() {
        let navigationAppearance =
            UINavigationBarAppearance()
        navigationAppearance
            .configureWithOpaqueBackground()
        navigationAppearance.backgroundColor =
            .glabBrandChrome
        navigationAppearance.shadowColor = .clear
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font:
                scaledFont(
                    named: "Lato-SemiBold",
                    size: 17,
                    textStyle: .headline
                ),
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font:
                scaledFont(
                    named: "Lato-Bold",
                    size: 34,
                    textStyle: .largeTitle
                ),
        ]

        let navigationBar =
            UINavigationBar.appearance()
        navigationBar.standardAppearance =
            navigationAppearance
        navigationBar.scrollEdgeAppearance =
            navigationAppearance
        navigationBar.compactAppearance =
            navigationAppearance
        navigationBar.compactScrollEdgeAppearance =
            navigationAppearance
        navigationBar.tintColor = .white
        navigationBar.barStyle = .black

        UIBarButtonItem.appearance(
            whenContainedInInstancesOf: [
                UINavigationBar.self,
            ]
        ).tintColor = .white
    }

    private static func scaledFont(
        named name: String,
        size: CGFloat,
        textStyle: UIFont.TextStyle
    ) -> UIFont {
        let baseFont =
            UIFont(name: name, size: size)
            ?? UIFont.systemFont(
                ofSize: size,
                weight: .semibold
            )
        return UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(for: baseFont)
    }
}

struct GlabList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            content()
                .listRowBackground(
                    Color.glabSurface
                )
                .listRowSeparatorTint(
                    Color.glabSeparator
                )
        }
        .glabListSurface()
    }
}

extension Color {
    static let glabAccent = Color("GlabAccent")
    static let glabBrandChrome = Color("GlabBrandChrome")
    static let glabCanvas = Color("GlabCanvas")
    static let glabSurface = Color("GlabSurface")
    static let glabRaisedSurface = Color("GlabRaisedSurface")
    static let glabSeparator = Color("GlabSeparator")
    static let glabBrandWarm = Color("GlabBrandWarm")
}

extension UIColor {
    static var glabBrandChrome: UIColor {
        UIColor(named: "GlabBrandChrome")
            ?? .systemBlue
    }

    static var glabSurface: UIColor {
        UIColor(named: "GlabSurface")
            ?? .systemBackground
    }

    static var glabRaisedSurface: UIColor {
        UIColor(named: "GlabRaisedSurface")
            ?? .secondarySystemBackground
    }
}

extension Font {
    static let glabLargeTitle =
        Font.custom(
            "Lato",
            size: 34,
            relativeTo: .largeTitle
        )

    static let glabTitle =
        Font.custom(
            "Lato",
            size: 28,
            relativeTo: .title
        )

    static let glabTitle2 =
        Font.custom(
            "Lato",
            size: 22,
            relativeTo: .title2
        )

    static let glabTitle3 =
        Font.custom(
            "Lato",
            size: 20,
            relativeTo: .title3
        )

    static let glabHeadline =
        Font.custom(
            "Lato",
            size: 17,
            relativeTo: .headline
        )
        .weight(.semibold)

    static let glabBody =
        Font.custom(
            "Lato",
            size: 17,
            relativeTo: .body
        )

    static let glabCallout =
        Font.custom(
            "Lato",
            size: 16,
            relativeTo: .callout
        )

    static let glabSubheadline =
        Font.custom(
            "Lato",
            size: 15,
            relativeTo: .subheadline
        )

    static let glabFootnote =
        Font.custom(
            "Lato",
            size: 13,
            relativeTo: .footnote
        )

    static let glabCaption =
        Font.custom(
            "Lato",
            size: 12,
            relativeTo: .caption
        )

    static let glabCaption2 =
        Font.custom(
            "Lato",
            size: 11,
            relativeTo: .caption2
        )
}

extension View {
    func glabAppTheme() -> some View {
        font(.glabBody)
            .scrollContentBackground(.hidden)
            .background(
                Color.glabCanvas
                    .ignoresSafeArea()
            )
            .glabNavigationChrome()
    }

    func glabNavigationChrome() -> some View {
        toolbarBackground(
            Color.glabBrandChrome,
            for: .navigationBar
        )
        .toolbarBackground(
            .visible,
            for: .navigationBar
        )
        .toolbarColorScheme(
            .dark,
            for: .navigationBar
        )
    }

    func glabListSurface() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.glabCanvas)
    }
}
