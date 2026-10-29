import SwiftUI

/// A compact metric card: icon, title, a large value and an optional subtitle.
/// Used across the Dashboard and monitor screens.
struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = Theme.Palette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(title).eyebrow()
            }
            Text(value)
                .font(.mcMetric(24))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.mcMicro)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview {
    HStack {
        StatCard(title: "사용 가능", value: "128 GB", subtitle: "총 512 GB 중", systemImage: "internaldrive", tint: .blue)
        StatCard(title: "정리 가능", value: "12.4 GB", subtitle: "안전하게 확보", systemImage: "sparkles", tint: .green)
    }
    .padding()
    .frame(width: 520)
}
