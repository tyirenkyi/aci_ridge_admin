//
//  Supa.swift
//  ACI Admin
//
//  The Supabase client. Same project as the member app — the server checks the
//  access token this issues against its own admin allowlist.
//
//  The anon key is designed to ship inside apps; it grants nothing on its own.
//

import Auth
import Foundation
import Supabase

nonisolated enum Supa {
    static let projectURL = URL(string: "https://qjpjgmunybctwfjwefol.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFqcGpnbXVueWJjdHdmandlZm9sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcyNjM0OTgsImV4cCI6MjA3MjgzOTQ5OH0.Zmq0wtET9JO4Q8hM72razduXBKZLBjXsLBOfFNRfVC8"

    static let client = SupabaseClient(supabaseURL: projectURL, supabaseKey: anonKey)

    /// Reads the current access token, refreshing it first if it has expired. Cheap
    /// in the common case — the SDK caches and persists the session itself.
    static let accessToken: APIClient.TokenProvider = {
        try await client.auth.session.accessToken
    }

    /// One refresh attempt after a 401. A second 401 is taken at face value.
    static let refreshToken: APIClient.TokenRefresher = {
        (try? await client.auth.refreshSession()) != nil
    }
}
