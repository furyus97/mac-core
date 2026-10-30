import SwiftUI

/// The Mac Core color system. Exact spec values, resolved dynamically per
/// appearance (Apple HIG: semantic, adaptive, never hard-coded per view).
enum AppColor {
    // Surfaces — airy lavender light theme, deep ink dark theme.
    static let background = Color(lightHex: "F5F4FA", darkHex: "131219")
    static let card       = Color(lightHex: "FFFFFF", darkHex: "1E1D27")
    static let sidebar    = Color(lightHex: "EFEDF7", darkHex: "17161F")
    static let divider    = Color(lightHex: "E3E0EE", darkHex: "34323F")

    // Semantic
    static let primary    = Color(lightHex: "5B4FE0", darkHex: "A79CFF")
    static let success    = Color(lightHex: "16936A", darkHex: "6FD6A8")
    static let warning    = Color(lightHex: "C27C0E", darkHex: "F2C26B")
    static let danger     = Color(lightHex: "D9384F", darkHex: "FF8A9A")

    // Text
    static let primaryText   = Color(lightHex: "16141F", darkHex: "EEEDF5")
    static let secondaryText = Color(lightHex: "686579", darkHex: "A9A6BA")

    /// Soft tinted fill behind icons / chips.
    static func tintedFill(_ color: Color, _ opacity: Double = 0.14) -> Color {
        color.opacity(opacity)
    }
}

/// The four signature tile colors used for at-a-glance cards and feature icons.
enum TileColor {
    static let cleanup    = [Color(hex: "E5485F"), Color(hex: "A3203A")]
    static let speed      = [Color(hex: "7FB52A"), Color(hex: "3E6B12")]
    static let protection = [Color(hex: "7067F0"), Color(hex: "3F33C4")]
    static let apps       = [Color(hex: "3D8EF2"), Color(hex: "1D4FB0")]
    static let files      = [Color(hex: "F29A3D"), Color(hex: "B85A12")]
    static let system     = [Color(hex: "2FB3B0"), Color(hex: "13706E")]
}

/// Gradients for the light, glassy surface treatment.
enum AppGradient {
    /// Brand gradient used for hero numbers, primary buttons and highlights.
    static let brand = LinearGradient(colors: [Color(hex: "4F46E5"), Color(hex: "8B5CF6"), Color(hex: "E26BB4")],
                                      startPoint: .leading, endPoint: .trailing)
    static let brandDiagonal = LinearGradient(colors: [Color(hex: "6D5DF6"), Color(hex: "A06BF0"), Color(hex: "E77BB8")],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Rich two-stop gradient for a colored tile.
    static func tile(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Tinted fill for icon tiles (top-lit).
    static func tile(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.28), color.opacity(0.14)],
                       startPoint: .top, endPoint: .bottom)
    }
    /// Angular sweep for ring gauges.
    static func ring(_ color: Color) -> AngularGradient {
        AngularGradient(gradient: Gradient(colors: [color.opacity(0.55), color]),
                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
    }
    /// Vertical fade for sparkline / chart area fills.
    static func area(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.30), color.opacity(0.02)],
                       startPoint: .top, endPoint: .bottom)
    }
    /// Hairline card border with a top highlight.
    static var cardHairline: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.7), AppColor.divider.opacity(0.6)],
                       startPoint: .top, endPoint: .bottom)
    }
    /// Faint top-down sheen overlaid on card surfaces for depth.
    static var cardSheen: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.08), Color.clear],
                       startPoint: .top, endPoint: .center)
    }
}

/// Status mapping for health/risk visuals.
enum StatusColor {
    /// 0...1 usage → success/warning/danger.
    static func forUsage(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.70: return AppColor.success
        case ..<0.90: return AppColor.warning
        default:      return AppColor.danger
        }
    }

    /// 0...100 health score → danger/warning/success (higher is better).
    static func forScore(_ score: Int) -> Color {
        switch score {
        case ..<50: return AppColor.danger
        case ..<80: return AppColor.warning
        default:    return AppColor.success
        }
    }
}
