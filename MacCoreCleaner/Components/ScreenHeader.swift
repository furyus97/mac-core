import SwiftUI

struct ScreenHeader: View {
    let item: NavItem
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tr("ui.subtitle"))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Spacer(minLength: 12)
            Label(tr("sidebar.localMode"), systemImage: "lock.shield")
                .font(.mcMicro)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.vertical, 20)
        .background(AppColor.background)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}
