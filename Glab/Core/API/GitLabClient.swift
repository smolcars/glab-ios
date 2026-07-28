import Foundation

nonisolated struct GitLabEmptyResponse: Decodable, Equatable, Sendable {
    init() {}
}

nonisolated struct GitLabClient<Transport>: Sendable where Transport: GitLabHTTPTransport {
    private let requestBuilder: GitLabRequestBuilder
    private let transport: Transport
    private let retryPolicy: GitLabReadRetryPolicy
    private let sleep:
        @Sendable (Duration) async throws -> Void

    init(
        requestBuilder: GitLabRequestBuilder,
        transport: Transport,
        retryPolicy: GitLabReadRetryPolicy = .standard,
        sleep:
            @escaping @Sendable (Duration) async throws -> Void = { duration in
                try await Task.sleep(for: duration)
            }
    ) {
        self.requestBuilder = requestBuilder
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.sleep = sleep
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
        try await sendPage(.initial(endpoint))
    }

    @concurrent
    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabAPIError) -> GitLabAPIResponse<Response> {
        let response = try await sendRawPage(page)
        return try GitLabAPIResponseDecoder.decode(
            response
        )
    }

    @concurrent
    func sendRawPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabAPIError) -> GitLabRawAPIResponse {
        guard !Task.isCancelled else {
            throw .cancelled
        }

        let request = try request(for: page)

        return try await send(
            request,
            allowsAutomaticRetry:
                request.httpMethod == GitLabHTTPMethod.get.rawValue
        )
    }

    func request<Response>(
        for page: GitLabAPIPageRequest<Response>
    ) throws(GitLabAPIError) -> URLRequest {
        do {
            return try requestBuilder.build(page)
        } catch {
            throw .invalidRequest(error)
        }
    }

    private func send(
        _ request: URLRequest,
        allowsAutomaticRetry: Bool
    ) async throws(GitLabAPIError) -> GitLabRawAPIResponse {
        var retryNumber = 1

        while true {
            do {
                return try await sendAttempt(request)
            } catch {
                guard !Task.isCancelled else {
                    throw .cancelled
                }
                guard
                    allowsAutomaticRetry,
                    let delay = retryPolicy.delay(
                        after: error,
                        retryNumber: retryNumber
                    )
                else {
                    throw error
                }

                do {
                    try await sleep(delay)
                } catch {
                    throw .cancelled
                }

                guard !Task.isCancelled else {
                    throw .cancelled
                }
                retryNumber += 1
            }
        }
    }

    private func sendAttempt(
        _ request: URLRequest
    ) async throws(GitLabAPIError) -> GitLabRawAPIResponse {
        guard !Task.isCancelled else {
            throw .cancelled
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

        return GitLabRawAPIResponse(
            body: data,
            metadata:
                GitLabResponseMetadata(
                    response: httpResponse
                ),
            entityTag:
                Self.normalizedHeader(
                    "ETag",
                    from: httpResponse
                ),
            lastModified:
                Self.normalizedHeader(
                    "Last-Modified",
                    from: httpResponse
                )
        )
    }

    private static func normalizedHeader(
        _ name: String,
        from response: HTTPURLResponse
    ) -> String? {
        let value = response
            .value(forHTTPHeaderField: name)?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        return value?.isEmpty == false ? value : nil
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

nonisolated enum GitLabAPIResponseDecoder {
    static func decode<Response>(
        _ response: GitLabRawAPIResponse
    ) throws(GitLabAPIError) -> GitLabAPIResponse<Response>
    where Response: Decodable & Sendable {
        let value: Response

        if
            response.body.isEmpty,
            let emptyResponse =
                GitLabEmptyResponse() as? Response
        {
            value = emptyResponse
        } else {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                value = try decoder.decode(
                    Response.self,
                    from: response.body
                )
            } catch {
                throw .decoding
            }
        }

        return GitLabAPIResponse(
            value: value,
            metadata: response.metadata
        )
    }
}
