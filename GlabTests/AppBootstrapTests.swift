import Testing
@testable import Glab

@Suite("App bootstrap")
struct AppBootstrapTests {
    @Test("Root view can be constructed")
    @MainActor
    func rootViewCanBeConstructed() {
        _ = AppRootView()
    }
}
