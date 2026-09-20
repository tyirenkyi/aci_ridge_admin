//
//  AppLock.swift
//  ACI Admin
//
//  The PIN and Face ID gate in front of the console.
//
//  The prototype's version was decorative — an Int counter that unlocked on any
//  three taps. This one is real, because the console is one tap away from pushing to
//  the entire congregation and phones get lent out.
//

import CryptoKit
import Foundation
import LocalAuthentication
import Observation

@Observable
final class AppLock {
    /// How long the console may sit in the background before it re-locks.
    static let graceInterval: TimeInterval = 5 * 60
    static let maxAttempts = 5

    private let keychain = Keychain(service: "com.aciridge.ACI-Admin.applock")
    private var account: String = "default"

    private(set) var failedAttempts = 0
    private(set) var isEnrolled = false

    /// Ties the stored PIN to one admin, so signing in as someone else can't reuse it.
    func bind(to account: String) {
        self.account = account
        // Testing runs against a known PIN so the click-through can get past the gate.
        if APIConfig.isUITesting, keychain.get(account: account) == nil {
            try? enroll(pin: "1234")
        }
        isEnrolled = keychain.get(account: account) != nil
    }

    var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    enum LockError: Error { case badPin }

    func enroll(pin: String) throws {
        guard pin.count >= 4 else { throw LockError.badPin }
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        keychain.set(salt + Self.hash(pin: pin, salt: salt), account: account)
        isEnrolled = true
        failedAttempts = 0
    }

    /// Compares against the stored salted hash. The PIN itself is never written down.
    func verify(pin: String) -> Bool {
        guard let stored = keychain.get(account: account), stored.count == 48 else { return false }
        let salt = stored.prefix(16)
        let expected = stored.suffix(32)
        let matches = Self.hash(pin: pin, salt: salt) == Data(expected)
        failedAttempts = matches ? 0 : failedAttempts + 1
        return matches
    }

    var isLockedOut: Bool { failedAttempts >= Self.maxAttempts }

    func biometricUnlock() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        do {
            // deviceOwnerAuthentication falls back to the device passcode, so an admin
            // whose Face ID fails isn't stranded.
            return try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "Unlock the ACI Ridge console")
        } catch {
            return false
        }
    }

    func clear() {
        keychain.delete(account: account)
        isEnrolled = false
        failedAttempts = 0
    }

    func shouldRelock(backgroundedAt: Date?) -> Bool {
        guard let backgroundedAt else { return true }
        return Date().timeIntervalSince(backgroundedAt) > Self.graceInterval
    }

    private static func hash(pin: String, salt: some DataProtocol) -> Data {
        var hasher = SHA256()
        hasher.update(data: Data(salt))
        hasher.update(data: Data(pin.utf8))
        return Data(hasher.finalize())
    }
}
