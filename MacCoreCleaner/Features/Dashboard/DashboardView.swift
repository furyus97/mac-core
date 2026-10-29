import SwiftUI

/// The Dashboard: Mac Health Score hero, live system metric cards (storage,
/// memory, CPU, battery, network, temperature), and top processes.
@MainActor
struct DashboardView: View {
    @StateObject private var vm: DashboardViewModel
    private let automaticallyRefresh: Bool

    init(vm: DashboardViewModel? = nil, automaticallyRefresh: Bool = true) {
        _vm = StateObject(wrappedValue: vm ?? DashboardViewModel())
        self.automaticallyRefresh = automaticallyRefresh
    }
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var nav: NavigationModel
    @State private var detailMetric: DashboardMetric?

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: Theme.Spacing.gridGap)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                SectionTitle(tr("dash.systemSection"))
                LazyVGrid(columns: columns, spacing: Theme.Spacing.gridGap) {
                    metricCards
                }
                topProcesses
                if let outcome = vm.lastOutcome {
                    CleanOutcomeBanner(outcome: outcome)
                }
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.dashboard"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.quickScan() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(tr("common.refresh"))
                .disabled(vm.isLoading)
            }
        }
        .task {
            guard automaticallyRefresh else { return }
            if settings.autoScanOnLaunch {
                await vm.quickScan()
            } else {
                await vm.refresh()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                await vm.refreshLive()
            }
        }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(
                items: vm.pendingItems,
                mode: $vm.mode,
                allowPermanent: false,
                onConfirm: { Task { await vm.confirmClean() } },
                onCancel: { vm.cancelClean() }
            )
        }
        .sheet(item: $detailMetric) { metric in
            MetricDetailSheet(
                metric: metric,
                vm: vm,
                onOpenScreen: { nav.selection = $0; detailMetric = nil },
                onClose: { detailMetric = nil }
            )
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 32) { healthRing; healthDetails }
                VStack(alignment: .leading, spacing: 24) { healthRing; healthDetails }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { reclaimableValue; Spacer(); scanActions }
                VStack(alignment: .leading, spacing: 16) { reclaimableValue; scanActions }
            }
        }
        .card(padding: 28, elevated: true)
    }

    @ViewBuilder
    private var healthRing: some View {
        if vm.health.components.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(tr("dash.measuring")).font(.mcCaption)
            }
            .frame(width: 176, height: 176)
        } else {
            HealthScoreRing(score: vm.health.score, word: vm.health.word,
                            caption: vm.health.caption, size: 160)
                .padding(8)
        }
    }

    private var healthDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tr("ui.live"), systemImage: "waveform.path")
                .font(.mcMicro).foregroundStyle(AppColor.primary)
            Text(tr("dash.healthScore")).font(.mcSectionTitle)
            ForEach(vm.health.components) { component in
                VStack(spacing: 6) {
                    HStack {
                        Text(component.name).font(.mcCaption)
                        Spacer(minLength: 16)
                        Text(component.detail).font(.mcCaption.monospacedDigit())
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    UsageBar(fraction: component.usageFraction, height: 5)
                }
            }
        }
        .frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)
    }

    private var reclaimableValue: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("dash.reclaimable")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            if vm.isEstimating {
                ProgressView().controlSize(.small)
            } else {
                Text(ByteFormat.string(fromBytes: vm.reclaimable))
                    .font(.mcMetric(26)).foregroundStyle(AppColor.primaryText)
            }
        }
    }

    private var scanActions: some View {
        HStack(spacing: 12) {
            Button { Task { await vm.quickScan() } } label: {
                Label(tr("common.quickScan"), systemImage: "magnifyingglass")
            }
            .controlSize(.large)
            .disabled(vm.isLoading || vm.isEstimating || vm.isPreparingClean || vm.isCleaning)
            Button { Task { await vm.safeClean() } } label: {
                Label(tr("common.safeClean"), systemImage: "sparkles")
            }
            .buttonStyle(.primaryGradient)
            .disabled(vm.isLoading || vm.isPreparingClean || vm.isCleaning)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: Metric cards

    @ViewBuilder
    private var metricCards: some View {
        // Storage
        MetricCard(
            title: tr("dash.card.storage"), icon: "externaldrive.fill", tint: .blue,
            value: ByteFormat.string(fromBytes: vm.disk.freeBytes), unit: tr("dash.unit.free"),
            progress: vm.disk.usedFraction,
            statusText: tr("dash.storage.usedStatus", ByteFormat.percent(vm.disk.usedFraction)),
            statusColor: StatusColor.forUsage(vm.disk.usedFraction),
            action: { detailMetric = .storage }
        )
        // Memory
        MetricCard(
            title: tr("dash.card.memory"), icon: "memorychip.fill", tint: .purple,
            value: ByteFormat.string(fromBytes: vm.memory.usedBytes), unit: tr("dash.unit.used"),
            progress: vm.memory.usedFraction,
            samples: vm.memHistory,
            statusText: tr("dash.memory.pressure", vm.memory.pressure.title),
            statusColor: vm.memory.pressure.tint,
            action: { detailMetric = .memory }
        )
        // CPU
        MetricCard(
            title: tr("dash.card.cpu"), icon: "cpu.fill", tint: .orange,
            value: ByteFormat.percent(vm.cpu.totalUsage), unit: nil,
            progress: vm.cpu.totalUsage,
            samples: vm.cpuHistory,
            statusText: tr("dash.cpu.coresUser", vm.cpu.coreCount, ByteFormat.percent(vm.cpu.userUsage)),
            statusColor: StatusColor.forUsage(vm.cpu.totalUsage),
            action: { detailMetric = .cpu }
        )
        // Battery
        batteryCard
        // Network
        MetricCard(
            title: tr("dash.card.network"), icon: "network", tint: .teal,
            value: ByteFormat.networkBytes(vm.network.downBytesPerSec), unit: "/s ↓",
            caption: tr("dash.network.upCaption", ByteFormat.networkBytes(vm.network.upBytesPerSec), vm.network.primaryInterface),
            samples: vm.netHistory,
            action: { detailMetric = .network }
        )
        // Temperature (real sensor via IOKit; honest fallback if unreadable)
        temperatureCard
    }

    @ViewBuilder
    private var temperatureCard: some View {
        let source = settings.temperatureSource
        if let value = vm.temperature.value(for: source) {
            MetricCard(
                title: tr("dash.card.temperature"),
                icon: "thermometer.medium",
                tint: temperatureTint(value),
                value: ByteFormat.temperature(value),
                caption: tr(source.titleKey),
                action: { detailMetric = .temperature }
            )
        } else {
            MetricCard(
                title: tr("dash.card.temperature"), icon: "thermometer.medium", tint: .gray,
                value: tr("dash.temp.unavailable"),
                caption: tr(vm.temperature.isAvailable ? "sensor.sourceUnavailable" : "dash.temp.unsupported"),
                action: { detailMetric = .temperature }
            )
        }
    }

    private func temperatureTint(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: return AppColor.success
        case ..<80: return AppColor.warning
        default:    return AppColor.danger
        }
    }

    @ViewBuilder
    private var batteryCard: some View {
        if vm.battery.isPresent {
            MetricCard(
                title: tr("dash.card.battery"), icon: vm.battery.isCharging ? "battery.100.bolt" : "battery.75",
                tint: .green,
                value: "\(vm.battery.percentage)", unit: "%",
                progress: Double(vm.battery.percentage) / 100,
                statusText: vm.battery.isCharging ? tr("dash.battery.charging") : (vm.battery.isPluggedIn ? tr("dash.battery.pluggedIn") : tr("dash.battery.onBattery")),
                statusColor: vm.battery.percentage < 20 ? AppColor.danger : AppColor.success,
                action: { detailMetric = .battery }
            )
        } else {
            MetricCard(
                title: tr("dash.card.battery"), icon: "powerplug.fill", tint: .gray,
                value: "AC", caption: tr("dash.battery.noBattery"),
                action: { detailMetric = .battery }
            )
        }
    }

    // MARK: Top processes

    private var topProcesses: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionTitle(tr("dash.topProcesses"))
            VStack(spacing: 0) {
                if vm.topProcesses.isEmpty {
                    Text(tr("dash.measuring")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(vm.topProcesses) { p in
                        ProcessRow(process: p, metric: .cpu)
                        if p.id != vm.topProcesses.last?.id { Divider().opacity(0.4) }
                    }
                }
            }
            .card()
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppServices.shared.settings)
        .frame(width: 1024, height: 800)
}
