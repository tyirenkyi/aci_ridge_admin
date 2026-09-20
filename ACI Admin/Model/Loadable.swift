//
//  Loadable.swift
//  ACI Admin
//
//  Per-area load state. Each tab loads independently, so one area failing must not
//  blank another — which is why this is per-area rather than a single `isLoading`.
//

import Foundation

nonisolated enum Loadable<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    /// A failure that keeps whatever we last loaded, so a failed *refresh* shows the
    /// old data under a banner instead of throwing the admin back to an error screen.
    case failed(APIError, stale: Value?)

    var value: Value? {
        switch self {
        case .loaded(let v): return v
        case .failed(_, let stale): return stale
        case .idle, .loading: return nil
        }
    }

    var error: APIError? {
        if case .failed(let e, _) = self { return e }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// True only for the very first load, when there is nothing to show yet.
    var isInitialLoad: Bool {
        switch self {
        case .idle, .loading: return value == nil
        default: return false
        }
    }

    var hasLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// Moves to `.loading` while holding on to any value we already have, so a
    /// refresh doesn't flash an empty screen.
    mutating func beginRefresh() {
        if let existing = value {
            self = .loaded(existing)
        } else {
            self = .loading
        }
    }

    mutating func fail(_ error: APIError) {
        self = .failed(error, stale: value)
    }
}

extension Loadable: Equatable where Value: Equatable {}
