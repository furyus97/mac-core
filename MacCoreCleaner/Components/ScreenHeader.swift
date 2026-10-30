import SwiftUI

struct ScreenHeader: View {
    let item: NavItem
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(systemName: item.systemImage, tint: AppColor.primary, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tr("ui.subtitle"))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Spacer(minLength: 12)
            Label(tr("sidebar.localMode"), systemImage: "lock.shield.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(AppColor.card.opacity(0.8)))
                .overlay(Capsule().strokeBorder(AppColor.divider.opacity(0.6), lineWidth: 0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.top, 18).padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.divider.opacity(0.4)).frame(height: 0.5) }
    }
}
