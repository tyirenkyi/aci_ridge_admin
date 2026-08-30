//
//  AuthScreens.swift
//  ACI Admin
//
//  Sign-in and PIN lock, ported from admin-screens-a.jsx.
//  Prototype only — the buttons navigate, nothing authenticates.
//

import SwiftUI

// MARK: - Sign in

struct AdSignInView: View {
    @Environment(\.palette) private var c
    let onNext: () -> Void

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

            Button(action: onNext) {
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
            .buttonStyle(.plain)
            .padding(.top, 34)

            Text("Console access is granted by the church office. Your Apple ID must match an approved address.")
                .font(AdFont.sans(11.5))
                .lineSpacing(2.5)
                .foregroundStyle(c.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(SanctumBackground())
    }
}

// MARK: - PIN lock

struct AdPinLockView: View {
    @Environment(\.palette) private var c
    let onUnlock: () -> Void

    @State private var pinLength = 0

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

            Text("Enter your PIN")
                .font(AdFont.display(30))
                .foregroundStyle(c.fg)
                .padding(.top, 22)

            Text(AdminUser.current.name)
                .font(AdFont.sans(13))
                .foregroundStyle(c.fgMuted)
                .padding(.top, 8)

            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < pinLength ? c.glow : .clear)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(i < pinLength ? c.glow : c.border, lineWidth: 1.5))
                }
            }
            .padding(.top, 34)

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

            Button {
                unlock()
            } label: {
                Text("Use Face ID instead")
                    .font(AdFont.sans(13, weight: .semibold))
                    .foregroundStyle(c.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SanctumBackground())
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
        if key == "del" {
            pinLength = max(0, pinLength - 1)
        } else if pinLength >= 3 {
            pinLength = 4
            unlock()
        } else {
            pinLength += 1
        }
    }

    private func unlock() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onUnlock()
        }
    }
}
