import SwiftUI

/// Theme palette — ZeroSqueeze identity v2.
///
/// Cool **ink** base (deep blue-black, not warm graphite) carrying one
/// confident signature: a **rose → violet pulse** gradient (#FF3D71 → #A24BFF)
/// on primary CTAs, rings and hero accents. Secondary metric hues are cool
/// (cyan, sky, violet) with warm reserved for the pulse/heart and hemoglobin —
/// so the canvas reads calm and clinical while the heartbeat reads vivid. Text
/// and accent both clear WCAG AA on their backgrounds.
struct ZSPalette {
    let isDark: Bool
    let background: Color
    let backgroundElevated: Color
    let surface: Color
    let surfaceElevated: Color
    let border: Color
    let divider: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textDisabled: Color
    let accent: Color
    let accentSoft: Color
    let heartRateColor: Color
    let spO2Color: Color
    let stepsColor: Color
    let sleepColor: Color
    let hemoglobinColor: Color
    let hrvColor: Color
    let respColor: Color
    let piColor: Color
    let stressColor: Color
    let bpColor: Color
    let caloriesColor: Color
    let distanceColor: Color
    let alertRed: Color
    let cautionYellow: Color
    let successGreen: Color
    let inactiveGray: Color

    /// Flat, quiet background. Dark = deep cool ink with a barely-there lift.
    /// Light = clean cool paper. The colour comes from the accent, not canvas.
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(hex: 0x0A0E18), Color(hex: 0x0C1322)]
                : [Color(hex: 0xF6F8FC), Color(hex: 0xEAEEF6)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Signature brand gradient: rose → violet "pulse". Used on primary CTAs,
    /// the capture progress ring, and hero accents — the one premium focal
    /// sweep over the cool neutral UI.
    var accentGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(hex: 0xFF3D71), Color(hex: 0xA24BFF)]
                : [Color(hex: 0xE11D6B), Color(hex: 0x7C3AED)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func vitalGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.95), color.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func cardGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(isDark ? 0.10 : 0.05), color.opacity(0.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension ZSPalette {
    // Signature pulse rose #FF3D71 → violet #A24BFF on deep cool ink. One
    // confident accent; cool secondary hues keep the UI calm and clinical.
    static let dark = ZSPalette(
        isDark: true,
        background: Color(hex: 0x0A0E18),
        backgroundElevated: Color(hex: 0x111726),
        surface: Color(hex: 0x141B2B),
        surfaceElevated: Color(hex: 0x1B2438),
        border: Color(hex: 0x27324A),
        divider: Color(hex: 0x1A2236),
        textPrimary: Color(hex: 0xEAF0FA),
        textSecondary: Color(hex: 0xA7B2C6),
        textTertiary: Color(hex: 0x717C90),
        textDisabled: Color(hex: 0x3E4759),
        accent: Color(hex: 0xFF3D71),
        accentSoft: Color(hex: 0xD62E63),
        heartRateColor: Color(hex: 0xFF3D71),
        spO2Color: Color(hex: 0x22D3EE),
        stepsColor: Color(hex: 0x4ADE80),
        sleepColor: Color(hex: 0x818CF8),
        hemoglobinColor: Color(hex: 0xFF7A4D),
        hrvColor: Color(hex: 0x22D3EE),
        respColor: Color(hex: 0x38BDF8),
        piColor: Color(hex: 0x2FD27A),
        stressColor: Color(hex: 0xFFB020),
        bpColor: Color(hex: 0xA24BFF),
        caloriesColor: Color(hex: 0xFF8A4D),
        distanceColor: Color(hex: 0x38BDF8),
        alertRed: Color(hex: 0xFF5470),
        cautionYellow: Color(hex: 0xFFB020),
        successGreen: Color(hex: 0x2FD27A),
        inactiveGray: Color(hex: 0x3E4759)
    )

    static let light = ZSPalette(
        isDark: false,
        background: Color(hex: 0xF6F8FC),
        backgroundElevated: Color(hex: 0xEAEEF6),
        surface: Color(hex: 0xFFFFFF),
        surfaceElevated: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xE2E8F2),
        divider: Color(hex: 0xEEF2F8),
        textPrimary: Color(hex: 0x0B1220),
        textSecondary: Color(hex: 0x46506A),
        // ~4.6:1 on the #F6F8FC paper — clears WCAG AA for small text.
        textTertiary: Color(hex: 0x5B6678),
        textDisabled: Color(hex: 0xC5CDDA),
        accent: Color(hex: 0xE11D6B),
        accentSoft: Color(hex: 0xBE185D),
        heartRateColor: Color(hex: 0xE11D6B),
        spO2Color: Color(hex: 0x0E9AAE),
        stepsColor: Color(hex: 0x059669),
        sleepColor: Color(hex: 0x6D28D9),
        hemoglobinColor: Color(hex: 0xC2410C),
        hrvColor: Color(hex: 0x0E8FA3),
        respColor: Color(hex: 0x0284C7),
        piColor: Color(hex: 0x0E9F6E),
        stressColor: Color(hex: 0xB45309),
        bpColor: Color(hex: 0x7C3AED),
        caloriesColor: Color(hex: 0xC2410C),
        distanceColor: Color(hex: 0x0284C7),
        alertRed: Color(hex: 0xC81E4A),
        cautionYellow: Color(hex: 0xB45309),
        successGreen: Color(hex: 0x0E9F6E),
        inactiveGray: Color(hex: 0xA1A1AA)
    )
}

private struct ZSPaletteKey: EnvironmentKey {
    static let defaultValue: ZSPalette = .dark
}

extension EnvironmentValues {
    var zsPalette: ZSPalette {
        get { self[ZSPaletteKey.self] }
        set { self[ZSPaletteKey.self] = newValue }
    }
}
