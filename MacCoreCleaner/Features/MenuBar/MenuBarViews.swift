import SwiftUI
import AppKit

/// The popover panel shown when the menu-bar item is clicked.
struct MenuBarPanel: View {
    @ObservedObject var vm: MenuBarMonitorViewModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var localization: LocalizationManager
    var automaticallyRefresh = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                IconTile(systemName: "bolt.heart.fill", tint: AppColor.primary, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mac Core").font(.system(size: 14, weight: .bold))
                    Text(tr("ui.subtitle"))
                        .font(.system(size: 10)).foregroundStyle(AppColor.secondaryText)
                }
            }

            Divider()

            ForEach(settings.menuBarMetrics) { metric in
                metricRow(metric)
            }

            if settings.menuBarExpandedDetails {
                if settings.menuBarMetrics.contains(.temperature) {
                    Text(vm.snapshot.temperatureSnapshot.readings.first { $0.id == settings.menuBarSensorID }?.displayName
                         ?? (settings.menuBarSensorID.isEmpty ? tr(settings.temperatureSource.titleKey) : tr("menubar.sensorMissing")))
                        .font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                }
                if settings.menuBarMetrics.contains(where: { [.battery, .batteryPower, .systemPower].contains($0) }) {
                    TelemetryRow(title: tr("power.input"), value: TelemetryFormat.number(vm.snapshot.battery.electrical.inputWatts, unit: "W"))
                    TelemetryRow(title: tr("power.batteryWatts"), value: TelemetryFormat.number(vm.snapshot.battery.electrical.batteryWatts, unit: "W"))
                }
            }

            Divider()

            Button(action: openMainWindow) {
                Label(tr("menubar.open"), systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.primaryGradient)

            Button(tr("menubar.quit")) { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.mcCaption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 320)
        .background(AppColor.card)
        .preferredColorScheme(settings.appearance.colorScheme)
        .environment(\.locale, localization.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .task { if automaticallyRefresh { vm.startIfNeeded() } }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain && !window.isMiniaturized {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let window = NSApp.windows.first(where: \.canBecomeMain) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Ask Launch Services to reopen this single-instance app. SwiftUI then
        // recreates the WindowGroup even if the last main window was closed.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in }
    }

    @ViewBuilder
    private func metricRow(_ metric: MenuBarMetric) -> some View {
        let snapshot = vm.snapshot
        switch metric {
        case .cpu:
            row(icon: metric.systemImage, tint: AppColor.secondaryText, label: metric.title,
                value: ByteFormat.percent(snapshot.cpu), fraction: snapshot.cpu)
        case .memory:
            row(icon: metric.systemImage, tint: AppColor.secondaryText, label: metric.title,
                value: MenuBarTitleFormatter.value(metric, snapshot: snapshot, settings: settings), fraction: snapshot.memFraction)
        case .temperature:
            row(icon: metric.systemImage, tint: AppColor.secondaryText, label: metric.title,
                value: MenuBarTitleFormatter.value(metric, snapshot: snapshot, settings: settings))
        case .diskFree:
            row(icon: metric.systemImage, tint: AppColor.secondaryText,
                label: settings.menuBarDiskPercent ? tr("dash.card.storage") : metric.title,
                value: MenuBarTitleFormatter.value(metric, snapshot: snapshot, settings: settings),
                fraction: snapshot.diskUsedFraction)
        case .networkDown:
            row(icon: metric.systemImage, tint: AppColor.primary, label: metric.title,
                value: ByteFormat.networkRate(snapshot.network.downBytesPerSec))
        case .networkUp:
            row(icon: metric.systemImage, tint: AppColor.success, label: metric.title,
                value: ByteFormat.networkRate(snapshot.network.upBytesPerSec))
        case .battery:
            let battery = snapshot.battery
            row(
                icon: battery.isCharging ? "battery.100.bolt" : metric.systemImage,
                tint: battery.isPresent && battery.percentage < 20 ? AppColor.danger : AppColor.success,
                label: metric.title,
                value: battery.isPresent ? "\(battery.percentage)%" : tr("menubar.batteryAC"),
                fraction: battery.isPresent ? Double(battery.percentage) / 100 : nil
            )
        case .batteryPower, .systemPower:
            row(icon: metric.systemImage, tint: AppColor.secondaryText, label: metric.title,
                value: MenuBarTitleFormatter.value(metric, snapshot: snapshot, settings: settings))
        }
    }

    private func row(
        icon: String,
        tint: Color,
        label: String,
        value: String,
        fraction: Double? = nil
    ) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
                Text(label).font(.mcCaption)
                Spacer()
                Text(value).font(.mcMono(12, weight: .medium))
            }
            if let fraction {
                UsageBar(fraction: fraction, height: 4)
            }
        }
    }
}
