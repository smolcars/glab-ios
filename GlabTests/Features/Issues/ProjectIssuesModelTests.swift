import Foundation
import Testing
@testable import Glab

@Suite("Project issues model")
@MainActor
struct ProjectIssuesModelTests {
    @Test("Loads and preserves separate paginated state queries")
    func loadsStatePages() async throws {
        let first = makeTestIssue(
            id: 1,
            iid: 1,
            title: "First"
        )
        let second = makeTestIssue(
            id: 2,
            iid: 2,
            title: "Second"
        )
        let closed = makeTestIssue(
            id: 3,
            iid: 3,
            title: "Closed",
            state: "closed"
        )
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects/42/issues?state=opened&page=2"
            )
        )
        let loader = ProjectIssueLoaderStub(
            pages: [
                .opened: [
                    GitLabResourcePage(
                        items: [first],
                        nextPageURL:
                            nextPageURL,
                        totalCount: 2
                    ),
                    GitLabResourcePage(
                        items: [second],
                        nextPageURL: nil,
                        totalCount: 2
                    ),
                ],
                .closed: [
                    GitLabResourcePage(
                        items: [closed],
                        nextPageURL: nil,
                        totalCount: 1
                    ),
                ],
            ]
        )
        let model = ProjectIssuesModel(
            projectID: 42,
            loader: loader
        )

        await model.activeModel.loadIfNeeded()
        await model.activeModel
            .loadNextPageIfNeeded(
                after: first
            )
        model.selectedState = .closed
        await model.activeModel.loadIfNeeded()

        #expect(
            model.activeModel.items == [closed]
        )
        #expect(
            model.activeModel
                .reliableItemCount == 1
        )

        model.selectedState = .opened
        #expect(
            model.activeModel.items
                == [first, second]
        )
        #expect(
            model.activeModel
                .reliableItemCount == 2
        )
        #expect(
            await loader.projectIDs
                == [42, 42, 42]
        )
        #expect(
            await loader.states
                == [
                    .opened,
                    .opened,
                    .closed,
                ]
        )
        #expect(
            await loader.pageURLs
                == [
                    nil,
                    nextPageURL,
                    nil,
                ]
        )
    }

    @Test("Each state retains its own loaded search")
    func retainsStateSearch() async {
        let opened = makeTestIssue(
            id: 1,
            iid: 7,
            title: "Open issue"
        )
        let closed = makeTestIssue(
            id: 2,
            iid: 8,
            title: "Closed issue",
            state: "closed"
        )
        let loader = ProjectIssueLoaderStub(
            pages: [
                .opened: [
                    GitLabResourcePage(
                        items: [opened],
                        nextPageURL: nil
                    ),
                ],
                .closed: [
                    GitLabResourcePage(
                        items: [closed],
                        nextPageURL: nil
                    ),
                ],
            ]
        )
        let model = ProjectIssuesModel(
            projectID: 42,
            loader: loader
        )

        await model.activeModel.loadIfNeeded()
        model.activeModel.searchText = "#7"
        model.selectedState = .closed
        await model.activeModel.loadIfNeeded()
        model.activeModel.searchText =
            "Closed"
        model.selectedState = .opened

        #expect(
            model.activeModel.searchText == "#7"
        )
        #expect(
            model.activeModel.displayedItems
                == [opened]
        )
    }

    @Test("Creation always reconciles into Open")
    func reconcilesCreationIntoOpen() async {
        let opened = makeTestIssue(
            id: 1,
            iid: 7,
            title: "Existing"
        )
        let closed = makeTestIssue(
            id: 2,
            iid: 8,
            title: "Closed",
            state: "closed"
        )
        let created = makeTestIssue(
            id: 3,
            iid: 9,
            title: "Created"
        )
        let loader = ProjectIssueLoaderStub(
            pages: [
                .opened: [
                    GitLabResourcePage(
                        items: [opened],
                        nextPageURL: nil,
                        totalCount: 1
                    ),
                ],
                .closed: [
                    GitLabResourcePage(
                        items: [closed],
                        nextPageURL: nil,
                        totalCount: 1
                    ),
                ],
            ]
        )
        let model = ProjectIssuesModel(
            projectID: 42,
            loader: loader
        )
        await model.activeModel.loadIfNeeded()
        model.selectedState = .closed
        await model.activeModel.loadIfNeeded()

        model.reconcileCreatedIssue(created)

        #expect(
            model.activeModel.items == [closed]
        )
        #expect(
            model.model(for: .opened).items
                == [created, opened]
        )
        #expect(
            model.model(for: .opened)
                .reliableItemCount == 2
        )
    }

    @Test("A state edit moves a loaded issue between tabs")
    func reconcilesStateEdit() async {
        let opened = makeTestIssue(
            id: 1,
            iid: 7,
            title: "Issue"
        )
        let closed = makeTestIssue(
            id: 1,
            iid: 7,
            title: "Issue",
            state: "closed"
        )
        let loader = ProjectIssueLoaderStub(
            pages: [
                .opened: [
                    GitLabResourcePage(
                        items: [opened],
                        nextPageURL: nil,
                        totalCount: 1
                    ),
                ],
                .closed: [
                    GitLabResourcePage(
                        items: [],
                        nextPageURL: nil,
                        totalCount: 0
                    ),
                ],
            ]
        )
        let model = ProjectIssuesModel(
            projectID: 42,
            loader: loader
        )
        await model.activeModel.loadIfNeeded()
        model.selectedState = .closed
        await model.activeModel.loadIfNeeded()

        model.reconcileEditedIssue(closed)

        #expect(
            model.model(for: .opened)
                .items.isEmpty
        )
        #expect(
            model.model(for: .closed)
                .items == [closed]
        )
        #expect(
            model.model(for: .opened)
                .reliableItemCount == 0
        )
        #expect(
            model.model(for: .closed)
                .reliableItemCount == 1
        )
    }
}

private actor ProjectIssueLoaderStub:
    GitLabIssueLoading
{
    private var pages: [
        GitLabProjectIssueState:
            [GitLabResourcePage<GitLabIssue>]
    ]
    private(set) var projectIDs:
        [Int] = []
    private(set) var states:
        [GitLabProjectIssueState] = []
    private(set) var pageURLs:
        [URL?] = []

    init(
        pages: [
            GitLabProjectIssueState:
                [GitLabResourcePage<GitLabIssue>]
        ]
    ) {
        self.pages = pages
    }

    func loadAssignedIssuesPage(
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabIssuePage
    {
        throw .api(.invalidResponse)
    }

    func loadProjectIssuesPage(
        projectID: Int,
        state: GitLabProjectIssueState,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabIssue>
    {
        projectIDs.append(projectID)
        states.append(state)
        pageURLs.append(nextPageURL)
        guard
            var statePages = pages[state],
            !statePages.isEmpty
        else {
            throw .api(.invalidResponse)
        }
        let page = statePages.removeFirst()
        pages[state] = statePages
        return page
    }

    func loadIssue(
        at route: GitLabIssueRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabIssue
    {
        throw .api(.invalidResponse)
    }
}
