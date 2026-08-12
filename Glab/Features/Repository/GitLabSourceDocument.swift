import Foundation

nonisolated enum GitLabSourceLanguage:
    Equatable,
    Sendable
{
    case swift
    case shell
    case json
    case yaml
    case python
    case javascript
    case typescript
    case ruby
    case rust
    case go
    case cLike
    case markup
    case markdown
    case plainText

    init(fileName: String) {
        let normalized = fileName.lowercased()
        let fileExtension = URL(
            filePath: normalized
        ).pathExtension

        self = switch fileExtension {
        case "swift":
            .swift
        case "sh", "bash", "zsh", "fish":
            .shell
        case "json", "jsonc":
            .json
        case "yaml", "yml":
            .yaml
        case "py", "pyi":
            .python
        case "js", "jsx", "mjs", "cjs":
            .javascript
        case "ts", "tsx":
            .typescript
        case "rb", "rake":
            .ruby
        case "rs":
            .rust
        case "go":
            .go
        case "c", "cc", "cpp", "cxx", "h", "hpp",
             "m", "mm", "java", "kt", "kts":
            .cLike
        case "html", "htm", "xml", "plist", "svg":
            .markup
        case "md", "markdown":
            .markdown
        default:
            switch normalized {
            case "dockerfile", "makefile", "gemfile":
                .shell
            default:
                .plainText
            }
        }
    }
}

nonisolated struct GitLabSourceDocument:
    Equatable,
    Sendable
{
    static let maximumRenderedLineLength =
        32 * 1_024
    static let maximumLineCount = 100_000
    static let renderedTabWidth = 4

    let source: String
    let lines: [String]
    let maximumRenderedColumnCount: Int
    let truncatedLineCount: Int
    let language: GitLabSourceLanguage
    let syntaxLanguage: GitLabSyntaxLanguage?

    var lineCount: Int {
        lines.count
    }

    init(
        source: String,
        fileName: String
    ) {
        let normalized = source
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
        var maximumColumnCount = 0
        var truncatedLineCount = 0
        let lines = normalized
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .map { substring in
                let line = String(substring)
                let displayLine: String
                if
                    line.count
                        > Self
                            .maximumRenderedLineLength
                {
                    truncatedLineCount += 1
                    displayLine = String(
                        line.prefix(
                            Self.maximumRenderedLineLength
                        )
                    ) + " …"
                } else {
                    displayLine = line
                }

                let rendered = Self.expandingTabs(
                    in: displayLine
                )
                maximumColumnCount = max(
                    maximumColumnCount,
                    rendered.utf16.count
                )
                return rendered
            }

        self.source = source
        self.lines = lines
        maximumRenderedColumnCount = min(
            maximumColumnCount,
            Self.maximumRenderedLineLength
                * Self.renderedTabWidth
                + 2
        )
        self.truncatedLineCount =
            truncatedLineCount
        language = GitLabSourceLanguage(
            fileName: fileName
        )
        syntaxLanguage = GitLabSyntaxLanguage(
            fileName: fileName
        )
    }

    private static func expandingTabs(
        in line: String
    ) -> String {
        guard line.contains("\t") else {
            return line
        }

        var result = ""
        result.reserveCapacity(line.count)
        var column = 0
        for character in line {
            if character == "\t" {
                let spaces = renderedTabWidth
                    - column % renderedTabWidth
                result.append(
                    String(
                        repeating: " ",
                        count: spaces
                    )
                )
                column += spaces
            } else {
                result.append(character)
                column += String(character)
                    .utf16.count
            }
        }
        return result
    }

    static func decode(
        _ data: Data,
        fileName: String
    ) throws -> Self {
        let decoded: String

        if data.starts(with: [0xFF, 0xFE]) {
            guard
                let value = String(
                    data: data,
                    encoding: .utf16LittleEndian
                )
            else {
                throw GitLabRepositorySourceLoadError
                    .unsupportedTextEncoding
            }
            decoded = value
        } else if data.starts(with: [0xFE, 0xFF]) {
            guard
                let value = String(
                    data: data,
                    encoding: .utf16BigEndian
                )
            else {
                throw GitLabRepositorySourceLoadError
                    .unsupportedTextEncoding
            }
            decoded = value
        } else {
            guard
                !isLikelyBinary(data),
                let value = String(
                    data: data,
                    encoding: .utf8
                )
            else {
                throw GitLabRepositorySourceLoadError
                    .binary
            }
            decoded = value
        }

        guard
            lineCount(in: decoded)
                <= maximumLineCount
        else {
            throw GitLabRepositorySourceLoadError
                .tooManyLines
        }

        return Self(
            source:
                decoded.first == "\u{FEFF}"
                ? String(decoded.dropFirst())
                : decoded,
            fileName: fileName
        )
    }

    private static func lineCount(
        in source: String
    ) -> Int {
        var lineCount = 1
        var previousWasCarriageReturn = false
        for scalar in source.unicodeScalars {
            if scalar.value == 0x0A {
                if !previousWasCarriageReturn {
                    lineCount += 1
                }
                previousWasCarriageReturn = false
            } else if scalar.value == 0x0D {
                lineCount += 1
                previousWasCarriageReturn = true
            } else {
                previousWasCarriageReturn = false
            }

            if lineCount > maximumLineCount {
                return lineCount
            }
        }
        return lineCount
    }

    private static func isLikelyBinary(
        _ data: Data
    ) -> Bool {
        let sample = data.prefix(8 * 1_024)
        guard !sample.isEmpty else {
            return false
        }

        var controlByteCount = 0
        for byte in sample {
            if byte == 0 {
                return true
            }
            if
                byte < 0x09
                    || (byte > 0x0D && byte < 0x20)
            {
                controlByteCount += 1
            }
        }

        return controlByteCount * 100
            > sample.count
    }
}

nonisolated enum GitLabRepositorySourceLoadError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case binary
    case unsupportedTextEncoding
    case tooLarge
    case tooManyLines
    case session(GitLabSessionClientError)
    case incomplete
    case unsafeRedirect
    case storage
    case cancelled

    var description: String {
        switch self {
        case .binary:
            "This file is not plain text and can’t be displayed here."
        case .unsupportedTextEncoding:
            "This file uses a text encoding that isn’t supported."
        case .tooLarge:
            "This file is larger than the 10 MB viewing limit."
        case .tooManyLines:
            "This file has more than 100,000 lines and can’t be displayed safely."
        case let .session(error):
            error.description
        case .incomplete:
            "GitLab stopped sending the file before it was complete."
        case .unsafeRedirect:
            "GitLab redirected the file to an unsafe destination."
        case .storage:
            "The file could not be prepared securely."
        case .cancelled:
            "The file request was cancelled."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            case let .session(error) = self,
            error.requiresReauthentication
        else {
            return nil
        }
        return error
    }

    var canRetry: Bool {
        switch self {
        case .binary,
             .unsupportedTextEncoding,
             .tooLarge,
             .tooManyLines:
            false
        default:
            true
        }
    }
}
