import Testing
import Foundation
@testable import PodcastPlayer

@Suite("HTTPClient", .serialized)
struct HTTPClientTests {
    let url = URL(string: "https://example.test/feed.xml")!

    private func makeClient() -> URLSessionHTTPClient {
        StubURLProtocol.reset()
        return URLSessionHTTPClient(session: StubURLProtocol.makeSession())
    }

    @Test("Sends conditional headers when validators are known")
    func sendsConditionalHeaders() async throws {
        let client = makeClient()
        StubURLProtocol.respond(status: 304)

        _ = try await client.get(url, conditional: ConditionalHeaders(
            etag: "\"abc\"",
            lastModified: "Mon, 01 Jan 2024 00:00:00 GMT"
        ))

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 01 Jan 2024 00:00:00 GMT")
    }

    @Test("Sends no conditional headers on a cold fetch")
    func sendsNoConditionalHeadersWithoutValidators() async throws {
        let client = makeClient()
        StubURLProtocol.respond(status: 200, body: Data("x".utf8))

        _ = try await client.get(url, conditional: nil)

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
    }

    @Test("Maps 304 to notModified")
    func mapsNotModified() async throws {
        let client = makeClient()
        StubURLProtocol.respond(status: 304)

        let response = try await client.get(url, conditional: nil)
        #expect(response == .notModified)
    }

    @Test("Returns the body and its validators on 200")
    func returnsDataAndValidators() async throws {
        let client = makeClient()
        StubURLProtocol.respond(
            status: 200,
            body: Data("hello".utf8),
            headers: ["ETag": "\"v2\"", "Last-Modified": "Tue, 02 Jan 2024 00:00:00 GMT"]
        )

        guard case let .data(body, headers) = try await client.get(url, conditional: nil) else {
            Issue.record("Expected a data response")
            return
        }
        #expect(body == Data("hello".utf8))
        #expect(headers.etag == "\"v2\"")
        #expect(headers.lastModified == "Tue, 02 Jan 2024 00:00:00 GMT")
    }

    @Test("A 200 with no validators still succeeds")
    func succeedsWithoutValidators() async throws {
        let client = makeClient()
        StubURLProtocol.respond(status: 200, body: Data("hello".utf8))

        guard case let .data(_, headers) = try await client.get(url, conditional: nil) else {
            Issue.record("Expected a data response")
            return
        }
        #expect(headers.etag == nil)
        #expect(headers.lastModified == nil)
    }

    @Test("Maps 404 to notFound")
    func mapsNotFound() async {
        let client = makeClient()
        StubURLProtocol.respond(status: 404)

        await #expect(throws: AppError.notFound) {
            try await client.get(url, conditional: nil)
        }
    }

    @Test("Maps other failures to network, keeping the status code", arguments: [500, 503, 403])
    func mapsServerErrors(status: Int) async {
        let client = makeClient()
        StubURLProtocol.respond(status: status)

        await #expect(throws: AppError.network(statusCode: status)) {
            try await client.get(url, conditional: nil)
        }
    }

    @Test("Maps connectivity failures to offline", arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotFindHost,
    ])
    func mapsConnectivityFailuresToOffline(code: URLError.Code) async {
        let client = makeClient()
        StubURLProtocol.fail(with: URLError(code))

        await #expect(throws: AppError.offline) {
            try await client.get(url, conditional: nil)
        }
    }

    @Test("Maps an unexpected transport failure to network")
    func mapsUnknownTransportFailure() async {
        let client = makeClient()
        StubURLProtocol.fail(with: URLError(.badServerResponse))

        await #expect(throws: AppError.network(statusCode: nil)) {
            try await client.get(url, conditional: nil)
        }
    }

    @Test("No URLError ever escapes the client")
    func noURLErrorEscapes() async {
        let client = makeClient()
        StubURLProtocol.fail(with: URLError(.unknown))

        do {
            _ = try await client.get(url, conditional: nil)
            Issue.record("Expected a thrown error")
        } catch {
            #expect(error is AppError)
        }
    }
}
