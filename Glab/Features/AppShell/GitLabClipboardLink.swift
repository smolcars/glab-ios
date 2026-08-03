import CoreTransferable
import Foundation
import Observation
import SwiftUI
import UIKit

nonisolated struct GitLabClipboardLinkCandidate:
    Equatable,
    Sendable,
    Transferable
{
    let url: URL

    init(url: URL) {
        self.url = url
    }

    init?(text: String) {
        let value = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !value.isEmpty,
            let components = URLComponents(
                string: value
            ),
            components.scheme != nil,
            let url = components.url
        else {
            return nil
        }

        self.init(url: url)
    }

    static var transferRepresentation:
        some TransferRepresentation
    {
        ProxyRepresentation {
            (url: URL) in
            Self(url: url)
        }
        ProxyRepresentation {
            (text: String) throws in
            guard let candidate = Self(
                text: text
            ) else {
                throw GitLabClipboardLinkImportError
                    .invalidURL
            }
            return candidate
        }
    }
}

nonisolated private enum
    GitLabClipboardLinkImportError:
    Error
{
    case invalidURL
}

nonisolated enum GitLabClipboardLinkClassification:
    Equatable,
    Sendable
{
    case accepted(URL)
    case unavailable
}

nonisolated enum GitLabClipboardLinkClassifier {
    static func classify(
        _ incomingURL: URL,
        accounts: [GitLabAccountID]
    ) -> GitLabClipboardLinkClassification {
        guard
            let targetURL =
                GitLabContentLink.targetURL(
                    from: incomingURL
                ),
            accounts.contains(where: {
                GitLabInAppLinkRouting
                    .shouldHandle(
                        targetURL,
                        for: $0.host
                    )
            })
        else {
            return .unavailable
        }

        return .accepted(targetURL)
    }
}

@MainActor
protocol GitLabClipboardURLDetecting:
    AnyObject
{
    var changeCount: Int { get }

    func containsProbableWebURL(
        for expectedChangeCount: Int
    ) async -> Bool?
}

@MainActor
final class LiveGitLabClipboardURLDetector:
    GitLabClipboardURLDetecting
{
    private var pasteboard: UIPasteboard {
        .general
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func containsProbableWebURL(
        for expectedChangeCount: Int
    ) async -> Bool? {
        guard
            changeCount
                == expectedChangeCount
        else {
            return nil
        }

        do {
            let probableURL =
                \UIPasteboard.DetectedValues
                    .probableWebURL
            let patterns = try await pasteboard
                .detectedPatterns(
                    for: [probableURL]
                )
            guard
                changeCount
                    == expectedChangeCount
            else {
                return nil
            }
            return patterns.contains(
                probableURL
            )
        } catch {
            return nil
        }
    }
}

@MainActor
@Observable
final class GitLabClipboardLinkSuggestionModel {
    private(set) var isSuggestionPresented = false
    private(set) var unavailablePasteMessage:
        String?

    private let detector:
        any GitLabClipboardURLDetecting
    private var lastObservedChangeCount:
        Int?
    private var requestGeneration = 0

    init(
        detector:
            any GitLabClipboardURLDetecting
            = LiveGitLabClipboardURLDetector()
    ) {
        self.detector = detector
    }

    func refresh(
        hasSavedAccounts: Bool
    ) async {
        requestGeneration &+= 1
        let generation = requestGeneration

        guard hasSavedAccounts else {
            isSuggestionPresented = false
            return
        }

        let changeCount = detector.changeCount
        guard
            changeCount
                != lastObservedChangeCount
        else {
            return
        }

        guard
            let containsProbableWebURL =
                await detector
                    .containsProbableWebURL(
                        for: changeCount
                    ),
            generation == requestGeneration,
            !Task.isCancelled
        else {
            return
        }

        lastObservedChangeCount =
            changeCount
        isSuggestionPresented =
            containsProbableWebURL
    }

    func dismiss() {
        requestGeneration &+= 1
        isSuggestionPresented = false
    }

    func didPasteUnavailableLink() {
        dismiss()
        unavailablePasteMessage =
            "The copied URL doesn’t belong to a saved GitLab account."
    }

    func didAcceptPastedLink() {
        dismiss()
        unavailablePasteMessage = nil
    }

    func clearUnavailablePasteMessage() {
        unavailablePasteMessage = nil
    }
}

struct GitLabClipboardLinkSuggestionView: View {
    let onPaste:
        ([GitLabClipboardLinkCandidate]) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(
                "Copied link",
                systemImage: "link"
            )
            .font(.glabSubheadline.weight(.semibold))
            .lineLimit(1)

            PasteButton(
                payloadType:
                    GitLabClipboardLinkCandidate.self,
                onPaste: onPaste
            )
            .buttonStyle(.plain)
            .font(.glabSubheadline.weight(.semibold))
            .tint(Color.glabAccent)
            .accessibilityLabel(
                "Open copied GitLab link"
            )

            Divider()
                .frame(height: 20)
                .accessibilityHidden(true)

            Button(
                role: .cancel,
                action: onDismiss
            ) {
                Image(systemName: "xmark")
                    .font(.glabCaption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(
                "Dismiss copied link"
            )
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
        .glassEffect(
            .regular,
            in: .capsule
        )
        .accessibilityIdentifier(
            "clipboardLink.suggestion"
        )
    }
}
