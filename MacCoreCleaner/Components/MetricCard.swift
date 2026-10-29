import SwiftUI

/// The primary Dashboard card: icon tile, title, a large value with unit, an
/// optional usage bar, a colored status line, and an optional trend chip.
/// Designed to read at a glance like a native macOS widget.
struct MetricCard: View {
    let title: String
    let icon: String
    var tint: Color = AppColor.primary

    let value: String
    var unit: String? = nil
    var caption: String? = nil

    var progress: Double? = nil
    /// Optional telemetry history → renders a sparkline instead of the bar.
    var samples: [Double]? = nil
    var statusText: String? = nil
    var statusColor: Color? = nil
    var trend: TrendChip? = nil

    /// Optional tap (e.g. navigate to the detail screen).
    var action: (() -> Void)? = nil

    var body: some View {
        let content = VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                IconTile(systemName: icon, tint: tint)
                Text(title).font(.mcCaption.weight(.medium))
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                if let trend { trend }
                if action != nil {
                    Image(systemName: "arrow.up.right").font(.mcMicro)
                        .foregroundStyle(AppColor.secondaryText.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.mcMetric(30))
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.mcBodyMedium)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }

            if let samples, samples.count > 1 {
                Sparkline(values: samples, tint: AppColor.primary)
                    .frame(height: 28)
            } else if let progress {
                UsageBar(fraction: progress, tint: statusColor ?? tint)
            }

            Spacer(minLength: 0)

            if let statusText {
                HStack(spacing: 6) {
                    Circle().fill(statusColor ?? AppColor.secondaryText).frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.mcCaption.weight(.medium))
                        .foregroundStyle(statusColor ?? AppColor.secondaryText)
                        .lineLimit(2)
                }
            } else if let caption {
                Text(caption)
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .card()
        .hoverLift()

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

#Preview {
    HStack {
        MetricCard(title: "저장공간", icon: "internaldrive.fill", tint: .blue,
                   value: "128", unit: "GB", progress: 0.62, statusText: "여유 있음",
                   statusColor: .green, trend: TrendChip(up: false, text: "2.1GB"))
        MetricCard(title: "메모리", icon: "memorychip.fill", tint: .purple,
                   value: "11.2", unit: "GB", progress: 0.7, statusText: "정상", statusColor: .green)
    }
    .padding()
    .frame(width: 560)
}
