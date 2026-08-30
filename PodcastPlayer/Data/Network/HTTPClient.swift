import Foundation

/// HTTP cache validators, as sent and received.
///
/// Kept opaque on purpose: their only job is to be handed back to the server
/// unchanged so it can answer 304.
struct ConditionalHeaders: Equatable, Sendable {
    let etag: String?
    let lastModified: String?

    static let none = ConditionalHeaders(etag: nil, lastModified: nil)

    var isEmpty: Bool { etag == nil && lastModified == nil }
}

enum HTTPResponse: Equatable, Sendable {
    /// The server confirmed our cached copy is still current.
    case notModified
    case data(Data, ConditionalHeaders)
}

protocol HTTPClient: Sendable {
    func get(_ url: URL, conditional: ConditionalHeaders?) async throws(AppError) -> HTTPResponse
}

/// The only place `URLSession` is touched.
///
/// Every `URLError` is translated to an `AppError` here, so no transport type
/// ever reaches a ViewModel.
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get(_ url: URL, conditional: ConditionalHeaders?) async throws(AppError) -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // The app runs its own cache with its own policy; letting URLCache also
        // answer would make revalidation untestable and the TTL a fiction.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        if let conditional {
            if let etag = conditional.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = conditional.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.mapped(error)
        } catch {
            throw .network(statusCode: nil)
        }

        guard let http = response as? HTTPURLResponse else {
            throw .network(statusCode: nil)
        }

        switch http.statusCode {
        case 304:
            return .notModified
        case 200...299:
            return .data(data, ConditionalHeaders(
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified")
            ))
        case 404, 410:
            throw .notFound
        default:
            throw .network(statusCode: http.statusCode)
        }
    }

    /// Connectivity problems become `.offline` because that is what the user
    /// can act on; everything else is the server's fault, not theirs.
    private static func mapped(_ error: URLError) -> AppError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed:
            .offline
        default:
            .network(statusCode: nil)
        }
    }
}
