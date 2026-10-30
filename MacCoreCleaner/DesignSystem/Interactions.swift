import SwiftUI

/// A subtle, HIG-appropriate hover response for cards: a gentle border and
/// shadow lift without resizing the layout under the pointer.
private struct HoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(AppColor.primary.opacity(hovering ? 0.40 : 0), lineWidth: 1)
            )
            .onHover { state in
                if reduceMotion { hovering = state }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = state } }
            }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }

    /// Premium window/screen background: base color with a faint top-leading
    /// accent glow for subtle depth (never gaudy).
    func screenBackground() -> some View {
        background(PastelBackdrop().ignoresSafeArea())
    }
}

/// Soft pastel backdrop: base color plus large blurred color fields.
struct PastelBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let strength = scheme == .dark ? 0.22 : 0.55
        ZStack {
            AppColor.background
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Circle().fill(Color(hex: "C9C2FF").opacity(strength)).frame(width: w * 0.7).blur(radius: 120).offset(x: w * 0.45, y: -h * 0.25)
                Circle().fill(Color(hex: "FFD3E2").opacity(strength * 0.8)).frame(width: w * 0.5).blur(radius: 120).offset(x: -w * 0.1, y: h * 0.55)
                Circle().fill(Color(hex: "BFE3FF").opacity(strength * 0.7)).frame(width: w * 0.45).blur(radius: 110).offset(x: w * 0.7, y: h * 0.6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Brand gradient call-to-action button (the app's primary action style).
struct PrimaryGradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background {
                if let tint { shape.fill(tint) } else { shape.fill(AppGradient.brandDiagonal) }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
            .shadow(color: Color(hex: "6D5DF6").opacity(isEnabled ? 0.30 : 0), radius: 10, x: 0, y: 5)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryGradientButtonStyle {
    /// `.buttonStyle(.primaryGradient)` — the premium CTA style.
    static var primaryGradient: PrimaryGradientButtonStyle { PrimaryGradientButtonStyle() }
}

/// Quiet capsule button for secondary actions on cards.
struct SoftCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var onColor = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(onColor ? Color.white : AppColor.primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(onColor ? Color.white.opacity(configuration.isPressed ? 0.30 : 0.20) : AppColor.primary.opacity(configuration.isPressed ? 0.18 : 0.10)))
            .overlay(Capsule().strokeBorder(onColor ? Color.white.opacity(0.45) : .clear, lineWidth: 0.8))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension ButtonStyle where Self == SoftCapsuleButtonStyle {
    static var softCapsule: SoftCapsuleButtonStyle { SoftCapsuleButtonStyle() }
    static var softCapsuleOnColor: SoftCapsuleButtonStyle { SoftCapsuleButtonStyle(onColor: true) }
}

/// A tinted, rounded "app icon" tile holding an SF Symbol — the recurring icon
/// treatment across cards.
struct IconTile: View {
    let systemName: String
    var tint: Color = AppColor.primary
    var size: CGFloat = 36
    /// When set, the tile is filled with this gradient and the glyph is white.
    var colors: [Color]? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
        Group {
            if let colors {
                shape.fill(AppGradient.tile(colors))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
                    .overlay(Image(systemName: systemName).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
            } else {
                shape.fill(tint.opacity(0.12))
                    .overlay(Image(systemName: systemName).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(tint))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Small monospaced status line with a colored dot ("● SCAN COMPLETE · 14:32").
struct StatusEyebrow: View {
    let text: String
    var color: Color = AppColor.success
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
                .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 3))
            Text(text.uppercased()).font(.mcMono(10, weight: .medium)).tracking(0.8).foregroundStyle(AppColor.primary)
        }
    }
}
