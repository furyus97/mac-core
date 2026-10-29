import SwiftUI

/// The "Review" sheet shown before any removal (Storage & Developer). The user
/// inspects and selects exactly what will be removed; the parent then presents
/// `ConfirmCleanSheet` for the final confirmation.
struct CategoryReviewSheet: View {
    @Binding var result: CategoryScanResult
    let onClean: () -> Void
    let onClose: () -> Void

    private var category: CleanCategory { result.category }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
        .background(AppColor.background)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconTile(systemName: category.systemImage, tint: category.group.tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).font(.mcSectionTitle)
                Text(category.subtitle).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            }
            Spacer()
            RiskBadge(level: category.defaultSafety)
        }
        .padding(Theme.Spacing.xl)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if result.isEmpty {
                    EmptyStateView(systemImage: "checkmark.circle", title: tr("comp.review.empty"))
                        .frame(height: 280)
                } else {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { result.allSelected },
                            set: { v in for i in result.items.indices { result.items[i].isSelected = v } }
                        )) { Text(tr("common.selectAll")).font(.mcCaption) }
                        .toggleStyle(.checkbox)
                        Spacer()
                        Text(tr("comp.review.selectedCount", result.selectedCount, result.itemCount))
                            .font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)

                    ForEach($result.items) { $item in
                        CleanableItemRow(item: $item)
                            .padding(.horizontal, Theme.Spacing.xl)
                        Divider().opacity(0.4).padding(.leading, Theme.Spacing.xl)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(ByteFormat.string(fromBytes: result.selectedBytes))
                    .font(.mcCardTitle).monospacedDigit()
                Text(tr("comp.review.freedCaption")).font(.mcMicro).foregroundStyle(AppColor.secondaryText)
            }
            Spacer()
            Button(tr("common.close"), action: onClose)
                .keyboardShortcut(.cancelAction)
            Button {
                onClean()
            } label: {
                Label(tr("common.clean"), systemImage: "trash")
            }
            .buttonStyle(.primaryGradient)
            .disabled(result.selectedCount == 0)
        }
        .padding(Theme.Spacing.xl)
    }
}
