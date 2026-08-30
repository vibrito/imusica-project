import Foundation

/// Intercepts requests inside URLSession so HTTPClient can be tested against
/// real URLSession machinery without touching the network.
///
/// Registered on an ephemeral configuration rather than globally, so tests stay
/// isolated from each other.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data()
        var headers: [String: String] = [:]
        var error: Error?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _stub = Stub()
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    static var stub: Stub {
        get { lock.withLock { _stub } }
        set { lock.withLock { _stub = newValue } }
    }

    static var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    static var lastRequest: URLRequest? {
        lock.withLock { _requests.last }
    }

    static func reset() {
        lock.withLock {
            _stub = Stub()
            _requests = []
        }
    }

    static func respond(status: Int, body: Data = Data(), headers: [String: String] = [:]) {
        stub = Stub(statusCode: status, body: body, headers: headers, error: nil)
    }

    static func fail(with error: Error) {
        stub = Stub(error: error)
    }

    /// A session that routes every request through this stub.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self._requests.append(request) }
        let stub = Self.stub

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.test")!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty {
            client?.urlProtocol(self, didLoad: stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
