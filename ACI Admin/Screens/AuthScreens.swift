//
//  AuthScreens.swift
//  ACI Admin
//
//  Sign-in and PIN lock, ported from admin-screens-a.jsx.
//

import AuthenticationServices
import SwiftUI

// MARK: - Sign in

struct AdSignInView: View {
    @Environment(\.palette) private var c
    @Environment(AdminSession.self) private var session

    /// Why the last attempt ended, when it ended badly. The server's 403 sentence is
    /// already the copy this screen wants.
    var reason: AdminSession.SignOutReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("✦")
                .font(AdFont.serif(19))
                .foregroundStyle(c.glow)
                .frame(width: 44, height: 44)
                .background(c.surfaceRaised, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border))
                .padding(.top, 24)

            Spacer(minLength: 0)

            Text("CONSOLE")
                .font(AdFont.label())
                .tracking(2.3)
                .foregroundStyle(c.glow)

            Text("Ridge Community\n\(Text("Cathedral.").italic().foregroundStyle(c.glow))")
                .font(AdFont.display(44))
                .lineSpacing(0)
                .foregroundStyle(c.fg)
                .padding(.top, 12)

            Text("Notices, recurring sends, events and translation review for the ACI Ridge app.")
                .font(AdFont.sans(14.5))
                .lineSpacing(4)
                .foregroundStyle(c.fgSecondary)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(.top, 16)

            signInButton
                .padding(.top, 34)

            Text(reason?.message ?? "Console access is granted by the church office. Your Apple ID must match an approved address.")
                .font(AdFont.sans(11.5))
                .lineSpacing(2.5)
                .foregroundStyle(reason?.message == nil ? c.fgMuted : c.destructive)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(SanctumBackground())
    }

    @ViewBuilder
    private var signInButton: some View {
        if APIConfig.isUITesting {
            // The system sheet can't be driven from a UI test, so the walk-through
            // build keeps the hand-styled button and goes straight through.
            Button { session.signInForTesting() } label: { appleButtonLabel }
                .buttonStyle(.plain)
        } else {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                Task { await session.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(c.isDark ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .clipShape(.rect(cornerRadius: 12))
            .opacity(session.signingIn ? 0.6 : 1)
            .disabled(session.signingIn)
            .accessibilityIdentifier("Sign in with Apple")
        }
    }

    private var appleButtonLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: "apple.logo")
                .font(.system(size: 17, weight: .medium))
            Text("Sign in with Apple")
                .font(AdFont.sans(15.5, weight: .semibold))
        }
        .foregroundStyle(c.inverseFg)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(c.inverseBg, in: .rect(cornerRadius: 12))
    }
}

// MARK: - PIN lock

struct AdPinLockView: View {
    @Environment(\.palette) private var c
    @Environment(AdminSession.self) private var session

    let profile: AdminProfile

    private enum Mode: Equatable {
        case create
        case confirm(String)
        case unlock
    }

    @State private var digits = ""
    @State private var mode: Mode = .unlock
    @State private var error: String?
    @State private var shake = 0

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "del"]

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(c.glow)
                .frame(width: 52, height: 52)
                .background(c.surfaceRaised, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(c.border))
                .padding(.top, 38)

            Text(title)
                .font(AdFont.display(30))
                .foregroundStyle(c.fg)
                .multilineTextAlignment(.center)
                .padding(.top, 22)

            Text(error ?? subtitle)
                .font(AdFont.sans(13))
                .foregroundStyle(error == nil ? c.fgMuted : c.destructive)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < digits.count ? c.glow : .clear)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(i < digits.count ? c.glow : c.border, lineWidth: 1.5))
                }
            }
            .padding(.top, 34)
            .modifier(ShakeEffect(travel: CGFloat(shake)))
            .animation(.default, value: shake)

            Spacer(minLength: 0)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(74), spacing: 16), count: 3), spacing: 16) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    if key.isEmpty {
                        Color.clear.frame(width: 74, height: 74)
                    } else if key == "del" {
                        keypadButton(key) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(c.fgMuted)
                        }
                    } else {
                        keypadButton(key) {
                            Text(key)
                                .font(AdFont.serif(27))
                                .foregroundStyle(c.fg)
                        }
                    }
                }
            }

            if mode == .unlock, session.lock.biometricsAvailable {
                Button {
                    Task {
                        if await session.lock.biometricUnlock() { session.unlock() }
                    }
                } label: {
                    Text("Use Face ID instead")
                        .font(AdFont.sans(13, weight: .semibold))
                        .foregroundStyle(c.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
                .padding(.bottom, 28)
            } else {
                Color.clear.frame(height: 1).padding(.top, 26).padding(.bottom, 28)
            }
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SanctumBackground())
        .onAppear { mode = session.lock.isEnrolled ? .unlock : .create }
    }

    private var title: String {
        switch mode {
        case .create: return "Choose a PIN"
        case .confirm: return "Confirm your PIN"
        case .unlock: return "Enter your PIN"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create: return "Four digits, asked for whenever the console has been away."
        case .confirm: return "Once more, to be sure."
        case .unlock: return profile.email
        }
    }

    private func keypadButton(_ key: String, @ViewBuilder label: () -> some View) -> some View {
        Button {
            tap(key)
        } label: {
            label()
                .frame(width: 74, height: 74)
                .background(key == "del" ? .clear : c.card, in: .circle)
                .overlay(Circle().strokeBorder(key == "del" ? .clear : c.cardEdge))
        }
        .buttonStyle(.plain)
    }

    private func tap(_ key: String) {
        error = nil
        if key == "del" {
            if !digits.isEmpty { digits.removeLast() }
            return
        }
        guard digits.count < 4 else { return }
        digits.append(key)
        guard digits.count == 4 else { return }

        let entered = digits
        // Let the fourth dot land before the screen changes under them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            submit(entered)
        }
    }

    private func submit(_ entered: String) {
        switch mode {
        case .create:
            digits = ""
            mode = .confirm(entered)

        case .confirm(let first):
            digits = ""
            guard entered == first else {
                mode = .create
                fail("Those didn't match. Start again.")
                return
            }
            try? session.lock.enroll(pin: entered)
            session.unlock()

        case .unlock:
            if session.lock.verify(pin: entered) {
                digits = ""
                session.unlock()
            } else {
                digits = ""
                if session.lock.isLockedOut {
                    // Five wrong tries: start over with Apple. Two taps to get back.
                    Task { await session.signOut(reason: .userInitiated) }
                } else {
                    let left = AppLock.maxAttempts - session.lock.failedAttempts
                    fail("Not that one. \(left) \(left == 1 ? "try" : "tries") left.")
                }
            }
        }
    }

    private func fail(_ message: String) {
        error = message
        shake += 1
    }
}

/// A short sideways nudge when a PIN is wrong.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(travel * .pi * 4) * 8, y: 0))
    }
}
