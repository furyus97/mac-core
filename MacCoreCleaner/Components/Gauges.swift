import SwiftUI

/// A circular usage gauge (0...1) with a centered label. Used for disk / CPU /
/// memory at-a-glance readings.
struct RingGauge: View {
    let fraction: Double
    var lineWidth: CGFloat = 6
    var label: String? = nil
    var caption: String? = nil
    var tint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var color: Color { tint ?? usageTint(for: clamped) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.secondaryText.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: clamped)
            VStack(spacing: 3) {
                Text(label ?? ByteFormat.percent(clamped))
                    .font(.mcMetric(22))
                if let caption {
                    Text(caption).eyebrow()
                }
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption ?? tr("comp.gauge.usage")) \(ByteFormat.percent(clamped))")
    }
}

/// A horizontal usage bar with optional leading/trailing labels.
struct UsageBar: View {
    let fraction: Double
    var tint: Color? = nil
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var color: Color { tint ?? usageTint(for: clamped) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.secondaryText.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * clamped))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: clamped)
            }
        }
        .frame(height: height)
        .accessibilityLabel(ByteFormat.percent(clamped))
    }
}

#Preview {
    HStack(spacing: 24) {
        RingGauge(fraction: 0.42, caption: "디스크")
            .frame(width: 120, height: 120)
        RingGauge(fraction: 0.93, caption: "CPU")
            .frame(width: 120, height: 120)
        VStack { UsageBar(fraction: 0.6); UsageBar(fraction: 0.95) }
            .frame(width: 160)
    }
    .padding()
}
