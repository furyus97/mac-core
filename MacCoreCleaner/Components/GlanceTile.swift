import SwiftUI

/// A colorful at-a-glance tile: icon, title, a large value with unit, a caption
/// and one action. Used for the four summary cards on the dashboard.
struct GlanceTile: View {
    let title: String
    let icon: String
    let colors: [Color]
    let value: String
    var unit: String? = nil
    let caption: String
    let action: String
    let perform: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.22)))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.mcHero(40)).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.system(size: 13, weight: .semibold)).opacity(0.85) }
            }
            Text(caption).font(.system(size: 12)).opacity(0.85).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: perform) { Label(action, systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle()) }
                .buttonStyle(.softCapsuleOnColor)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background {
            shape.fill(AppGradient.tile(colors))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Color.white.opacity(0.16)).frame(width: 140).blur(radius: 20).offset(x: 40, y: -50)
                }
                .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
        .shadow(color: (colors.last ?? .black).opacity(0.25), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// Places the icon after the title ("Review →").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon.font(.system(size: 10, weight: .bold)) }
    }
}
