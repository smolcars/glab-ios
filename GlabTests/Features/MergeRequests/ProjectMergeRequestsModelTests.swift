import Foundation
import Testing
@testable import Glab

@Suite("Project merge requests model")
@MainActor
struct ProjectMergeRequestsModelTests {
    @Test(
        "Loads and preserves separate paginated state queries"
    )
    func loadsStatePages() async throws {
        let first = makeTestMergeRequest(
            id: 1,
            iid: 1,
            title: "First"
        )
        let second = makeTestMergeRequest(
            id: 2,
            iid: 2,
            title: "Second"
        )
        let merged = makeTestMergeRequest(
            id: 3,
            iid: 3,
            title: "Merged",
            state: "merged"
        )
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/merge_requests"
                    + "?state=opened&page=2"
            )
        )
        let loader =
            ProjectMergeRequestLoaderStub(
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
                    .merged: [
                        GitLabResourcePage(
                            items: [merged],
                            nextPageURL: nil,
                            totalCount: 1
                        ),
                    ],
                ]
            )
        let model =
            ProjectMergeRequestsModel(
                projectID: 42,
                loader: loader
            )

        await model.activeModel.loadIfNeeded()
        await model.activeModel
            .loadNextPageIfNeeded(
                after: first
            )
        model.selectedState = .merged
        await model.activeModel.loadIfNeeded()

        #expect(
            model.activeModel.items
                == [merged]
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
                    .merged,
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
        let opened = makeTestMergeRequest(
            id: 1,
            iid: 7,
            title: "Open request"
        )
        let merged = makeTestMergeRequest(
            id: 2,
            iid: 8,
            title: "Merged request",
            state: "merged"
        )
        let loader =
            ProjectMergeRequestLoaderStub(
                pages: [
                    .opened: [
                        GitLabResourcePage(
                            items: [opened],
                            nextPageURL: nil
                        ),
                    ],
                    .merged: [
                        GitLabResourcePage(
                            items: [merged],
                            nextPageURL: nil
                        ),
                    ],
                ]
            )
        let model =
            ProjectMergeRequestsModel(
                projectID: 42,
                loader: loader
            )

        await model.activeModel.loadIfNeeded()
        model.activeModel.searchText = "!7"
        model.selectedState = .merged
        await model.activeModel.loadIfNeeded()
        model.activeModel.searchText =
            "Merged"
        model.selectedState = .opened

        #expect(
            model.activeModel.searchText == "!7"
        )
        #expect(
            model.activeModel.displayedItems
                == [opened]
        )
    }

    @Test(
        "A merge moves a loaded request between tabs"
    )
    func reconcilesMerge() async {
        let opened = makeTestMergeRequest(
            id: 1,
            iid: 7,
            title: "Request"
        )
        let merged = makeTestMergeRequest(
            id: 1,
            iid: 7,
            title: "Request",
            state: "merged"
        )
        let loader =
            ProjectMergeRequestLoaderStub(
                pages: [
                    .opened: [
                        GitLabResourcePage(
                            items: [opened],
                            nextPageURL: nil,
                            totalCount: 1
                        ),
                    ],
                    .merged: [
                        GitLabResourcePage(
                            items: [],
                            nextPageURL: nil,
                            totalCount: 0
                        ),
                    ],
                ]
            )
        let model =
            ProjectMergeRequestsModel(
                projectID: 42,
                loader: loader
            )
        await model.activeModel.loadIfNeeded()
        model.selectedState = .merged
        await model.activeModel.loadIfNeeded()

        model.reconcileEditedMergeRequest(
            merged
        )

        #expect(
            model.model(for: .opened)
                .items.isEmpty
        )
        #expect(
            model.model(for: .merged)
                .items == [merged]
        )
        #expect(
            model.model(for: .opened)
                .reliableItemCount == 0
        )
        #expect(
            model.model(for: .merged)
                .reliableItemCount == 1
        )
    }

    @Test(
        "Closure removes the request and another project is ignored"
    )
    func reconcilesClosureForCurrentProject() async {
        let opened = makeTestMergeRequest(
            id: 1,
            iid: 7
        )
        let closed = makeTestMergeRequest(
            id: 1,
            iid: 7,
            state: "closed"
        )
        let otherProject =
            makeTestMergeRequest(
                id: 1,
                iid: 7,
                projectID: 43,
                state: "closed"
            )
        let loader =
            ProjectMergeRequestLoaderStub(
                pages: [
                    .opened: [
                        GitLabResourcePage(
                            items: [opened],
                            nextPageURL: nil,
                            totalCount: 1
                        ),
                    ],
                ]
            )
        let model =
            ProjectMergeRequestsModel(
                projectID: 42,
                loader: loader
            )
        await model.activeModel.loadIfNeeded()

        model.reconcileEditedMergeRequest(
            otherProject
        )
        #expect(
            model.activeModel.items
                == [opened]
        )

        model.reconcileEditedMergeRequest(
            closed
        )
        #expect(
            model.activeModel.items.isEmpty
        )
        #expect(
            model.activeModel
                .reliableItemCount == 0
        )
    }
}

private actor ProjectMergeRequestLoaderStub:
    GitLabMergeRequestLoading
{
    private var pages: [
        GitLabProjectMergeRequestState:
            [
                GitLabResourcePage<
                    GitLabMergeRequest
                >
            ]
    ]
    private(set) var projectIDs:
        [Int] = []
    private(set) var states:
        [GitLabProjectMergeRequestState] = []
    private(set) var pageURLs:
        [URL?] = []

    init(
        pages: [
            GitLabProjectMergeRequestState:
                [
                    GitLabResourcePage<
                        GitLabMergeRequest
                    >
                ]
        ]
    ) {
        self.pages = pages
    }

    func loadMergeRequestsPage(
        for mode: GitLabMergeRequestListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestPage
    {
        throw .api(.invalidResponse)
    }

    func loadProjectMergeRequestsPage(
        projectID: Int,
        state: GitLabProjectMergeRequestState,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabMergeRequest>
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

    func loadMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        throw .api(.invalidResponse)
    }
}
