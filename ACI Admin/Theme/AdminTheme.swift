//
//  AdminTheme.swift
//  ACI Admin
//
//  Sanctum palette (cathedral · jewel · stained-glass) in light and dark,
//  ported from the design's themes.jsx. Screens read `@Environment(\.palette)`.
//

import SwiftUI

// MARK: - Color helpers

extension Color {
    /// `Color(hex: 0x1a1838)`
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// `Color(rgba: 26, 24, 56, 0.08)`
    init(rgba r: Double, _ g: Double, _ b: Double, _ a: Double) {
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

// MARK: - Palette

struct Palette {
    let isDark: Bool

    let bg: Color
    let bgGradient: [Color]
    let surface: Color
    let surfaceRaised: Color
    let card: Color
    let cardEdge: Color
    let fg: Color
    let fgSecondary: Color
    let fgMuted: Color
    let accent: Color
    let accentSoft: Color
    let glow: Color
    let glowSoft: Color
    let emerald: Color
    let sapphire: Color
    let border: Color
    let borderSoft: Color
    let onAccent: Color
    let destructive: Color
    let progressTrack: Color
    let progressFill: Color

    // Derived tones used by chips, bars and toasts.
    var greenBg: Color { isDark ? Color(rgba: 80, 180, 130, 0.16) : Color(rgba: 30, 74, 58, 0.10) }
    var greenFg: Color { isDark ? Color(hex: 0x7fd6a6) : emerald }
    var redBg: Color { isDark ? Color(rgba: 226, 108, 82, 0.16) : Color(rgba: 138, 26, 26, 0.09) }
    var goldFg: Color { isDark ? glow : Color(hex: 0x6a5010) }
    var onGlow: Color { isDark ? Color(hex: 0x1a1024) : Color(hex: 0x241a06) }
    var dangerEdge: Color { isDark ? Color(rgba: 226, 108, 82, 0.40) : Color(rgba: 138, 26, 26, 0.28) }
    var barBg: Color { isDark ? Color(rgba: 6, 9, 42, 0.94) : Color(rgba: 243, 237, 217, 0.96) }
    var topBarBg: Color { isDark ? Color(rgba: 10, 12, 42, 0.86) : Color(rgba: 243, 237, 217, 0.90) }
    var toastBg: Color { isDark ? Color(rgba: 16, 22, 74, 0.97) : Color(rgba: 26, 24, 56, 0.95) }
    var toastFg: Color { isDark ? fg : Color(hex: 0xf6f0dc) }
    var previewBg: Color { isDark ? Color(rgba: 255, 255, 255, 0.06) : Color(rgba: 26, 24, 56, 0.05) }
    var draftBg: Color { isDark ? Color(rgba: 255, 255, 255, 0.03) : Color(rgba: 26, 24, 56, 0.025) }
    var rejectNoteBg: Color { isDark ? Color(rgba: 226, 108, 82, 0.10) : Color(rgba: 138, 26, 26, 0.06) }
    var inverseBg: Color { isDark ? Color(hex: 0xf6f0dc) : Color(hex: 0x101026) }
    var inverseFg: Color { isDark ? Color(hex: 0x101026) : Color(hex: 0xf6f0dc) }

    static let light = Palette(
        isDark: false,
        bg: Color(hex: 0xebe4d2),
        bgGradient: [Color(hex: 0xf0e6cb), Color(hex: 0xebe4d2), Color(hex: 0xd4c8a8)],
        surface: Color(hex: 0xf3edd9),
        surfaceRaised: Color(rgba: 26, 24, 56, 0.04),
        card: Color(hex: 0xf6f0dc),
        cardEdge: Color(rgba: 26, 24, 56, 0.08),
        fg: Color(hex: 0x1a1838),
        fgSecondary: Color(hex: 0x3e3a5e),
        fgMuted: Color(hex: 0x7a7689),
        accent: Color(hex: 0x6b1a3a),
        accentSoft: Color(hex: 0x8a2a4c),
        glow: Color(hex: 0xc8a04a),
        glowSoft: Color(rgba: 200, 160, 74, 0.35),
        emerald: Color(hex: 0x1e4a3a),
        sapphire: Color(hex: 0x2c3a78),
        border: Color(rgba: 26, 24, 56, 0.13),
        borderSoft: Color(rgba: 26, 24, 56, 0.06),
        onAccent: Color(hex: 0xf6f0dc),
        destructive: Color(hex: 0x8a1a1a),
        progressTrack: Color(rgba: 26, 24, 56, 0.14),
        progressFill: Color(hex: 0xc8a04a)
    )

    static let dark = Palette(
        isDark: true,
        bg: Color(hex: 0x06092a),
        bgGradient: [Color(hex: 0x0e1448), Color(hex: 0x06092a), Color(hex: 0x02041a)],
        surface: Color(hex: 0x0d1240),
        surfaceRaised: Color(rgba: 229, 184, 90, 0.06),
        card: Color(hex: 0x10164a),
        cardEdge: Color(rgba: 229, 184, 90, 0.13),
        fg: Color(hex: 0xede4cc),
        fgSecondary: Color(hex: 0xb8aa88),
        fgMuted: Color(hex: 0x6e6680),
        accent: Color(hex: 0xc54363),
        accentSoft: Color(hex: 0x8a2a4c),
        glow: Color(hex: 0xe5b85a),
        glowSoft: Color(rgba: 229, 184, 90, 0.28),
        emerald: Color(hex: 0x3a8a64),
        sapphire: Color(hex: 0x6680e8),
        border: Color(rgba: 237, 228, 204, 0.13),
        borderSoft: Color(rgba: 237, 228, 204, 0.06),
        onAccent: Color(hex: 0x06092a),
        destructive: Color(hex: 0xe26c52),
        progressTrack: Color(rgba: 237, 228, 204, 0.14),
        progressFill: Color(hex: 0xe5b85a)
    )

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Type

/// The design pairs Bodoni Moda (display) with Inter Tight (sans).
/// Stand-ins: the system serif (New York) for display, SF Pro for sans.
enum AdFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func serif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Small uppercase label with wide tracking (eyebrows, chips, field labels).
    static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .bold)
    }
}

// MARK: - Background gradient

struct SanctumBackground: View {
    @Environment(\.palette) private var c

    var body: some View {
        ZStack {
            c.bg
            RadialGradient(
                colors: c.bgGradient,
                center: .init(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}
