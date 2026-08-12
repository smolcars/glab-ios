import CryptoKit
import Foundation
import Highlighter
import SwiftUI
import UIKit

nonisolated struct GitLabSyntaxLanguage:
    Equatable,
    Hashable,
    Sendable
{
    let identifier: String

    init?(markdownFence: String?) {
        guard
            let markdownFence,
            let token = markdownFence
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .split(whereSeparator: { $0.isWhitespace })
                .first
        else {
            return nil
        }

        let normalized = String(token)
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: "{.}"
                )
            )
            .lowercased()
        self.init(normalizedIdentifier: normalized)
    }

    init?(fileName: String) {
        let normalizedName = URL(
            filePath: fileName.lowercased()
        ).lastPathComponent
        let explicitIdentifier: String? = switch normalizedName {
        case "dockerfile", "containerfile":
            "dockerfile"
        case "makefile":
            "makefile"
        case "gemfile", "podfile", "rakefile":
            "ruby"
        default:
            nil
        }

        let fileExtension = URL(
            filePath: normalizedName
        ).pathExtension
        let identifier = explicitIdentifier
            ?? Self.identifier(
                forFileExtension: fileExtension
            )
            ?? (fileExtension.isEmpty
                ? nil
                : fileExtension)
        guard let identifier else {
            return nil
        }
        self.init(normalizedIdentifier: identifier)
    }

    private init?(normalizedIdentifier: String) {
        let identifier = Self.aliases[
            normalizedIdentifier
        ] ?? normalizedIdentifier
        guard
            !Self.plainTextIdentifiers.contains(
                identifier
            ),
            !identifier.isEmpty,
            identifier.unicodeScalars.allSatisfy({
                Self.allowedIdentifierCharacters
                    .contains($0)
            })
        else {
            return nil
        }
        self.identifier = identifier
    }

    private static func identifier(
        forFileExtension fileExtension: String
    ) -> String? {
        switch fileExtension {
        case "swift":
            "swift"
        case "sh", "bash", "zsh", "fish":
            "bash"
        case "json", "jsonc":
            "json"
        case "yaml", "yml":
            "yaml"
        case "py", "pyi":
            "python"
        case "js", "jsx", "mjs", "cjs":
            "javascript"
        case "ts", "tsx":
            "typescript"
        case "rb", "rake":
            "ruby"
        case "rs":
            "rust"
        case "go":
            "go"
        case "c":
            "c"
        case "cc", "cpp", "cxx", "h", "hh", "hpp":
            "cpp"
        case "m", "mm":
            "objectivec"
        case "java":
            "java"
        case "kt", "kts":
            "kotlin"
        case "html", "htm", "xml", "plist", "svg":
            "xml"
        case "md", "markdown":
            "markdown"
        case "css", "scss", "sass", "less":
            fileExtension
        case "sql":
            "sql"
        case "php":
            "php"
        case "dart":
            "dart"
        case "cs":
            "csharp"
        case "ex", "exs":
            "elixir"
        case "erl", "hrl":
            "erlang"
        case "lua":
            "lua"
        case "r":
            "r"
        case "vue":
            "vue"
        case "toml":
            "ini"
        case "ini":
            "ini"
        default:
            nil
        }
    }

    private static let aliases = [
        "c++": "cpp",
        "c#": "csharp",
        "html": "xml",
        "js": "javascript",
        "jsx": "javascript",
        "objc": "objectivec",
        "objective-c": "objectivec",
        "py": "python",
        "rb": "ruby",
        "sass": "scss",
        "shell": "bash",
        "sh": "bash",
        "ts": "typescript",
        "tsx": "typescript",
        "vue": "xml",
        "yml": "yaml",
    ]

    private static let plainTextIdentifiers: Set<String> = [
        "no-highlight",
        "none",
        "plain",
        "plaintext",
        "text",
        "txt",
    ]

    private static let allowedIdentifierCharacters =
        CharacterSet(
            charactersIn:
                "abcdefghijklmnopqrstuvwxyz0123456789_+-"
        )
}

nonisolated enum GitLabSyntaxTheme:
    Equatable,
    Hashable,
    Sendable
{
    case light
    case dark

    var highlighterName: String {
        switch self {
        case .light:
            "github"
        case .dark:
            "github-dark"
        }
    }
}

nonisolated struct GitLabSyntaxHighlightRequest:
    Sendable
{
    fileprivate enum Source: Sendable {
        case text(String)
        case lines([String])
    }

    fileprivate let source: Source
    let language: GitLabSyntaxLanguage
    let theme: GitLabSyntaxTheme

    init(
        source: String,
        language: GitLabSyntaxLanguage,
        theme: GitLabSyntaxTheme
    ) {
        self.source = .text(source)
        self.language = language
        self.theme = theme
    }

    init(
        lines: [String],
        language: GitLabSyntaxLanguage,
        theme: GitLabSyntaxTheme
    ) {
        source = .lines(lines)
        self.language = language
        self.theme = theme
    }
}

nonisolated struct GitLabHighlightedText:
    @unchecked Sendable
{
    // The immutable defensive copy is the only attributed string that
    // crosses the highlighter actor boundary.
    let attributedString: NSAttributedString

    init(_ attributedString: NSAttributedString) {
        self.attributedString = NSAttributedString(
            attributedString: attributedString
        )
    }
}

