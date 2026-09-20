//
//  APIClient.swift
//  ACI Admin
//
//  The one place that talks to the server.
//
//  It is a stateless `nonisolated` class rather than an actor or a main-actor type:
//  the target compiles with MainActor as the default isolation, so an unannotated
//  class would pin JSON decoding to the main thread, while an actor would serialise
//  a type that holds nothing mutable. Every property is a `let`, so Sendable is free.
//

import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

nonisolated struct Endpoint: Sendable {
    var method: HTTPMethod = .get
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable & Sendable)?

    init(_ method: HTTPMethod = .get,
         _ path: String,
         query: [URLQueryItem] = [],
         body: (any Encodable & Sendable)? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}

nonisolated final class APIClient: Sendable {
    /// Supplies a bearer token. Kept as a closure so the client knows nothing about
    /// Supabase, and so tests can hand it a constant.
    typealias TokenProvider = @Sendable () async throws -> String
    /// Asks the auth layer to refresh after a 401. Returns true if it might be worth
    /// retrying.
    typealias TokenRefresher = @Sendable () async -> Bool

    private let baseURL: URL
    private let session: URLSession
    private let token: TokenProvider
    private let refresh: TokenRefresher

    init(baseURL: URL = APIConfig.baseURL,
         session: URLSession = .apiDefault,
         token: @escaping TokenProvider,
         refresh: @escaping TokenRefresher = { false }) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
        self.refresh = refresh
    }

    // MARK: Sending

    /// For endpoints that answer with a body.
    func send<Response: Decodable>(_ endpoint: Endpoint) async throws(APIError) -> Response {
        let data = try await perform(endpoint, allowRefresh: true)
        guard !data.isEmpty else {
            throw APIError.decoding("Expected a response body but the server sent none.")
        }
        do {
            return try JSONDecoder.api.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// For endpoints that answer 204 with no body — every DELETE here.
    func send(_ endpoint: Endpoint) async throws(APIError) {
        _ = try await perform(endpoint, allowRefresh: true)
    }

    // MARK: Internals

    private func perform(_ endpoint: Endpoint, allowRefresh: Bool) async throws(APIError) -> Data {
        let request = try await buildRequest(endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                throw APIError.offline
            default:
                throw APIError.transport(error.localizedDescription)
            }
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("The server sent a response we couldn't read.")
        }

        if (200..<300).contains(http.statusCode) {
            return data
        }

        // One shot at a refresh, then believe the 401.
        if http.statusCode == 401, allowRefresh, await refresh() {
            return try await perform(endpoint, allowRefresh: false)
        }

        throw APIError.from(status: http.statusCode, message: Self.errorMessage(from: data, status: http.statusCode))
    }

    private func buildRequest(_ endpoint: Endpoint) async throws(APIError) -> URLRequest {
        // Paths are written with a leading slash for readability; appending one
        // verbatim would double it up.
        let relative = endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path
        var components = URLComponents(
            url: baseURL.appendingPathComponent(relative),
            resolvingAgainstBaseURL: false
        )
        if !endpoint.query.isEmpty { components?.queryItems = endpoint.query }
        guard let url = components?.url else {
            throw APIError.transport("Couldn't build a URL for \(endpoint.path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue

        do {
            request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.unauthorized("Your session expired. Sign in again.")
        }

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder.api.encode(body)
            } catch {
                throw APIError.decoding("Couldn't encode the request: \(error)")
            }
        }
        return request
    }

    /// The server always answers `{ "error": "<sentence>" }`. Fall back to something
    /// sayable if it ever doesn't.
    private static func errorMessage(from data: Data, status: Int) -> String {
        if let envelope = try? JSONDecoder.api.decode(ErrorEnvelope.self, from: data),
           !envelope.error.isEmpty {
            return envelope.error
        }
        return "The server returned an error (\(status))."
    }
}
