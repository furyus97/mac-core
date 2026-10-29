import SwiftUI

struct TelemetryRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(title).font(.mcBody).foregroundStyle(AppColor.secondaryText)
                Spacer(minLength: 8)
                Text(value).font(.mcMono(13, weight: .medium))
                    .foregroundStyle(AppColor.primaryText).textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }.padding(.vertical, 9)
            Divider().opacity(0.45)
        }
    }
}

struct BatteryInspector: View {
    let battery: BatterySnapshot
    private var e: BatteryElectrical { battery.electrical }
    var body: some View {
        if battery.isPresent {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteFormat.percent(Double(battery.percentage) / 100)).font(.mcMetric(42))
                    Spacer()
                    Text(tr(battery.isCharging ? "dash.battery.charging" : battery.isPluggedIn ? "dash.battery.pluggedIn" : "dash.battery.onBattery"))
                        .font(.mcBodyMedium).foregroundStyle(AppColor.secondaryText)
                }
                UsageBar(fraction: Double(battery.percentage) / 100, tint: AppColor.primary, height: 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20)], alignment: .leading, spacing: 12) {
                    powerSummary("power.input", e.inputWatts)
                    powerSummary("power.system", e.systemWatts)
                    powerSummary("power.batteryWatts", e.batteryWatts)
                }
                Divider()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 24)], alignment: .leading, spacing: 24) {
                    section("power.battery") {
                        TelemetryRow(title: tr("power.voltage"), value: TelemetryFormat.number(e.voltage, unit: "V", digits: 2))
                        TelemetryRow(title: tr("power.current"), value: TelemetryFormat.number(e.current, unit: "A", digits: 2))
                        TelemetryRow(title: tr("power.batteryWatts"), value: TelemetryFormat.number(e.batteryWatts, unit: "W"))
                        TelemetryRow(title: tr("dash.card.temperature"), value: TelemetryFormat.number(e.temperature, unit: "°C"))
                        TelemetryRow(title: tr("power.chargeTime"), value: battery.timeToFullMinutes.map { tr("detail.minutes", $0) } ?? "—")
                        TelemetryRow(title: tr("detail.timeLeft"), value: battery.timeToEmptyMinutes.map { tr("detail.minutes", $0) } ?? "—")
                    }
                    section("power.capacity") {
                        TelemetryRow(title: tr("power.remaining"), value: TelemetryFormat.capacity(e.currentCapacity))
                        TelemetryRow(title: tr("power.maximum"), value: TelemetryFormat.capacity(e.maximumCapacity))
                        TelemetryRow(title: tr("power.design"), value: TelemetryFormat.capacity(e.designCapacity))
                        TelemetryRow(title: tr("power.ratio"), value: e.capacityRatio.map { TelemetryFormat.number($0 * 100, unit: "%", digits: 0) } ?? "—")
                        TelemetryRow(title: tr("detail.cycles"), value: battery.cycleCount.map(String.init) ?? "—")
                        TelemetryRow(title: tr("detail.condition"), value: battery.localizedHealth ?? "—")
                    }
                    section("power.adapter") {
                        TelemetryRow(title: tr("power.rated"), value: TelemetryFormat.number(e.adapterRatedWatts, unit: "W", digits: 0))
                        TelemetryRow(title: tr("power.input"), value: TelemetryFormat.number(e.inputWatts, unit: "W"))
                        TelemetryRow(title: tr("power.voltage"), value: TelemetryFormat.number(e.inputVoltage, unit: "V", digits: 2))
                        TelemetryRow(title: tr("power.current"), value: TelemetryFormat.number(e.inputCurrent, unit: "A", digits: 2))
                        TelemetryRow(title: tr("power.currentLimit"), value: TelemetryFormat.number(e.adapterCurrentLimit, unit: "A", digits: 2))
                        TelemetryRow(title: tr("power.system"), value: TelemetryFormat.number(e.systemWatts, unit: "W"))
                    }
                }
                Text(tr("power.note")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            EmptyStateView(systemImage: "powerplug", title: tr("dash.battery.noBattery"))
        }
    }

    private func section<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr(key)).font(.mcCardTitle).padding(.bottom, 8)
            content()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func powerSummary(_ key: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr(key)).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            Text(TelemetryFormat.number(value, unit: "W")).font(.mcMetric(25))
                .foregroundStyle(AppColor.primaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SensorInspector: View {
    let snapshot: TemperatureSnapshot
    var ranges: [String: ClosedRange<Double>] = [:]
    @State private var query = ""
    @State private var hottestFirst = false
    private var readings: [TemperatureReading] {
        snapshot.readings.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { hottestFirst ? $0.celsius > $1.celsius : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tr("sensor.list", snapshot.readings.count)).font(.mcCardTitle)
                Spacer()
                Toggle(tr("sensor.hottest"), isOn: $hottestFirst).toggleStyle(.checkbox).font(.mcCaption)
            }
            TextField(tr("sensor.search"), text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Text(tr("sensor.name"))
                Spacer()
                Text(tr("sensor.current")).frame(width: 82, alignment: .trailing)
                if !ranges.isEmpty {
                    Text(tr("sensor.min" )).frame(width: 82, alignment: .trailing)
                    Text(tr("sensor.max")).frame(width: 82, alignment: .trailing)
                }
            }.font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            LazyVStack(spacing: 0) {
                ForEach(readings) { reading in
                    HStack(spacing: 12) {
                        Text(reading.displayName).font(.mcMono(12)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        sensorValue(reading.celsius)
                        if !ranges.isEmpty {
                            sensorValue(ranges[reading.id]?.lowerBound)
                            sensorValue(ranges[reading.id]?.upperBound)
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 8)
                    .background(AppColor.secondaryText.opacity(readings.firstIndex(of: reading).map { $0 % 2 == 0 } == true ? 0.045 : 0))
                }
            }
            if readings.isEmpty {
                Text(tr(snapshot.readings.isEmpty ? "dash.temp.unsupported" : "sensor.noResults"))
                    .font(.mcBody).foregroundStyle(AppColor.secondaryText).padding(.vertical, 24)
            }
            Text(tr("sensor.note")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func sensorValue(_ value: Double?) -> some View {
        Text(TelemetryFormat.number(value, unit: "°C"))
            .font(.mcMono(12, weight: .medium)).frame(width: 82, alignment: .trailing)
    }
}
