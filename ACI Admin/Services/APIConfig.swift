//
//  APIConfig.swift
//  ACI Admin
//

import Foundation

nonisolated enum APIConfig {
    /// The console talks to the same Railway deployment the website does.
    static let productionBaseURL = URL(string: "https://aciridgeserver-production.up.railway.app")!
    static let localBaseURL = URL(string: "http://localhost:8080")!

    static var baseURL: URL {
        // Point a debug build at a local server by passing -local at launch.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-local") { return localBaseURL }
        #endif
        return productionBaseURL
    }

    /// Set by the click-through UI test so the app runs against stub data and skips
    /// real Sign in with Apple. See StubAPI.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    /// Shown above a notice as the default sender. Replaces AdminUser.current.church,
    /// since /api/me only returns an email and a role.
    static let churchName = "Ridge Community Cathedral"
}

nonisolated extension URLSession {
    static let apiDefault: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()
}
