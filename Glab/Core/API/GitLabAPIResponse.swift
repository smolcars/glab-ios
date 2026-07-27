import Foundation

nonisolated struct GitLabAPIResponse<Value>: Sendable where Value: Sendable {
    let value: Value
    let metadata: GitLabResponseMetadata
}

nonisolated struct GitLabResponseMetadata: Equatable, Sendable {
    let requestID: String?
    let nextPageURL: URL?
    let totalCount: Int?

    init(
        requestID: String? = nil,
        nextPageURL: URL? = nil,
        totalCount: Int? = nil
    ) {
        self.requestID = requestID
        self.nextPageURL = nextPageURL
        self.totalCount = totalCount
    }

    init(response: HTTPURLResponse) {
        let requestID = response
            .value(forHTTPHeaderField: "X-Request-ID")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let totalCount = response
            .value(forHTTPHeaderField: "X-Total")
            .flatMap(Self.nonnegativeInteger)

        self.init(
            requestID: requestID?.isEmpty == false ? requestID : nil,
            nextPageURL: Self.nextPageURL(
                from: response.value(forHTTPHeaderField: "Link")
            ),
            totalCount: totalCount
        )
    }

    private static func nonnegativeInteger(
        _ value: String
    ) -> Int? {
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            let count = Int(normalized),
            count >= 0
        else {
            return nil
        }

        return count
    }

    private static func nextPageURL(from linkHeader: String?) -> URL? {
        guard let linkHeader else {
            return nil
        }

        for linkValue in splitLinkValues(linkHeader) {
            guard
                let openingBracket = linkValue.firstIndex(of: "<"),
                let closingBracket = linkValue[openingBracket...].firstIndex(of: ">")
            else {
                continue
            }

            let parameters = linkValue[linkValue.index(after: closingBracket)...]
                .split(separator: ";")
            let isNext = parameters.contains { parameter in
                let parts = parameter.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    return false
                }

                let name = parts[0]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let value = parts[1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

                return name == "rel"
                    && value.split(whereSeparator: \.isWhitespace).contains("next")
            }

            guard isNext else {
                continue
            }

            let urlString = String(
                linkValue[linkValue.index(after: openingBracket)..<closingBracket]
            )
            guard
                let url = URL(string: urlString),
                url.scheme?.lowercased() == "https",
                url.host != nil
            else {
                return nil
            }

            return url
        }

        return nil
    }

    private static func splitLinkValues(_ header: String) -> [Substring] {
        var values: [Substring] = []
        var start = header.startIndex
        var insideBrackets = false
        var insideQuotes = false

        for index in header.indices {
            switch header[index] {
            case "<" where !insideQuotes:
                insideBrackets = true
            case ">" where !insideQuotes:
                insideBrackets = false
            case "\"" where !insideBrackets:
                insideQuotes.toggle()
            case "," where !insideBrackets && !insideQuotes:
                values.append(header[start..<index])
                start = header.index(after: index)
            default:
                break
            }
        }

        values.append(header[start...])
        return values
    }
}
