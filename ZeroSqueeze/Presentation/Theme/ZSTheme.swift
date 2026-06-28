import SwiftUI

enum ZSSpacing {
    static let xs: CGFloat = 3
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let standard: CGFloat = 14
    static let l: CGFloat = 18
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum ZSShapes {
    static let pill = Capsule()
    static let smallShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
}

/// ZeroSqueeze's identity pairs a **rounded** display scg for titles and big
/// numbers (warm, friendly, distinct from a stock SF-Pro health app) with
/// plain SF Pro for body/caption text (maximum legibility at small sizes).
///
/// Text-level tokens map to system `TextStyle`s so they scale with the user's
/// Dynamic Type setting (an accessibility requirement for a health app). The
/// large display numbers (`hero`, `metricValue`) stay at fixed point sizes —
/// they're already oversized, and the metric cards that use them apply
/// `minimumScaleFactor` to stay on one line; letting them grow unbounded would
/// break those fixed-height layouts.
enum ZSTypography {
    static var captionTight: Font { .system(.caption2, design: .default).weight(.medium) }
    static var caption: Font { .system(.caption, design: .default) }
    static var chipLabel: Font { .system(.caption2, design: .rounded).weight(.semibold) }
    static var body: Font { .system(.subheadline, design: .default) }
    static var bodyEmphasized: Font { .system(.subheadline, design: .default).weight(.semibold) }
    static var title: Font { .system(.title3, design: .rounded).weight(.semibold) }
    static var largeTitle: Font { .system(.title, design: .rounded).weight(.bold) }
    static var hero: Font { .system(size: 52, weight: .bold, design: .rounded) }
    static var metricLabel: Font { .system(.caption2, design: .rounded).weight(.semibold) }
    static var metricValue: Font { .system(size: 30, weight: .bold, design: .rounded) }
    static var metricValueSmall: Font { .system(.title3, design: .rounded).weight(.semibold) }
}

struct ZSThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let palette: ZSPalette = colorScheme == .dark ? .dark : .light
        content
            .environment(\.zsPalette, palette)
            .tint(palette.accent)
    }
}

extension View {
    func zsTheme() -> some View { modifier(ZSThemeModifier()) }
}

// ── Primary button ────────────────────────────────────────────────

/// Full-width primary CTA filled with the signature emerald→teal accent
/// gradient. Replaces ad-hoc `.borderedProminent` buttons so every primary
/// action looks identical and on-brand.
struct ZSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.zsPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ZSTypography.bodyEmphasized)
            // Enabled: high-contrast ink/white on the bright gradient.
            // Disabled: muted text on the muted fill — using the gradient
            // ink here would be near-invisible on the dark inactive fill.
            .foregroundColor(
                isEnabled
                    ? (palette.isDark ? Color(hex: 0x07120E) : .white)
                    : palette.textTertiary
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, ZSSpacing.standard)
            .background(
                Group {
                    if isEnabled {
                        palette.accentGradient
                    } else {
                        palette.inactiveGray.opacity(0.4)
                    }
                }
            )
            .clipShape(ZSShapes.smallShape)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ZSPrimaryButtonStyle {
    static var zsPrimary: ZSPrimaryButtonStyle { ZSPrimaryButtonStyle() }
}

// ── Card modifiers ────────────────────────────────────────────────

extension View {
    /// Glass-style card with subtle border.
    func zsCard() -> some View { modifier(ZSCardModifier(tint: nil)) }

    /// Card tinted by accent color (vital cards).
    func zsCard(tint: Color) -> some View { modifier(ZSCardModifier(tint: tint)) }
}

private struct ZSCardModifier: ViewModifier {
    let tint: Color?
    @Environment(\.zsPalette) private var palette

    func body(content: Content) -> some View {
        content
            .padding(ZSSpacing.standard)
            .background(
                ZStack {
                    palette.surface
                    if let tint {
                        palette.cardGradient(tint)
                    }
                }
            )
            .clipShape(ZSShapes.cardShape)
            .overlay(ZSShapes.cardShape.stroke(palette.border, lineWidth: 0.5))
            .shadow(
                color: palette.isDark ? Color.black.opacity(0.4) : Color.black.opacity(0.06),
                radius: 12, x: 0, y: 4
            )
    }
}

// ── Modern polish modifiers ───────────────────────────────────────

extension View {
    /// Subtle neon halo behind brand-accent values. Slightly visible on dark
    /// surfaces, near-invisible on light — keeps the look quiet but premium.
    func heroNeonShadow(_ color: Color, intensity: CGFloat = 1) -> some View {
        modifier(HeroNeonShadowModifier(color: color, intensity: intensity))
    }

    /// Heavy uppercase tracked section label, the same shape used across
    /// every "VITAL SIGNS · 1D" header. Standardising means a single tweak
    /// later (font size, tracking, color) ripples everywhere.
    func sectionLabel() -> some View {
        modifier(SectionLabelModifier())
    }
}

private struct HeroNeonShadowModifier: ViewModifier {
    let color: Color
    let intensity: CGFloat
    @Environment(\.zsPalette) private var palette
    func body(content: Content) -> some View {
        // Toned down from a heavy neon halo to a subtle ambient shadow.
        // The hero number stands on weight + size alone, not on a glow.
        let alpha = palette.isDark ? 0.18 : 0.06
        return content
            .shadow(color: color.opacity(alpha * intensity), radius: 8 * intensity, x: 0, y: 2)
    }
}

private struct SectionLabelModifier: ViewModifier {
    @Environment(\.zsPalette) private var palette
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .bold, design: .default))
            .tracking(1.5)
            // Was textTertiary — too faint against dark surfaces for a label
            // that anchors every card. textSecondary lifts the hierarchy.
            .foregroundColor(palette.textSecondary)
    }
}

// ── Chip action ───────────────────────────────────────────────────

/// A small, bordered accent "chip" for inline secondary actions (e.g.
/// "New Heart Check", "Edit"). Replaces bare accent-coloured text labels so
/// the affordance reads as a tappable control, not a caption.
extension View {
    func zsChip(_ palette: ZSPalette) -> some View {
        self
            .font(ZSTypography.chipLabel)
            .foregroundColor(palette.accent)
            .padding(.horizontal, ZSSpacing.standard)
            .padding(.vertical, ZSSpacing.s)
            .background(palette.accent.opacity(palette.isDark ? 0.14 : 0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(palette.accent.opacity(0.4), lineWidth: 0.75))
    }
}

// ── Haptics ────────────────────────────────────────────────────────

import UIKit

/// `@MainActor` because `UI*FeedbackGenerator` itself is MainActor-isolated
/// in iOS 17+. Strict concurrency would otherwise flag every haptic call.
@MainActor
enum ZSHaptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
