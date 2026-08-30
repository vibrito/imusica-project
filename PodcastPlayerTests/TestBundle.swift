import Foundation

/// Anchor for `Bundle(for:)` so tests can reach fixture files in the test
/// bundle. Swift Testing has no `XCTestCase` to anchor against, so the test
/// target needs a class of its own.
final class BundleMarker {}

extension Bundle {
    static var tests: Bundle { Bundle(for: BundleMarker.self) }
}
