import SwiftUI

/// Spacing, radius, material and color tokens. Built on `AppColor`/`Font`
/// (the design system) so every screen shares one Apple-native language.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        // Spec semantic tokens
        static let outer: CGFloat = 28        // outer window margin
        static let gridGap: CGFloat = 16      // grid gap between cards
        static let cardPadding: CGFloat = 20  // inner card padding
    }

    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 10
        static let small: CGFloat = 8
        static let pill: CGFloat = 999
    }

    enum Sizes {
        static let icon: CGFloat = 22
        static let buttonHeight: CGFloat = 44
        static let sidebarWidth: CGFloat = 238
        static let windowMinWidth: CGFloat = 1080
        static let windowMinHeight: CGFloat = 720
    }

    /// Backward-compatible palette aliases (semantic → spec colors).
    enum Palette {
        static let accent  = AppColor.primary
        static let safe    = AppColor.success
        static let caution = AppColor.warning
        static let risky   = AppColor.danger

        static let primary = AppColor.primary
        static let success = AppColor.success
        static let warning = AppColor.warning
        static let danger  = AppColor.danger

        static let cardStroke     = AppColor.divider.opacity(0.6)
        static let cardFill       = AppColor.card
        static let windowFill     = AppColor.background
        static let sidebarFill    = AppColor.sidebar
        static let divider        = AppColor.divider
        static let secondaryText  = AppColor.secondaryText
        static let primaryText    = AppColor.primaryText
    }
}

// MARK: - Card styling

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    var elevated: Bool
    @Environment(\.colorScheme) private var scheme
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous) }
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(shape.fill(AppColor.card.opacity(scheme == .dark ? 0.92 : 0.86)))
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.strokeBorder(AppGradient.cardHairline, lineWidth: 0.8).opacity(scheme == .dark ? 0.35 : 1))
            .shadow(color: Color(hex: "3B2F8F").opacity(scheme == .dark ? 0.0 : (elevated ? 0.10 : 0.05)), radius: elevated ? 22 : 14, x: 0, y: elevated ? 10 : 6)
    }
}

private struct GlassCardModifier: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Standard solid card surface.
    func card(padding: CGFloat = Theme.Spacing.cardPadding, elevated: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, elevated: elevated))
    }

    /// Translucent surface for transient overlays.
    func glassCard(padding: CGFloat = Theme.Spacing.cardPadding) -> some View {
        modifier(GlassCardModifier(padding: padding))
    }
}

// MARK: - Model → UI bridges

extension SafetyLevel {
    var tint: Color {
        switch self {
        case .safe: return AppColor.success
        case .caution: return AppColor.warning
        case .risky: return AppColor.danger
        }
    }

    /// Localized risk label used by cards and review surfaces.
    var riskLabel: String { title }
}

extension MemoryPressure {
    var tint: Color {
        switch self {
        case .normal: return AppColor.success
        case .warning: return AppColor.warning
        case .critical: return AppColor.danger
        }
    }
}

extension CleanGroup {
    var tint: Color {
        switch self {
        case .storage: return AppColor.primary
        case .developer: return Color(lightHex: "AF52DE", darkHex: "BF5AF2")
        case .system: return Color(lightHex: "5AC8FA", darkHex: "64D2FF")
        }
    }
}

/// A fraction (0...1) mapped to a green→orange→red usage color (kept for
/// backward compatibility with existing components).
func usageTint(for fraction: Double) -> Color {
    StatusColor.forUsage(fraction)
}
