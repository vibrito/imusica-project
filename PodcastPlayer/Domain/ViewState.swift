import Foundation

/// The state of a screen that loads something.
///
/// Every screen in the app funnels through this one enum, which is what lets a
/// single `StateView` render loading, empty, and error consistently everywhere.
/// Adding a screen means populating this — not inventing a fourth spinner.
enum ViewState<T: Equatable>: Equatable {
    case idle
    case loading
    case loaded(T)
    /// The load succeeded but produced nothing worth showing.
    case empty
    case failed(AppError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var value: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: AppError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

extension ViewState: Sendable where T: Sendable {}
