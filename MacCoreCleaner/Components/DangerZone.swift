import SwiftUI

/// A red-accented, collapsed-by-default container for destructive actions
/// (per spec: process termination lives here and is never emphasized on the
/// default screen).
struct DangerZone<Content: View>: View {
    var title: String = tr("comp.danger.title")
    var message: String
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                if reduceMotion { expanded.toggle() }
                else { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(AppColor.danger)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.mcCardTitle)
                        Text(message)
                            .font(.mcCaption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(AppColor.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                content()
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(AppColor.danger.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(AppColor.danger.opacity(0.30), lineWidth: 1)
        )
    }
}
