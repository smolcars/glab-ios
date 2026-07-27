import Foundation

nonisolated struct GitLabEmptyResponse: Decodable, Equatable, Sendable {
    init() {}
}

nonisolated struct GitLabClient<Transport>: Sendable where Transport: GitLabHTTPTransport {
    private let requestBuilder: GitLabRequestBuilder
    private let transport: Transport

    init(requestBuilder: GitLabRequestBuilder, transport: Transport) {
        self.requestBuilder = requestBuilder
        self.transport = transport
    }

    @concurrent
    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabAPIError) -> Response {
        try await sendResponse(endpoint).value
    }

    @concurrent
    func sendResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabAPIError) -> GitLabAPIResponse<Response> {
        let request: URLRequest

        do {
            request = try requestBuilder.build(endpoint)
        } catch {
            throw .invalidRequest(error)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError {
            if error.code == .cancelled {
                throw .cancelled
            }
            throw .connectivity(error.code)
        } catch {
            throw .transport
        }

        guard !Task.isCancelled else {
            throw .cancelled
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw .invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.error(for: httpResponse)
        }

        let value: Response

        if data.isEmpty, let emptyResponse = GitLabEmptyResponse() as? Response {
            value = emptyResponse
        } else {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                value = try decoder.decode(Response.self, from: data)
            } catch {
                throw .decoding
            }
        }

        return GitLabAPIResponse(
            value: value,
            metadata: GitLabResponseMetadata(response: httpResponse)
        )
    }

    private static func error(for response: HTTPURLResponse) -> GitLabAPIError {
        switch response.statusCode {
        case 400, 422:
            .validation(statusCode: response.statusCode)
        case 401:
            .unauthenticated
        case 403:
            .forbidden
        case 404:
            .notFound
        case 429:
            .rateLimited(retryAfterSeconds: retryAfterSeconds(from: response))
        case 500...599:
            .server(statusCode: response.statusCode)
        default:
            .http(statusCode: response.statusCode)
        }
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        guard
            let value = response
                .value(forHTTPHeaderField: "Retry-After")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let seconds = Int(value),
            seconds >= 0
        else {
            return nil
        }

        return seconds
    }
}
