import SwiftUI

/// Storage page category card. Per spec, the primary action is "Review" (not a
/// raw delete) — the user always inspects before anything is removed.
struct StorageCategoryCard: View {
    let icon: String
    let tint: Color
    let title: String
    let description: String
    let locationDescription: String
    let sizeBytes: Int64
    let level: SafetyLevel
    var itemCount: Int = 0
    var isScanning: Bool = false
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemName: icon, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.mcCardTitle)
                    Text(description)
                        .font(.mcCaption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                RiskBadge(level: level)
            }

            HStack(alignment: .firstTextBaseline) {
                if isScanning {
                    ProgressView().controlSize(.small)
                    Text(tr("common.scanning")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                } else {
                    Text(ByteFormat.string(fromBytes: sizeBytes))
                        .font(.mcMetric(26))
                        .foregroundStyle(AppColor.primaryText)
                        .contentTransition(.numericText())
                    if itemCount > 0 {
                        Text(tr("comp.storCard.itemCount", itemCount))
                            .font(.mcCaption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                Spacer()
                Button(action: onReview) {
                    Text(tr("common.review")).frame(minWidth: 64)
                }
                .controlSize(.large)
                .disabled(isScanning || sizeBytes == 0)
            }

            Text(locationDescription)
                .font(.mcMicro)
                .foregroundStyle(AppColor.secondaryText.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .hoverLift()
    }
}
