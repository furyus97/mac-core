import SwiftUI
import Charts

struct HardwareMonitorView: View {
    let metric: DashboardMetric
    @StateObject private var vm: HardwareMonitorViewModel
    private let automaticallyRefresh: Bool
    @State private var paused = false

    init(metric: DashboardMetric, vm: HardwareMonitorViewModel? = nil, automaticallyRefresh: Bool = true) {
        self.metric = metric
        _vm = StateObject(wrappedValue: vm ?? HardwareMonitorViewModel())
        self.automaticallyRefresh = automaticallyRefresh
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Circle().fill(paused ? AppColor.secondaryText : AppColor.success).frame(width: 6, height: 6)
                    Text(tr(paused ? "telemetry.paused" : "telemetry.live")).font(.mcCaption)
                    Spacer()
                    if let updated = vm.updated {
                        Text(updated, style: .time).font(.mcMono(11)).foregroundStyle(AppColor.secondaryText)
                    }
                    Button(tr(paused ? "telemetry.resume" : "telemetry.pause")) { paused.toggle() }
                        .buttonStyle(.bordered)
                }
                if vm.updated == nil && automaticallyRefresh {
                    HStack { ProgressView().controlSize(.small); Text(tr("dash.measuring")).font(.mcBody) }
                        .frame(maxWidth: .infinity, minHeight: 200).card()
                } else {
                    metricContent
                }
            }.padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .task(id: paused) {
            guard automaticallyRefresh, !paused else { return }
            vm.resetBaseline()
            while !Task.isCancelled {
                await vm.refresh(metric)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    @ViewBuilder
    private var metricContent: some View {
                switch metric {
                case .temperature:
                    HStack(spacing: 16) {
                        summary(tr("temp.src.average"), TelemetryFormat.number(vm.temperature.average, unit: "°C"))
                        summary(tr("sensor.name"), "\(vm.temperature.sensorCount)")
                        summary(tr("temp.src.max"), TelemetryFormat.number(vm.temperature.maxValue, unit: "°C"))
                    }
                    SensorInspector(snapshot: vm.temperature, ranges: vm.ranges).card()
                    historyCard(title: tr("temp.src.max"), points: vm.history, unit: "°C")
                case .battery:
                    BatteryInspector(battery: vm.battery).card()
                    if vm.battery.isPresent {
                        HStack(alignment: .top, spacing: 16) {
                            historyCard(title: tr("power.batteryWatts"), points: vm.history, unit: "W")
                            historyCard(title: tr("power.system"), points: vm.secondaryHistory, unit: "W")
                        }
                    }
                case .network:
                    HStack(spacing: 16) {
                        summary(tr("detail.downSpeed"), ByteFormat.networkRate(vm.network.downBytesPerSec))
                        summary(tr("detail.upSpeed"), ByteFormat.networkRate(vm.network.upBytesPerSec))
                    }
                    NetworkInspector(snapshot: vm.network).card()
                    HStack(alignment: .top, spacing: 16) {
                        historyCard(title: tr("detail.downSpeed"), points: vm.history, unit: "MB/s", divisor: 1_000_000)
                        historyCard(title: tr("detail.upSpeed"), points: vm.secondaryHistory, unit: "MB/s", divisor: 1_000_000)
                    }
                default: EmptyView()
                }
    }

    private func summary(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            Text(value).font(.mcMetric(28)).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func historyCard(title: String, points: [TelemetryPoint], unit: String, divisor: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.mcCardTitle)
                Spacer()
                Text(unit).font(.mcMono(11)).foregroundStyle(AppColor.secondaryText)
            }
            if points.count > 1 {
                Chart(points) { point in
                    LineMark(x: .value("Time", point.id), y: .value(unit, point.value / divisor))
                        .foregroundStyle(AppColor.primary).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .frame(height: 140)
                .accessibilityLabel(title)
            } else {
                Text(tr("telemetry.waiting")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            Text(tr("telemetry.history")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct NetworkInspector: View {
    let snapshot: NetworkSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("network.interfaces")).font(.mcCardTitle)
            ForEach(snapshot.interfaces) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.id).font(.mcMono(14, weight: .semibold)).padding(.bottom, 6)
                    TelemetryRow(title: tr("detail.downSpeed"), value: ByteFormat.networkRate(item.downBytesPerSec))
                    TelemetryRow(title: tr("detail.upSpeed"), value: ByteFormat.networkRate(item.upBytesPerSec))
                    TelemetryRow(title: tr("detail.totalDown"), value: ByteFormat.networkBytes(Double(item.receivedBytes)))
                    TelemetryRow(title: tr("detail.totalUp"), value: ByteFormat.networkBytes(Double(item.sentBytes)))
                }
            }
            Text(tr("network.note")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