nonisolated protocol GitLabSyntaxHighlighting:
    Sendable
{
    func highlight(
        _ request: GitLabSyntaxHighlightRequest
    ) async -> GitLabHighlightedText?
}

actor GitLabSyntaxHighlighter:
    GitLabSyntaxHighlighting
{
    static let maximumInputByteCount =
        1 * 1_024 * 1_024

    private struct CacheKey:
        Equatable,
        Hashable
    {
        let sourceDigest: Data
        let language: GitLabSyntaxLanguage
        let theme: GitLabSyntaxTheme
    }

    private struct CacheEntry {
        let text: GitLabHighlightedText
        let sourceCost: Int
        var lastAccess: UInt64
    }

    private let maximumDocumentCount: Int
    private let maximumSourceCost: Int
    private var cache: [CacheKey: CacheEntry] = [:]
    private var highlighter: Highlighter?
    private var currentTheme: GitLabSyntaxTheme?
    private var accessCounter: UInt64 = 0

    init(
        maximumDocumentCount: Int = 32,
        maximumSourceCost: Int = 2 * 1_024 * 1_024
    ) {
        precondition(maximumDocumentCount > 0)
        precondition(maximumSourceCost > 0)
        self.maximumDocumentCount =
            maximumDocumentCount
        self.maximumSourceCost = maximumSourceCost
    }

    func highlight(
        _ request: GitLabSyntaxHighlightRequest
    ) async -> GitLabHighlightedText? {
        guard !Task.isCancelled else {
            return nil
        }
        guard
            let (source, sourceCost) = source(
                from: request.source
            )
        else {
            return nil
        }
        guard
            sourceCost > 0,
            sourceCost <= Self.maximumInputByteCount
        else {
            return nil
        }

        let key = CacheKey(
            sourceDigest:
                Data(
                    SHA256.hash(
                        data: Data(source.utf8)
                    )
                ),
            language: request.language,
            theme: request.theme
        )
        if var cached = cache[key] {
            cached.lastAccess = nextAccess()
            cache[key] = cached
            return cached.text
        }

        guard
            let highlighter = configuredHighlighter(
                for: request.theme
            ),
            let highlighted = highlighter.highlight(
                source,
                as: request.language.identifier
            ),
            highlighted.string == source,
            !Task.isCancelled
        else {
            return nil
        }

        let mutable = NSMutableAttributedString(
            attributedString: highlighted
        )
        let fullRange = NSRange(
            location: 0,
            length: mutable.length
        )
        mutable.removeAttribute(.font, range: fullRange)
        mutable.removeAttribute(
            .paragraphStyle,
            range: fullRange
        )
        mutable.removeAttribute(
            .backgroundColor,
            range: fullRange
        )
        let text = GitLabHighlightedText(mutable)
        cache[key] = CacheEntry(
            text: text,
            sourceCost: sourceCost,
            lastAccess: nextAccess()
        )
        evictIfNeeded()
        return text
    }

    var cacheEntryCount: Int {
        cache.count
    }

    var cacheSourceCost: Int {
        cache.values.reduce(0) {
            $0 + $1.sourceCost
        }
    }

    private func configuredHighlighter(
        for theme: GitLabSyntaxTheme
    ) -> Highlighter? {
        let instance: Highlighter
        if let highlighter {
            instance = highlighter
        } else {
            guard let created = Highlighter() else {
                return nil
            }
            created.ignoreIllegals = true
            highlighter = created
            instance = created
        }

        guard currentTheme != theme else {
            return instance
        }
        guard
            instance.setTheme(theme.highlighterName)
        else {
            return nil
        }
        currentTheme = theme
        return instance
    }

    private func source(
        from requestSource:
            GitLabSyntaxHighlightRequest.Source
    ) -> (String, Int)? {
        switch requestSource {
        case let .text(source):
            let sourceCost = source.utf8.count
            guard
                sourceCost
                    <= Self.maximumInputByteCount
            else {
                return nil
            }
            return (source, sourceCost)
        case let .lines(lines):
            var sourceCost = max(0, lines.count - 1)
            for line in lines {
                sourceCost += line.utf8.count
                guard
                    sourceCost
                        <= Self.maximumInputByteCount
                else {
                    return nil
                }
            }
            return (
                lines.joined(separator: "\n"),
                sourceCost
            )
        }
    }

    private func evictIfNeeded() {
        while
            cache.count > maximumDocumentCount
                || cacheSourceCost > maximumSourceCost
        {
            guard
                let leastRecentlyUsed = cache.min(
                    by: {
                        $0.value.lastAccess
                            < $1.value.lastAccess
                    }
                )?.key
            else {
                return
            }
            cache[leastRecentlyUsed] = nil
        }
    }

    private func nextAccess() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }
}

private struct GitLabSyntaxHighlighterEnvironmentKey:
    EnvironmentKey
{
    static let defaultValue:
        any GitLabSyntaxHighlighting =
            GitLabSyntaxHighlighter()
}

extension EnvironmentValues {
    var gitLabSyntaxHighlighter:
        any GitLabSyntaxHighlighting
    {
        get {
            self[
                GitLabSyntaxHighlighterEnvironmentKey.self
            ]
        }
        set {
            self[
                GitLabSyntaxHighlighterEnvironmentKey.self
            ] = newValue
        }
    }
}
