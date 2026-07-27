import Foundation
import Testing
@testable import Glab

@Suite("App bootstrap")
struct AppBootstrapTests {
    @Test("Root view can be constructed")
    @MainActor
    func rootViewCanBeConstructed() {
        _ = AppRootView()
    }

    @Test("Bundles the app privacy manifest")
    func bundlesPrivacyManifest() throws {
        let url = try #require(
            Bundle.main.url(
                forResource: "PrivacyInfo",
                withExtension: "xcprivacy"
            )
        )
        let data = try Data(contentsOf: url)
        let propertyList =
            try PropertyListSerialization.propertyList(
                from: data,
                format: nil
            )
        let manifest = try #require(
            propertyList as? [String: Any]
        )
        let accessedAPITypes = try #require(
            manifest["NSPrivacyAccessedAPITypes"]
                as? [[String: Any]]
        )
        let userDefaultsDeclaration = accessedAPITypes
            .first {
                $0["NSPrivacyAccessedAPIType"] as? String
                    == "NSPrivacyAccessedAPICategoryUserDefaults"
            }
        let reasons = try #require(
            userDefaultsDeclaration?[
                "NSPrivacyAccessedAPITypeReasons"
            ] as? [String]
        )

        #expect(reasons == ["CA92.1"])
        #expect(
            (manifest["NSPrivacyCollectedDataTypes"]
                as? [Any])?.isEmpty == true
        )
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect(
            (manifest["NSPrivacyTrackingDomains"]
                as? [String])?.isEmpty == true
        )
    }

    @Test("Bundles required release metadata")
    func bundlesRequiredReleaseMetadata() throws {
        let info = try #require(Bundle.main.infoDictionary)

        #expect(
            info["ITSAppUsesNonExemptEncryption"] as? Bool
                == false
        )

        let icons = try #require(
            info["CFBundleIcons"] as? [String: Any]
        )
        let primaryIcon = try #require(
            icons["CFBundlePrimaryIcon"] as? [String: Any]
        )
        let iconFiles = try #require(
            primaryIcon["CFBundleIconFiles"] as? [String]
        )
        #expect(!iconFiles.isEmpty)
    }
}
