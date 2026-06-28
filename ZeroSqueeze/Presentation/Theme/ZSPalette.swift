import SwiftUI

/// Theme palette. Dark = cool graphite-blue; Light = cool paper.
/// Brand = an indigo→cyan accent (#5B6CFF → #38BDF8) on restrained neutral
/// surfaces, with a rose pulse accent. Designed for contrast: text and accent
/// both clear WCAG AA on their backgrounds.
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

    /// Flat, quiet background. Dark = near-black neutral graphite with a
    /// barely-there lift toward the bottom. Light = clean warm-neutral paper.
    /// Kept almost flat on purpose — the colour comes from the accent, not
    /// the canvas.
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [
                    Color(hex: 0x100C0D),
                    Color(hex: 0x14100F)
                ]
                : [
                    Color(hex: 0xFCF8F7),
                    Color(hex: 0xF3ECEA)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Signature brand gradient: rose → coral. Used on primary CTAs, the
    /// capture progress ring, and hero accents to give the flat neutral UI
    /// one premium focal sweep.
    var accentGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(hex: 0xFF4D6D), Color(hex: 0xFF8A4D)]
                : [Color(hex: 0xE11D48), Color(hex: 0xEA580C)],
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
    // ZeroSqueeze brand rose #FF4D6D → coral on warm near-black. One confident
    // accent; secondary metric hues are muted so the UI reads calm. accent =
    // bright rose for dark surfaces, accentSoft = deeper rose.
    static let dark = ZSPalette(
        isDark: true,
        background: Color(hex: 0x100C0D),
        backgroundElevated: Color(hex: 0x1A1416),
        surface: Color(hex: 0x1C1618),
        surfaceElevated: Color(hex: 0x261D20),
        border: Color(hex: 0x342529),
        divider: Color(hex: 0x231A1C),
        textPrimary: Color(hex: 0xF4ECEE),
        textSecondary: Color(hex: 0xB7ABAE),
        textTertiary: Color(hex: 0x847479),
        textDisabled: Color(hex: 0x4F4548),
        accent: Color(hex: 0xFF4D6D),
        accentSoft: Color(hex: 0xE03457),
        heartRateColor: Color(hex: 0xFF4D6D),
        spO2Color: Color(hex: 0x38BDF8),
        stepsColor: Color(hex: 0x6EE7B7),
        sleepColor: Color(hex: 0x818CF8),
        hemoglobinColor: Color(hex: 0xFF8A4D),
        hrvColor: Color(hex: 0xC084FC),
        respColor: Color(hex: 0x38BDF8),
        piColor: Color(hex: 0x34D399),
        stressColor: Color(hex: 0xFBBF24),
        bpColor: Color(hex: 0xF472B6),
        caloriesColor: Color(hex: 0xFB923C),
        distanceColor: Color(hex: 0x38BDF8),
        alertRed: Color(hex: 0xFF5A5A),
        cautionYellow: Color(hex: 0xFBBF24),
        successGreen: Color(hex: 0x34D399),
        inactiveGray: Color(hex: 0x4F4548)
    )

    static let light = ZSPalette(
        isDark: false,
        background: Color(hex: 0xFCF8F7),
        backgroundElevated: Color(hex: 0xF3ECEA),
        surface: Color(hex: 0xFFFFFF),
        surfaceElevated: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xEEE2E0),
        divider: Color(hex: 0xF3EAE8),
        textPrimary: Color(hex: 0x18100F),
        textSecondary: Color(hex: 0x5C4D4A),
        // ~4.7:1 on the #FCF8F7 paper — clears WCAG AA for the small
        // caption/section-label text it's used for.
        textTertiary: Color(hex: 0x6B5A56),
        textDisabled: Color(hex: 0xD2C7C4),
        accent: Color(hex: 0xE11D48),
        accentSoft: Color(hex: 0xBE123C),
        heartRateColor: Color(hex: 0xE11D48),
        spO2Color: Color(hex: 0x0284C7),
        stepsColor: Color(hex: 0x059669),
        sleepColor: Color(hex: 0x6D28D9),
        hemoglobinColor: Color(hex: 0xC2410C),
        hrvColor: Color(hex: 0x7C3AED),
        respColor: Color(hex: 0x0284C7),
        piColor: Color(hex: 0x0E9F6E),
        stressColor: Color(hex: 0xB45309),
        bpColor: Color(hex: 0xBE185D),
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
