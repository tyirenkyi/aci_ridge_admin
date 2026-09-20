//
//  APIError.swift
//  ACI Admin
//
//  Every failure the console can show. The server always answers with
//  `{ "error": "<a finished human sentence>" }` and no error codes, so for the
//  statuses an admin can act on we show the server's own words.
//

import Foundation

nonisolated enum APIError: Error, Sendable, Equatable {
    /// The device has no usable connection. Nothing reached the server.
    case offline
    /// 401 — the session is dead even after a refresh. Re-authenticate.
    case unauthorized(String)
    /// 403 — signed in, but not on the admin allowlist.
    case forbidden(String)
    /// 404 — no such record.
    case notFound(String)
    /// 409 — a lifecycle conflict: already sent, sent notices can't change.
    case conflict(String)
    /// 400/422 — validation. The message is prose meant for display, never parsing.
    case validation(String)
    /// 5xx.
    case server(String)
    /// The request never completed for a reason that isn't plain offline.
    case transport(String)
    /// The response didn't match what we expect. Always our bug, not the admin's.
    case decoding(String)

    /// Copy to put straight into a toast or an error state.
    var message: String {
        switch self {
        case .offline:
            return "You're offline — the change wasn't saved."
        case .unauthorized:
            return "Your session expired. Sign in again."
        case .forbidden(let m), .notFound(let m), .conflict(let m), .validation(let m):
            // The server's sentence is already the right thing to say.
            return m
        case .server, .decoding, .transport:
            return "Something went wrong at our end. Try again in a moment."
        }
    }

    /// True when the session itself is the problem and the admin must sign in again.
    var isAuthFailure: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// True when retrying the same request could plausibly work.
    var isRetryable: Bool {
        switch self {
        case .offline, .transport, .server: return true
        default: return false
        }
    }

    /// Builds the right case from a status code and the decoded `{ error }` sentence.
    static func from(status: Int, message: String) -> APIError {
        switch status {
        case 401: return .unauthorized(message)
        case 403: return .forbidden(message)
        case 404: return .notFound(message)
        case 409: return .conflict(message)
        case 400, 422: return .validation(message)
        case 500...599: return .server(message)
        default: return .validation(message)
        }
    }
}
