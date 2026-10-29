import SwiftUI

/// The Mac Core color system. Exact spec values, resolved dynamically per
/// appearance (Apple HIG: semantic, adaptive, never hard-coded per view).
enum AppColor {
    // Surfaces
    static let background = Color(lightHex: "F4F4F3", darkHex: "1B1C1E")
    static let card       = Color(lightHex: "FFFFFF", darkHex: "242527")
    static let sidebar    = Color(lightHex: "ECECEB", darkHex: "202123")
    static let divider    = Color(lightHex: "DCDDDD", darkHex: "3A3B3D")

    // Semantic
    static let primary    = Color(lightHex: "356887", darkHex: "97BDD3")
    static let success    = Color(lightHex: "357557", darkHex: "9CBEA9")
    static let warning    = Color(lightHex: "926316", darkHex: "D9BA80")
    static let danger     = Color(lightHex: "B74747", darkHex: "E69D9D")

    // Text
    static let primaryText   = Color(lightHex: "242629", darkHex: "ECEDEE")
    static let secondaryText = Color(lightHex: "61666C", darkHex: "B1B5BA")

    /// Soft tinted fill behind icons / chips.
    static func tintedFill(_ color: Color, _ opacity: Double = 0.14) -> Color {
        color.opacity(opacity)
    }
}

/// Gradients used for the modern, technical surface treatment (subtle, never gaudy).
enum AppGradient {
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
    /// Hairline card border with a top highlight (subtle "lit from above" edge).
    static var cardHairline: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.14), AppColor.divider.opacity(0.45)],
                       startPoint: .top, endPoint: .bottom)
    }
    /// Faint top-down sheen overlaid on card surfaces for depth.
    static var cardSheen: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.05), Color.clear],
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
