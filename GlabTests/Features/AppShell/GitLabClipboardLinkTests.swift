import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab clipboard-link suggestion")
struct GitLabClipboardLinkSuggestionModelTests {
    @Test("Offers each probable URL clipboard change once")
    func offersNewProbableURLChanges() async {
        let detector = RecordingClipboardURLDetector(
            changeCount: 10,
            result: true
        )
        let model = GitLabClipboardLinkSuggestionModel(
            detector: detector
        )

        await model.refresh(hasSavedAccounts: true)

        #expect(model.isSuggestionPresented)
        #expect(detector.detectionCount == 1)

        model.dismiss()
        await model.refresh(hasSavedAccounts: true)

        #expect(!model.isSuggestionPresented)
        #expect(detector.detectionCount == 1)

        detector.changeCount = 11
        await model.refresh(hasSavedAccounts: true)

        #expect(model.isSuggestionPresented)
        #expect(detector.detectionCount == 2)
    }

    @Test("Keeps non-URLs, failures, and accountless sessions hidden")
    func hidesUnavailableSuggestions() async {
        let detector = RecordingClipboardURLDetector(
            changeCount: 20,
            result: false
        )
        let model = GitLabClipboardLinkSuggestionModel(
            detector: detector
        )

        await model.refresh(hasSavedAccounts: false)
        #expect(detector.detectionCount == 0)
        #expect(!model.isSuggestionPresented)

        await model.refresh(hasSavedAccounts: true)
        #expect(detector.detectionCount == 1)
        #expect(!model.isSuggestionPresented)

        detector.changeCount = 21
        detector.result = nil
        await model.refresh(hasSavedAccounts: true)
        #expect(detector.detectionCount == 2)
        #expect(!model.isSuggestionPresented)

        detector.result = true
        await model.refresh(hasSavedAccounts: true)
        #expect(detector.detectionCount == 3)
        #expect(model.isSuggestionPresented)
    }

    @Test("Ignores a detection result after the suggestion is dismissed")
    func ignoresStaleDetection() async {
        let detector = ControllableClipboardURLDetector(
            changeCount: 30
        )
        let model = GitLabClipboardLinkSuggestionModel(
            detector: detector
        )

        let refresh = Task {
            await model.refresh(
                hasSavedAccounts: true
            )
        }
        await detector.waitUntilDetectionStarts()

        model.dismiss()
        detector.complete(with: true)
        await refresh.value

        #expect(!model.isSuggestionPresented)
    }

    @Test("Ignores a detection result after foreground work is cancelled")
    func ignoresCancelledDetection() async {
        let detector = ControllableClipboardURLDetector(
            changeCount: 31
        )
        let model = GitLabClipboardLinkSuggestionModel(
            detector: detector
        )

        let refresh = Task {
            await model.refresh(
                hasSavedAccounts: true
            )
        }
        await detector.waitUntilDetectionStarts()

        refresh.cancel()
        detector.complete(with: true)
        await refresh.value

        #expect(!model.isSuggestionPresented)
    }
}

@Suite("GitLab pasted-link classification")
struct GitLabClipboardLinkClassifierTests {
    @Test("Accepts direct and wrapped links for saved GitLab sites")
    func acceptsSavedSites() throws {
        let gitLabCom = try account(
            host: "gitlab.com",
            userID: 1
        )
        let selfManaged = try account(
            host: "gitlab.example.com/gitlab",
            userID: 2
        )
        let directURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/gitlab/"
                    + "group/project/-/issues/7"
            )
        )
        let wrappedURL = try #require(
            URL(
                string:
                    "glab://open?url=https%3A%2F%2F"
                    + "gitlab.com%2Fgroup%2Fproject%2F-%2F"
                    + "merge_requests%2F9"
            )
        )
        let wrappedTarget = try #require(
            GitLabContentLink.targetURL(
                from: wrappedURL
            )
        )

        #expect(
            GitLabClipboardLinkClassifier.classify(
                directURL,
                accounts: [
                    gitLabCom,
                    selfManaged,
                ]
            ) == .accepted(directURL)
        )
        #expect(
            GitLabClipboardLinkClassifier.classify(
                wrappedURL,
                accounts: [
                    gitLabCom,
                    selfManaged,
                ]
            ) == .accepted(wrappedTarget)
        )
    }

    @Test("Keeps safe unsupported paths available for browser fallback")
    func acceptsUnsupportedSavedSitePath() throws {
        let saved = try account(
            host: "gitlab.example.com",
            userID: 1
        )
        let wikiURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project/-/wikis/home"
            )
        )

        #expect(
            GitLabClipboardLinkClassifier.classify(
                wikiURL,
                accounts: [saved]
            ) == .accepted(wikiURL)
        )
    }

    @Test("Rejects malformed and unsaved-site links")
    func rejectsInvalidAndUnsavedSites() throws {
        let saved = try account(
            host: "gitlab.example.com/gitlab",
            userID: 1
        )
        let invalidURLs = try [
            "http://gitlab.example.com/gitlab/group/project",
            "https://user:password@gitlab.example.com/gitlab/group/project",
            "https://gitlab.example.com.evil.test/gitlab/group/project",
            "https://gitlab.example.com/group/project",
            "https://example.com/group/project",
        ].map {
            try #require(URL(string: $0))
        }

        for url in invalidURLs {
            #expect(
                GitLabClipboardLinkClassifier.classify(
                    url,
                    accounts: [saved]
                ) == .unavailable
            )
        }
    }

    @Test("Normalizes a single plain-text URL candidate")
    func parsesPlainTextCandidate() throws {
        let candidate = try #require(
            GitLabClipboardLinkCandidate(
                text:
                    "  https://gitlab.com/group/project  \n"
            )
        )

        #expect(
            candidate.url.absoluteString
                == "https://gitlab.com/group/project"
        )
        #expect(
            GitLabClipboardLinkCandidate(
                text: "not a URL"
            ) == nil
        )
    }

    private func account(
        host: String,
        userID: Int
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host: try GitLabHost(host),
            userID: userID
        )
    }
}

@MainActor
private final class RecordingClipboardURLDetector:
    GitLabClipboardURLDetecting
{
    var changeCount: Int
    var result: Bool?
    private(set) var detectionCount = 0

    init(
        changeCount: Int,
        result: Bool?
    ) {
        self.changeCount = changeCount
        self.result = result
    }

    func containsProbableWebURL(
        for expectedChangeCount: Int
    ) async -> Bool? {
        detectionCount += 1
        return result
    }
}

@MainActor
private final class ControllableClipboardURLDetector:
    GitLabClipboardURLDetecting
{
    let changeCount: Int
    private var resultContinuation:
        CheckedContinuation<Bool?, Never>?
    private var startContinuation:
        CheckedContinuation<Void, Never>?
    private var didStart = false

    init(changeCount: Int) {
        self.changeCount = changeCount
    }

    func containsProbableWebURL(
        for expectedChangeCount: Int
    ) async -> Bool? {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
        return await withCheckedContinuation {
            resultContinuation = $0
        }
    }

    func waitUntilDetectionStarts() async {
        guard !didStart else {
            return
        }
        await withCheckedContinuation {
            startContinuation = $0
        }
    }

    func complete(with result: Bool?) {
        resultContinuation?.resume(
            returning: result
        )
        resultContinuation = nil
    }
}
