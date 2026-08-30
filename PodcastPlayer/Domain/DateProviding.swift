import Foundation

/// Supplies "now".
///
/// Cache expiry and history ordering both depend on the current time, which
/// makes them untestable if they call `Date()` directly. Injecting the clock
/// keeps those tests deterministic.
///
/// Named `DateProviding` rather than `Clock` to avoid colliding with the
/// standard library's `Clock` protocol.
protocol DateProviding: Sendable {
    var now: Date { get }
}

struct SystemDateProvider: DateProviding {
    var now: Date { Date() }
}

/// Test double: time never moves.
struct FixedDateProvider: DateProviding {
    let now: Date
    init(now: Date) { self.now = now }
}

/// Test double: every read advances by a fixed step, so successive writes get
/// strictly increasing timestamps without any sleeping.
final class AdvancingDateProvider: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let step: TimeInterval

    init(start: Date, step: TimeInterval = 1) {
        self.current = start
        self.step = step
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        let value = current
        current = current.addingTimeInterval(step)
        return value
    }
}
