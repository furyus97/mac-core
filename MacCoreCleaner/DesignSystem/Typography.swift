import SwiftUI

/// Mac Core type scale (SF Pro Display / Text — the system font, used natively).
/// Large sizes automatically render in SF Pro Display; body/caption in SF Pro Text.
extension Font {
    /// 34 / Bold — Dashboard large title.
    static let mcDashboardTitle = Font.system(size: 34, weight: .heavy, design: .rounded)
    /// 28 / Bold — screen large title.
    static let mcLargeTitle = Font.system(size: 28, weight: .heavy, design: .rounded)
    /// 22 / Semibold — section title.
    static let mcSectionTitle = Font.system(size: 22, weight: .semibold)
    /// 18 / Semibold — card title.
    static let mcCardTitle = Font.system(size: 18, weight: .semibold)
    /// 15 / Regular — body.
    static let mcBody = Font.system(size: 15, weight: .regular)
    /// 15 / Medium — emphasized body.
    static let mcBodyMedium = Font.system(size: 15, weight: .medium)
    /// 13 / Regular — caption / secondary.
    static let mcCaption = Font.system(size: 13, weight: .regular)
    /// 11 / Medium — micro labels / badges.
    static let mcMicro = Font.system(size: 11, weight: .medium)
    /// 11 / Semibold — UPPERCASE tracked "eyebrow" label (technical accent).
    static let mcEyebrow = Font.system(size: 11, weight: .semibold)

    /// Large rounded, tabular metric numbers (counts, sizes) — modern + stable.
    static func mcMetric(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// Hero display number ("31.7 GB").
    static func mcHero(_ size: CGFloat = 64) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }

    /// Monospaced technical readout (per-core %, table cells, telemetry).
    static func mcMono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Text {
    /// Secondary-colored caption helper.
    func mcSecondary() -> some View {
        self.font(.mcCaption).foregroundStyle(AppColor.secondaryText)
    }

    /// UPPERCASE, letter-spaced, secondary "eyebrow" label — the technical accent
    /// used above values across the app.
    func eyebrow(_ color: Color = AppColor.secondaryText) -> some View {
        self.font(.mcEyebrow)
            .tracking(0.2)
            .foregroundStyle(color)
    }
}
