import Testing
@testable import Glab

@Suite("GitLab app tabs")
struct GitLabAppTabTests {
    @Test("The MVP exposes exactly Home and Todos")
    func exposesOnlyMVPTabs() {
        #expect(GitLabAppTab.allCases == [.home, .todos])
        #expect(GitLabAppTab.defaultTab == .home)
    }

    @Test("Each tab has stable native presentation metadata")
    func presentsTabs() {
        #expect(GitLabAppTab.home.title == "Home")
        #expect(GitLabAppTab.home.systemImage == "house.fill")
        #expect(GitLabAppTab.todos.title == "Todos")
        #expect(GitLabAppTab.todos.systemImage == "checklist")
    }
}
