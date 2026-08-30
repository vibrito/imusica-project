import Testing
import Foundation
@testable import PodcastPlayer

@Suite("Scaffold")
struct SmokeTests {
    @Test("The unit test target is wired to the app target")
    func testTargetIsWired() {
        #expect(Bundle.tests.bundleIdentifier != nil)
    }
}
