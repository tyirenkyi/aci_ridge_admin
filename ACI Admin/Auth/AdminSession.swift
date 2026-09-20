//
//  AdminSession.swift
//  ACI Admin
//
//  Who is signed in, and how far through the front door they are.
//
//  The server has no login endpoint: it verifies a Supabase access token and checks
//  the address against its own admin allowlist. So signing in is two steps — Apple
//  via Supabase, then GET /api/me to find out whether this address is allowed in.
//

import Auth
import AuthenticationServices
import Foundation
import Observation
import Supabase

struct AdminProfile: Hashable, Sendable, Codable {
    enum Role: String, Codable, Sendable, Hashable { case owner, editor }

    let email: String
    let role: Role

    var roleLabel: String { role == .owner ? "Owner" : "Editor" }

    /// /api/me returns an address and nothing else, so the avatar comes from that.
    var initials: String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? email
        let words = localPart.split(whereSeparator: { ".-_+".contains($0) })
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// Only the owner may manage console access; everything else is open to both.
    var canManageAdmins: Bool { role == .owner }

    static let sample = AdminProfile(email: "franklin@acirid.ge", role: .owner)
}

@Observable
final class AdminSession {
    enum SignOutReason: Equatable, Sendable {
        case expired
        case notAllowlisted(String)
        case userInitiated

        var message: String? {
            switch self {
            case .expired: return "Your session expired. Sign in again."
            // The server's own sentence — already the right words.
            case .notAllowlisted(let message): return message
            case .userInitiated: return nil
            }
        }
    }

    enum Phase: Equatable {
        /// Restoring a stored session. Shown as the brand background rather than a
        /// flash of the sign-in screen on every cold start.
        case launching
        case signedOut(SignOutReason?)
        case verifying
        case locked(AdminProfile)
        case ready(AdminProfile)
    }

    private(set) var phase: Phase = .launching
    private(set) var signingIn = false
    let lock = AppLock()

    private var api: (any AdminAPI)?
    private var watch: Task<Void, Never>?
    private var backgroundedAt: Date?

    private static let cacheKey = "admin.profile"

    func configure(api: any AdminAPI) { self.api = api }

    var profile: AdminProfile? {
        switch phase {
        case .locked(let profile), .ready(let profile): return profile
        case .launching, .signedOut, .verifying: return nil
        }
    }

    // MARK: Lifecycle

    func start() async {
        // The click-through test can't drive the real Apple sheet, so it walks the
        // same three screens against a known PIN instead of a real identity.
        guard !APIConfig.isUITesting else {
            lock.bind(to: AdminProfile.sample.email)
            phase = .signedOut(nil)
            return
        }

        watch?.cancel()
        watch = Task { [weak self] in
            for await change in Supa.client.auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .initialSession, .signedIn, .tokenRefreshed:
                    if change.session == nil {
                        if case .signedOut = self.phase {} else { self.phase = .signedOut(nil) }
                    } else if self.profile == nil {
                        await self.verify()
                    }
                case .signedOut:
                    self.phase = .signedOut(.userInitiated)
                default:
                    break
                }
            }
        }
    }

    /// Asks the server whether this signed-in address is actually an admin.
    func verify() async {
        guard let api else { return }
        phase = .verifying
        do {
            let me = try await api.me()
            let profile = AdminProfile(
                email: me.email,
                role: AdminProfile.Role(rawValue: me.role) ?? .editor
            )
            cache(profile)
            lock.bind(to: profile.email)
            phase = .locked(profile)
        } catch let error as APIError {
            switch error {
            case .forbidden(let message):
                await signOut(reason: .notAllowlisted(message))
            case .unauthorized:
                // The client already spent its one refresh attempt.
                await signOut(reason: .expired)
            default:
                // A flaky connection must never lock the church office out of the
                // console minutes before a service. Carry on with what we know.
                if let cached = cachedProfile {
                    lock.bind(to: cached.email)
                    phase = .locked(cached)
                } else {
                    phase = .signedOut(nil)
                }
            }
        } catch {
            phase = .signedOut(nil)
        }
    }

    // MARK: Signing in

    func completeAppleSignIn(_ result: Result<ASAuthorization, any Error>) async {
        signingIn = true
        defer { signingIn = false }
        do {
            guard let credential = try result.get().credential as? ASAuthorizationAppleIDCredential,
                  let idToken = credential.identityToken
                      .flatMap({ String(data: $0, encoding: .utf8) })
            else {
                phase = .signedOut(nil)
                return
            }
            try await Supa.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken)
            )
            await verify()
        } catch is ASAuthorizationError {
            // Cancelled at the system sheet — not a failure worth shouting about.
            phase = .signedOut(nil)
        } catch {
            phase = .signedOut(nil)
        }
    }

    /// Stands in for the Apple sheet under UI testing only.
    func signInForTesting() {
        guard APIConfig.isUITesting else { return }
        lock.bind(to: AdminProfile.sample.email)
        phase = .locked(.sample)
    }

    func signOut(reason: SignOutReason = .userInitiated) async {
        lock.clear()
        clearCache()
        if !APIConfig.isUITesting {
            try? await Supa.client.auth.signOut()
        }
        phase = .signedOut(reason)
    }

    /// Called by the store when a 401 survives the client's refresh.
    func handleUnauthorized() async {
        await signOut(reason: .expired)
    }

    // MARK: The app lock

    func unlock() {
        guard case .locked(let profile) = phase else { return }
        phase = .ready(profile)
    }

    func relock() {
        guard case .ready(let profile) = phase else { return }
        phase = .locked(profile)
    }

    func didEnterBackground() { backgroundedAt = Date() }

    func willEnterForeground() {
        if lock.shouldRelock(backgroundedAt: backgroundedAt) { relock() }
        backgroundedAt = nil
    }

    // MARK: Cached identity

    /// Email and role only — not a secret, and it lets an offline start still reach
    /// the lock screen instead of the sign-in screen.
    private var cachedProfile: AdminProfile? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(AdminProfile.self, from: data)
    }

    private func cache(_ profile: AdminProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }
}
