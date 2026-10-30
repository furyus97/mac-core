import SwiftUI

/// Startup-disk usage pinned above Settings in the sidebar.
struct SidebarDiskCard: View {
    @State private var disk: DiskSnapshot = .unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(tr("sidebar.disk")).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppColor.primaryText)
                Spacer()
                Text(disk.totalBytes > 0 ? "\(ByteFormat.string(fromBytes: disk.totalBytes - disk.freeBytes)) / \(ByteFormat.string(fromBytes: disk.totalBytes))" : "—")
                    .font(.mcMono(10)).foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.divider.opacity(0.7))
                    Capsule().fill(AppGradient.brand).frame(width: max(6, geo.size.width * disk.usedFraction))
                }
            }
            .frame(height: 5)
            Text(tr("sidebar.diskFree", ByteFormat.string(fromBytes: disk.freeBytes)))
                .font(.system(size: 10)).foregroundStyle(AppColor.secondaryText)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.card.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppColor.divider.opacity(0.6), lineWidth: 0.6))
        .task {
            while !Task.isCancelled {
                disk = AppServices.shared.storage.diskSnapshot()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
