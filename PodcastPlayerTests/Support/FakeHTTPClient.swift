import Foundation
@testable import PodcastPlayer

/// Hand-written fake. Records what was asked for and returns canned answers —
/// clearer than a mocking DSL, and adds no dependency.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<HTTPResponse, AppError>]
    private var _requests: [(url: URL, conditional: ConditionalHeaders?)] = []

    init(result: Result<HTTPResponse, AppError>) {
        self.results = [result]
    }

    init(results: [Result<HTTPResponse, AppError>]) {
        self.results = results
    }

    convenience init(data: Data, headers: ConditionalHeaders = .none) {
        self.init(result: .success(.data(data, headers)))
    }

    convenience init(error: AppError) {
        self.init(result: .failure(error))
    }

    var requestCount: Int { lock.withLock { _requests.count } }
    var lastConditional: ConditionalHeaders? { lock.withLock { _requests.last?.conditional } }
    var requestedURLs: [URL] { lock.withLock { _requests.map(\.url) } }

    func get(_ url: URL, conditional: ConditionalHeaders?) async throws(AppError) -> HTTPResponse {
        let result: Result<HTTPResponse, AppError> = lock.withLock {
            _requests.append((url, conditional))
            // The last result repeats, so a test can set one answer and call
            // any number of times.
            return results.count > 1 ? results.removeFirst() : results[0]
        }

        switch result {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}
