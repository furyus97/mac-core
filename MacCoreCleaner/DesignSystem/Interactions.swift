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
        background(AppColor.background.ignoresSafeArea())
    }
}

/// Premium gradient call-to-action button (the app's primary action style).
struct PrimaryGradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = AppColor.primary

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.black.opacity(0.88) : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                shape.fill(tint)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryGradientButtonStyle {
    /// `.buttonStyle(.primaryGradient)` — the premium CTA style.
    static var primaryGradient: PrimaryGradientButtonStyle { PrimaryGradientButtonStyle() }
}

/// A tinted, rounded "app icon" tile holding an SF Symbol — the recurring icon
/// treatment across cards.
struct IconTile: View {
    let systemName: String
    var tint: Color = AppColor.primary
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        shape
            .fill(AppColor.secondaryText.opacity(0.07))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(AppColor.secondaryText)
            )
    }
}
